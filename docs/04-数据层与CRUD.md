# 04 · 数据层与 CRUD 方法清单

> **状态**：**已实施**
> **核对基线**：提交 `a2a63d8`（2026-10-20），schema v2.2，DB `version = 1`。
> 表语句见 [02-数据库设计.md](./02-数据库设计.md)，本文给**签名级**清单；实现以 `lib/repositories/*.dart` 为准。
> 与原始设计的偏差：`completed_count` 改为**绝对重算**（`CycleCounter.sync`）、新增 `periodic_skips` 墓碑表、生成器改为**一轮一期**（N13）、规则变更**重建未完成计划**（N14）、统计仓库已落地。

---

## 1. 技术选型

| 项 | 选择 | 理由 |
| :-- | :-- | :-- |
| 数据库 | **`sqflite`** | 需求指定 SQLite；支持事务、Batch、外键动作、`ON CONFLICT` |
| 路径 | **`path_provider`** | `getApplicationDocumentsDirectory()`（Android = 应用私有 `app_flutter/`） |
| 测试替身 | `sqflite_common_ffi` | Repository 测试可在桌面/CI 无设备运行；Widget 测试用 `databaseFactoryFfiNoIsolate` |
| 不选 Hive / drift | — | 非关系型不便于周期关联查询；drift 代码生成链路重 |

---

## 2. 目录与分层

```
lib/
├── models/
│   ├── todo.dart / periodic.dart / periodic_item.dart / cycle_rule.dart
│   ├── todo_groups.dart / todo_priority.dart / interval_type.dart
│   └── statistics_models.dart
├── utils/
│   ├── db_helper.dart       # 单例：open / onCreate / onUpgrade / foreign_keys=ON / kSchema
│   ├── date_util.dart       # 日期格式化、加月加年（月末收敛）、日期标签
│   ├── color_util.dart / app_exception.dart / lunar_util.dart
├── repositories/
│   ├── task_repository.dart
│   ├── periodic_repository.dart
│   ├── periodic_item_repository.dart
│   ├── periodic_generator.dart      # 生成引擎（本轮对齐 / 重建）
│   ├── periodic_round_policy.dart   # 「当前轮」唯一口径（纯函数）
│   ├── periodic_completion.dart     # 完成 / 取消完成的轮次联动
│   ├── cycle_counter.dart           # completed_count 绝对重算
│   ├── periodic_skips.dart          # 删除墓碑表读写
│   └── statistics_repository.dart   # 只读聚合
├── logic/                   # 写操作编排：调 repository → 按失效矩阵 invalidate → UI 反馈
├── stores/                  # Riverpod provider（db / todo / periodic / schedule / statistics / invalidation / bootstrap）
└── services/                # 通知 / 系统设置通道 / 设备品牌
```

**约定**

- **业务 SQL（DML）只允许出现在 `repositories/`**；DDL 与 `PRAGMA` 在 `utils/db_helper.dart`；
- `pages/` 不得 import `db_helper`；
- 写操作后按 [失效矩阵](../lib/stores/invalidation.dart) 统一 `invalidate`（三个封装函数）；读刷新/重试可直接 invalidate；
- 周期算术集中在 `models/cycle_rule.dart` 与 `utils/date_util.dart`，**不得**用 SQLite 的 `date(x,'+N month')`（月末溢出为进位而非收敛，实测 `2026-01-31 +1 month = 2026-03-03`）。

---

## 3. 基础设施

### 3.1 `DbHelper`（单例）

| 成员 | 签名 | 说明 |
| :-- | :-- | :-- |
| `database` | `Future<Database> get database` | 懒初始化，并发调用只 open 一次 |
| `_init` | `Future<Database>` | 路径 = `documents/qingyun_todo.db`；`version: 1` |
| `onConfigure` | `(db) => db.execute('PRAGMA foreign_keys = ON')` | **必须**，否则 SET NULL / CASCADE 全部失效 |
| `_onCreate` | `(db, version)` | 执行 [02 §5](./02-数据库设计.md) 全部 DDL（4 表 + 7 索引） |
| `_onUpgrade` | `(db, oldV, newV)` | 目前为空：**1.0 首发后任何 schema 变更都必须升 `kVersion` 并补迁移** |
| `close` / `deleteForTest` | `Future<void>` | 测试与热重启用 |

### 3.2 通用约定

- **时间戳**：`created_at` / `updated_at` 由 Repository 统一写入，页面不传；`update*` 自动刷新 `updated_at`。
- **完成语义**：`toggleComplete` 同时维护 `completed_at`（当前时间或 `NULL`）。
- **删除语义**：硬删除（物理移除）。删除前读出整行快照；`restore` 用 `insertWithId` 按原 id 写回。**周期实例删除还会写 `periodic_skips` 墓碑**（防重新生成），撤销时清墓碑；删除/恢复后重算该周期的 `completed_count`。
- **事务**：跨表写（新增周期 + 周期项 + 首次生成、删除周期、删除周期项、生成实例、完成并判定轮次）必须在 `db.transaction` 内。
- **异常**：Repository 不吞异常，向上抛 `DatabaseException` / `ValidationException`（如 `day_offset` 越界）；由 `logic/app_actions.dart` 或页面转换为 UI 文案。
- **排序**：列表查询以 `sort_order ASC` 作为末位排序键；`remind_time IS NULL` 一律排最后。

---

## 4. CRUD 方法清单

### 4.1 `TaskRepository`（待办任务）

| 方法 | 签名 | 说明 |
| :-- | :-- | :-- |
| 新增 | `Future<int> insert(Todo t)` | 返回自增 id；`created_at`/`updated_at` 由本层写入 |
| 带 id 新增 | `Future<void> insertWithId(Todo t, {DatabaseExecutor? executor})` | **仅供撤销删除**，显式写回原 id |
| 更新 | `Future<int> update(Todo t)` | 按 id 全量更新，自动刷 `updated_at` |
| 删除 | `Future<Todo?> deleteById(int id)` | 事务内：快照 → 删除 → 写墓碑 → `CycleCounter.sync`；返回快照供 5 秒撤销 |
| 批量删除 | `Future<List<Todo>> deleteByIds(List<int> ids)` | 事务内 `IN` 删除，同样写墓碑并重算轮数 |
| 恢复 | `Future<void> restore(Todo t)` | 撤销删除：`insertWithId` + 清墓碑 + 重算轮数 |
| 切换完成 | `Future<void> toggleComplete(int id, {bool? to})` | 写 `is_completed` + `completed_at`；周期实例在同一事务内走 `PeriodicCompletion` |
| 仅写完成字段 | `Future<void> setCompleted(int id, bool completed, {DatabaseExecutor? executor})` | 复用外层事务 |
| 拖拽排序 | `Future<void> reorder(List<int> orderedIds)` | 事务批量写 `sort_order`（**暂无 UI**） |
| 标记已通知 | `Future<void> markNotified(int id)` | `is_notified = 1` |
| 单条查询 | `Future<Todo?> findById(int id, {DatabaseExecutor? executor})` | 编辑页 / 撤销 |
| 全量查询 | `Future<List<Todo>> queryAll()` | 待办页分桶前的基础查询 |
| 分组查询 | `Future<TodoGroups> queryGrouped()` | **待办页主查询**：`queryAll()` → 若有周期实例再读 `periodic_configs` → `PeriodicRoundPolicy.visibleOnTodoPage` 过滤 → Dart 侧分 逾期/今天/明天/后续/已完成（Q10） |
| 按日查询 | `Future<List<Todo>> queryByDate(DateTime date)` | 日程页；`remind_time IS NULL` 排最后 |
| 月历标记 | `Future<Map<String, DayMarkers>> queryMonthMarkers(String monthKey)` | `YYYY-MM` 聚合每天的未完成/已完成条数 |
| 逾期 | `Future<List<Todo>> queryOverdue()` | `is_completed = 0 AND remind_date < today`（**全库口径**，含被隐藏的旧轮实例） |
| 按周期 | `Future<List<Todo>> queryByPeriodicId(int periodicId)` | 周期详情页「近期已生成」 |
| 孤儿历史 | `Future<List<Todo>> queryOrphanPeriodic()` | `source_type='PERIODIC' AND periodic_id IS NULL` |
| 今日进度 | `Future<TodayProgressData> countTodayProgress()` | 仅 `remind_date = today`，含周期实例 |
| 存在性 | `Future<bool> existsInstance(int itemId, int cycleIndex)` | **仅测试/外部校验**；生成器实际用 `_existingKeys` + 墓碑 |
| 待排期 | `Future<List<Todo>> queryRemindable()` | 未完成且带 `remind_time`，按时间升序（通知 reconcile 用） |
| 到点未通知 | `Future<List<Todo>> queryDueForNotify(DateTime now)` | **预留，当前未使用**（通知改用 `queryRemindable` + `computePlan`） |

> **删除与完成的区分（Q5）**：`deleteById` 使记录从列表与**所有统计分母**中消失；`toggleComplete` 保留记录并计入分母与分子。UI 上分别用红色垃圾桶（二次确认 + 5 秒撤销）与绿色勾选（可逆、无确认），不得共用同一手势。

### 4.2 `PeriodicRepository`（周期配置）

| 方法 | 签名 | 说明 |
| :-- | :-- | :-- |
| 新增 | `Future<int> insert(Periodic p, {List<PeriodicItem> items = const []})` | **事务**：写周期 + 周期项 + `generateCurrentRounds`（同事务，失败整体回滚） |
| 更新 | `Future<int> update(Periodic p)` | 校验 → 起始日/间隔变化走 `rebuildPending`（N14），否则 `regenerateAndSync`；缩短周期前须通过 `validateIntervalChange` |
| 启停 | `Future<void> setActive(int id, bool active)` | 暂停只停止生成；重新启用补生成本轮 |
| 保存校验 | `void validateForSave(Periodic p)` | 名称非空、`interval_value >= 1`、终止日不早于起始日 |
| 冲突校验 | `Future<List<PeriodicItem>> validateIntervalChange(Periodic p)` | `day_offset >= minCycleLength` 的周期项；非空则阻止保存（Q12） |
| 删除预览 | `Future<PeriodicDeleteResult> previewDelete(int id)` | 确认弹窗的「删 N 条未完成 / 保留 M 条已完成」 |
| 删除 | `Future<PeriodicDeleteResult> deleteById(int id)` | **事务，条件删除**：① 删未完成实例 ② 删周期本体（周期项 CASCADE，剩余已完成实例外键 SET NULL） |
| 列表 | `Future<List<Periodic>> queryAll({bool onlyActive = false})` | **仅测试使用**；页面用 `queryListWithProgress` |
| 列表 + 进度 | `Future<List<PeriodicListEntry>> queryListWithProgress()` | 周期页主查询：3 条聚合（周期 / 轮次进度 / 下次提醒）；「当前轮」走 `PeriodicRoundPolicy` |
| 详情 | `Future<PeriodicDetail?> queryDetail(int id)` | 周期 + 周期项 + 统计 + 本轮进度 + 下次提醒；周期不存在返回 null |
| 本轮进度 | `Future<CycleProgress?> queryCurrentCycleProgress(int id)` | 与 `PeriodicRoundPolicy` 同源；无实例返回 null |
| 下次提醒 | `Future<Todo?> queryNextRemind(int id)` | 最近的未完成实例（卡片副标题） |
| 孤儿历史 | `Future<List<Todo>> queryOrphanPeriodic()` | 同 `TaskRepository` |
| 完成回调 | `Future<void> onInstanceCompleted(Todo t)` / `onInstanceUncompleted(Todo t)` | 透传 `PeriodicCompletion` |

### 4.3 `PeriodicItemRepository`（周期项 / 模板）

| 方法 | 签名 | 说明 |
| :-- | :-- | :-- |
| 天序校验 | `static void validateDayOffset(int dayOffset, CycleRule rule, {String? title})` | `0 <= day_offset < minCycleLength`，越界抛 `ValidationException` |
| 新增 | `Future<int> insert(PeriodicItem item)` | 校验 → 落库 → `regenerateAndSync` |
| 更新 | `Future<int> update(PeriodicItem item)` | 校验；**天序 / 提醒时间变化**走 `rebuildPending(onlyItemId)`（N14）；其余字段不追溯（Q8） |
| 删除 | `Future<ItemDeleteResult> deleteById(int id)` | 删未完成实例 → 删模板行（已完成保留，`periodic_item_id` SET NULL）→ `regenerateAndSync` |
| 删除预览 | `Future<ItemDeleteResult> previewDelete(int id)` | 确认文案数据 |
| 删除未来实例 | `Future<int> deleteFutureInstances(int id, {DateTime? fromDate})` | 写墓碑（`FUTURE_DELETED`）+ 删除 + `CycleCounter.sync`，**不重新生成**；`fromDate` 默认今天，逾期实例传该实例日期（N22） |
| 未来实例计数 | `Future<int> countFutureInstances(int itemId, {DateTime? fromDate})` | 三级删除动作表文案 |
| 已生成计数 | `Future<int> countGeneratedInstances(int itemId)` | 编辑页「已生成过 N 条」提示 |
| 按周期查询 | `Future<List<PeriodicItem>> queryByPeriodicId(int id)` | 按 `day_offset, sort_order` 升序 |
| 按天查询 | `Future<List<PeriodicItem>> queryByDayOffset(int periodicId, int dayOffset)` | **当前未使用**（详情页用 `itemsByDay`） |
| 重排 | `Future<void> reorder(int periodicId, List<int> orderedIds)` | 事务批量写 `sort_order`（**暂无 UI**） |

### 4.4 `StatisticsRepository`（只读聚合）

| 方法 | 签名 | 口径 |
| :-- | :-- | :-- |
| 区间完成率 | `Future<RateStat> completionRate(String from, String to)` | 按 `remind_date` |
| 本周点阵 | `Future<List<WeekDayCell>> weekCells(DateTime today)` | 周一~周日，按 `remind_date` |
| 连续打卡 | `Future<int> currentStreak()` | 按 `completed_at` 去重回溯（今天未完成从昨天起算） |
| 逾期数 | `Future<int> countOverdue()` | 全库、实时派生 |
| 待处理数 | `Future<int> countPending()` | 全库未完成 |
| 周期完成率 | `Future<RateStat> periodicDueRate()` | `source_type='PERIODIC' AND remind_date <= today`（含孤儿） |
| 完成趋势 | `Future<List<TrendPoint>> completionTrend({required String from, required String to, required TrendGranularity granularity})` | 按 `completed_at`；粒度 hour/day/month |
| 优先级分布 | `Future<List<PrioritySlice>> priorityDistribution(String from, String to)` | 范围内全部任务 |
| 星期分布 | `Future<List<WeekdayBar>> weekdayDistribution(String from, String to)` | 按 `remind_date` 的 `strftime('%w')` |
| 范围总数 | `Future<int> countInRange(String from, String to)` | 图表空态判断 |
| 月历热力 | `Future<Map<String, int>> completionHeatmap(String monthKey)` | 按 `completed_at` |

**统计口径要点**：① 硬删除不计入任何分母；② 孤儿已完成实例**仍计入**周期完成率（`source_type` 判定）；③ 完成率按 `remind_date`、趋势按 `completed_at`，不可混用；④ **M4/M5/M6 是全库口径**，会把待办页隐藏的旧轮实例算进去（已知差异，见 [05 §1](./05-统计指标建议.md)）。

---

## 5. 周期实例生成算法（一轮一期）

```
generateCurrentRounds(today)            // 启动 / 跨日 / 重新启用
  for each periodic in periodic_configs where is_active = 1:
      if end_date != null && end_date < today: continue
      items = periodic_items where periodic_id = ?
      if items.isEmpty: continue
      instances = (cycle_index, is_completed) 全部实例
      kCur = PeriodicRoundPolicy.currentRound(rule, instances, today)
             // 最早的未完成轮；该轮窗口已整轮走完 → 顺延到「今天所在轮」；
             // 全部完结 / 无实例 → max(今天所在轮, 已有最大轮次 + 1)
      insertIgnore(kCur 的每一项)        // 短月份跳过 / 不补历史 / end_date 截断
      // 不清理 > kCur 的实例（N21：否则取消完成后会删掉下一轮）
```

```
generateForPeriodicId(id)               // 新建 / 修改周期或周期项后、本轮完结后
  = 只对指定周期执行上面的对齐逻辑
```

```
rebuildPending(id, {onlyItemId})        // 新规则生效（N14）
  ceiling = max(0, 今天所在轮)，跳过已整轮完成的轮次（防御上限 kRebuildProbeLimit=400）
  删除该周期（或该事项）的**全部未完成实例**
  按新规则写入 ceiling 轮 → 再删除 > ceiling 的未完成实例
  已完成实例完全不动
```

| 要点 | 说明 |
| :-- | :-- |
| 幂等 | `INSERT … ON CONFLICT(periodic_item_id, cycle_index) DO NOTHING` + 唯一索引 |
| **墓碑跳过** | 生成前取回 `periodic_skips` 的 `(周期项, 轮次)` 键，命中则跳过；撤销删除清墓碑 |
| **一轮一期** | 只保证「本轮」存在；本轮完成或整轮逾期才推进；下一轮实例**一旦生成就保留**（N21） |
| **规则变更** | 已完成实例保持原日期；未完成计划按新规则从今天所在轮重建（N14） |
| **轮次计数** | `CycleCounter.sync` 绝对重算「有 ≥1 条实例且无未完成实例」的轮数 |
| 触发时机 | ① 启动 ② 新建/修改周期或周期项后 ③ 完成一轮后 ④ 回前台且跨日 |
| 名称快照 | 生成时写 `periodic_name_snapshot`，周期改名不回写 |
| 异常 | 启动路径由 `bootstrapApp` 捕获并 `debugPrint`；写路径异常抛给页面并回滚事务 |

---

## 6. 典型调用链

| 场景 | 调用链 |
| :-- | :-- |
| 打开待办页 | `todoGroupsProvider` → `queryGrouped()`；`todayProgressProvider` → `countTodayProgress()` |
| 勾选完成（列表/日程） | `toggleTodoComplete` → `toggleComplete` → `invalidateAfterTaskWrite` → FutureProvider 重取 |
| 完成（编辑页） | 同上，成功后 `Navigator.pop`（失败留在原页；若表单有未保存修改先落盘） |
| 取消完成周期实例 | `toggleComplete(id, to: false)` → `onInstanceUncompleted` → `CycleCounter.sync` |
| 删除单条待办 | `requestDeleteTodo` → 二次确认 → `deleteById` → SnackBar（5 秒撤销 → `restore`） |
| 删除周期实例（三级） | 只删这一次 = `TaskRepository.deleteById`；删该事项未来 = `deleteFutureInstances(fromDate)`；删整个周期 = `PeriodicRepository.deleteById` |
| 删除周期 | `previewDelete` → 三选一弹窗（取消 / 暂停并保留 / 删除）→ `deleteById` |
| 新建周期 | `PeriodicRepository.insert(p, items: […])`（事务内含生成）→ `invalidateAfterPeriodicWrite` |
| 修改周期规则 | `validateIntervalChange` → 冲突则弹窗中止 → 规则变化 `rebuildPending`，否则 `regenerateAndSync` |
| 修改周期项 | 天序/时间变 → `rebuildPending(onlyItemId)`；否则 `regenerateAndSync` |
| 日程页点日期 | `dayTasksProvider(dateKey)` → `queryByDate` |
| 统计页 | `StatisticsRepository.*` 并行查询后组装 |

---

## 7. 测试要点

| 目标 | 用例 |
| :-- | :-- |
| 周期算术 | DAY/WEEK 日期序列；**MONTH 日号锚定**（`start=2026-09-01` → 10-01、11-01…）；**月末收敛**（`2026-01-31 + 1 月 → 2026-02-28`）；YEAR 闰年（2024-02-29 + 1 年 → 2025-02-28） |
| 轮长度 | MONTH 28–31、YEAR 365/366 |
| 跳过规则 | `day_offset >= cycleLength(k)` 该轮跳过（测试直接写库构造；**UI 不可保存 MONTH 的 28**） |
| `day_offset` 校验 | MONTH 下 `day_offset=28` 被拒（须 < 28）；DAY/2 下 `day_offset=2` 被拒 |
| 缩短周期 | 每 3 天含 `day_offset=2`，改为每 2 天 → 冲突并阻止保存（Q12） |
| 生成幂等 | 同一轮连续调用两次，行数不变 |
| 唯一索引 | 重复 `(periodic_item_id, cycle_index)` 被拒绝 |
| **一轮一期** | 只生成本轮；本轮完成生成下一轮；**取消完成后重启不丢下一轮（N21）**；未来轮实例保留（不展示） |
| **当前轮口径** | 整轮逾期顺延；`queryDetail` / `queryListWithProgress` 与 `PeriodicRoundPolicy` 一致（N21） |
| **删除周期** | 未完成实例删、已完成实例保留且外键为 NULL、`cycle_index` 与快照名保留、周期项清空 |
| **删除周期项** | 删未完成、保留已完成；未来实例删除接口不影响已完成 |
| **删除未来实例** | 写墓碑、不复活；**逾期实例传 `fromDate` 时连同该条一起删除（N22）** |
| 外键开关 | 断言 `PRAGMA foreign_keys` 已开启 |
| CHECK 约束 | `interval_value=0`、非法 `interval_type`/`priority`/`is_completed` 被拒 |
| 完成回调 | 一轮最后一项完成 → `completed_count` 重算；取消完成回退；删除唯一未完成项视为完结 |
| 删除撤销 | 快照 `restore` 后 id、`completed_at`、`sort_order` 一致，墓碑已清 |
| 统计口径 | 硬删除不进分母；孤儿已完成计入周期完成率 |

运行方式：`flutter test`（`sqflite_common_ffi` 内存库，无需真机）；Widget 测试用 `databaseFactoryFfiNoIsolate`（见 [03 §7.2 N3](./03-架构与现状.md)）。
