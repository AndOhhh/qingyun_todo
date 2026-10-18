# 04 · 数据层与 CRUD 方法清单

> **状态**：**已实施**（提交 `9c74fe6`），对齐 schema v2.2 与 2026-09-25 评审决策。
> 与本文签名清单的 3 处偏差见 [07 §I.2](./07-开发计划-待办与周期.md)：`completed_count` 改为绝对重算、
> 新增 `generateCycle`、新增 `periodic_skips` 墓碑表；`StatisticsRepository` 随统计页（Phase 5）再做。
> 原始需求点名要求"生成 sqlite 的数据表语句，以及需要用到的方法（CRUD）"——表语句见 [02-数据库设计.md](./02-数据库设计.md)，方法清单见本文。
> 本文给出**签名级**描述（便于评估工作量与接口一致性），落地计划见 [07-开发计划-待办与周期.md](./07-开发计划-待办与周期.md)。

---

## 1. 技术选型

| 项 | 选择 | 理由 |
| :-- | :-- | :-- |
| 数据库 | **`sqflite`** | 原始需求明确指定 SQLite；支持 `Transaction`、`Batch`、外键动作、`ON CONFLICT` |
| 路径 | **`path_provider`** | 取 `getApplicationDocumentsDirectory()`；Android 侧亦可用 `getDatabasesPath()` |
| 测试替身 | `sqflite_common_ffi` | 让 Repository 测试可在桌面/CI 无设备环境运行 |
| 不选 Hive | — | 非关系型，周期实例与模板的关联查询需自行实现 |
| 不选 drift | — | 代码生成链路重，对当前 3 张表规模收益不足 |

版本号在 `flutter pub add` 时以实际解析结果为准，文档不写死。

---

## 2. 目录与分层

```
lib/
├── models/
│   ├── todo.dart            # 改造：id→int、note→remark、拆 remindDate/remindTime、
│   │                        #       isOverdue 改派生 getter、done 改不可变、移除 subDone/subTotal
│   ├── todo_priority.dart   # 从 todo.dart 抽出：枚举 ↔ name ↔ Color
│   ├── periodic.dart        # 新增：对应 periodic_configs（含 intervalType/intervalValue + label）
│   ├── periodic_item.dart   # 新增：对应 periodic_items
│   └── cycle_rule.dart      # 新增：cycleStart(k) / cycleLength(k) / minCycleLength 纯函数（可单测）
├── utils/
│   ├── db_helper.dart       # sqflite 单例：open / onCreate / onUpgrade / foreign_keys=ON
│   ├── date_util.dart       # 日期时间格式化、加月加年（含月末收敛）、日期标签
│   └── color_util.dart      # Color ↔ #RRGGBB
├── repositories/
│   ├── task_repository.dart
│   ├── periodic_repository.dart
│   ├── periodic_item_repository.dart
│   ├── periodic_generator.dart      # 生成引擎（窗口生成 / 单周期生成 / 生成下一轮）
│   ├── periodic_completion.dart     # 完成 / 取消完成的轮次联动
│   ├── cycle_counter.dart           # completed_count 绝对重算
│   ├── periodic_skips.dart          # 删除墓碑表读写
│   └── statistics_repository.dart   # 只读聚合查询，供统计页使用（Phase 5，尚未建）
├── logic/                   # 写操作编排：调 repository → 按失效矩阵 invalidate → UI 反馈
└── stores/                  # Riverpod provider（db_providers / todo_store / periodic_store / invalidation / bootstrap）
```

**约定**：SQL 只允许出现在 `repositories/`；`pages/` 不得 import `db_helper`；写操作后按 [07 §A.1 失效矩阵](./07-开发计划-待办与周期.md) 统一 `ref.invalidate`。周期日期算术集中在 `models/cycle_rule.dart` 与 `utils/date_util.dart`，**不得**用 SQLite 的 `date(x,'+N month')`（月末溢出为进位而非收敛，实测 `2026-01-31 +1 month = 2026-03-03`）。

---

## 3. 基础设施

### 3.1 `DbHelper`（单例）

| 成员 | 签名 | 说明 |
| :-- | :-- | :-- |
| `database` | `Future<Database> get database` | 懒初始化，并发调用只 open 一次 |
| `_initDb` | `Future<Database>` | 路径 = documents/`qingyun_todo.db`；`version: 1` |
| `onConfigure` | `(db) => db.execute('PRAGMA foreign_keys = ON')` | **必须**，否则 SET NULL / CASCADE 全部失效，周期删除会留下悬挂外键 |
| `_onCreate` | `(db, version)` | 执行 [02 §5](./02-数据库设计.md) 全部 DDL + 7 条索引 |
| `_onUpgrade` | `(db, oldV, newV)` | v1 阶段留空壳 + 注释；后续按 `oldV` 分段迁移 |
| `close` | `Future<void> close()` | 测试与热重启用 |

### 3.2 通用约定

- **时间戳**：`created_at` / `updated_at` 由 Repository 统一写入，页面不传；`update*` 自动刷新 `updated_at`。
- **完成语义**：`toggleComplete` 同时维护 `completed_at`（写入当前时间或置 `NULL`）。
- **删除语义**：硬删除（物理移除）。为支持"撤销"，删除前先读出整行快照，`restore` 时用 `insertWithId` 按原 id 写回。
- **事务**：跨表写（新增周期 + 周期项、删除周期、删除周期项、生成实例、完成并判定轮次）必须在 `db.transaction` 内。
- **异常**：Repository 不吞异常，向上抛 `DatabaseException` / 自定义 `ValidationException`（如 `day_offset` 越界）；由 store 层转换为 UI 可展示状态。
- **排序**：列表查询统一以 `sort_order ASC` 作为末位排序键。

---

## 4. CRUD 方法清单

### 4.1 `TaskRepository`（待办任务）

| 方法 | 签名 | 说明 |
| :-- | :-- | :-- |
| 新增 | `Future<int> insert(Task t)` | 返回自增 id；常规待办入口 |
| 带 id 新增 | `Future<void> insertWithId(Task t)` | **仅供撤销删除使用**，显式写回原 id |
| 更新 | `Future<int> update(Task t)` | 按 id 全量更新，自动刷 `updated_at` |
| 删除 | `Future<Task?> deleteById(int id)` | 物理删除并**返回被删快照**（供 SnackBar 撤销）；无论完成与否一律真删 |
| 批量删除 | `Future<List<Task>> deleteByIds(List<int> ids)` | 事务内 `IN` 删除，返回快照列表 |
| 恢复 | `Future<void> restore(Task t)` | 撤销删除：调用 `insertWithId` |
| 切换完成 | `Future<void> toggleComplete(int id, {bool? to})` | 写 `is_completed` + `completed_at`；周期实例在事务内追加 `PeriodicRepository.onInstanceCompleted` / `onInstanceUncompleted` |
| 分组查询 | `Future<TodoGroups> queryGrouped()` | **待办页主查询**：一次取回全部，Dart 侧分为 逾期/今天/明天/后续/已完成（Q10） |
| 按日查询 | `Future<List<Task>> queryByDate(String date)` | 日程页用 |
| 逾期 | `Future<List<Task>> queryOverdue()` | `is_completed = 0 AND remind_date < today` |
| 按周期 | `Future<List<Task>> queryByPeriodicId(int periodicId)` | 周期详情页 |
| 孤儿历史 | `Future<List<Task>> queryOrphanPeriodic()` | `source_type='PERIODIC' AND periodic_id IS NULL`（来源周期已删） |
| 今日进度 | `Future<TodayProgressData> countTodayProgress()` | 返回 `(total, done)`，仅统计 `remind_date = today`，含周期实例 |
| 存在性 | `Future<bool> existsInstance(int itemId, int cycleIndex)` | 生成前幂等判断（唯一索引兜底） |
| 排序 | `Future<void> reorder(List<int> orderedIds)` | 事务内批量写 `sort_order`（Phase 7 拖拽） |
| 通知 | `Future<void> markNotified(int id)` / `queryDueForNotify(DateTime now)` | Phase 6 |

> **删除与完成的区分（Q5）**：`deleteById` 使记录从列表与**所有统计分母**中消失；`toggleComplete` 保留记录并计入分母与分子。两者在 UI 上分别用红色垃圾桶（需二次确认 + 撤销）与绿色勾选（可逆、无确认），不得共用同一手势方向。

### 4.2 `PeriodicRepository`（周期配置）

| 方法 | 签名 | 说明 |
| :-- | :-- | :-- |
| 新增 | `Future<int> insert(Periodic p, {List<PeriodicItem> items = const []})` | **事务**：写周期 + 初始周期项，随后触发生成 |
| 更新 | `Future<int> update(Periodic p)` | 修改 `start_date` / `interval_*` 遵循 Q8（已生成实例不变）；缩短周期前须通过 `validateIntervalChange` |
| 校验 | `Future<List<PeriodicItem>> validateIntervalChange(Periodic p)` | 返回 `day_offset` 越界的周期项列表；非空则**阻止保存**（Q12） |
| 删除 | `Future<PeriodicDeleteResult> deleteById(int id)` | **事务，条件删除**：① `DELETE FROM tasks WHERE periodic_id=? AND is_completed=0` ② `DELETE FROM periodic_configs WHERE id=?`（周期项 CASCADE，剩余已完成实例的 FK 自动 SET NULL）。返回 `(删除的未完成数, 保留的已完成数)` 供 UI 提示 |
| 启停 | `Future<void> setActive(int id, bool active)` | 暂停后停止生成新实例，已有实例保留 |
| 列表 | `Future<List<Periodic>> queryAll({bool onlyActive = false})` | 周期页 |
| 详情 | `Future<PeriodicDetail> queryDetail(int id)` | 聚合：周期 + 周期项（按 `day_offset`）+ 统计（总实例、已完成、完成率、当前轮次进度） |
| 本轮进度 | `Future<CycleProgress> queryCurrentCycleProgress(int id)` | `(done, total)`，对应 [02 §8.7](./02-数据库设计.md) |
| 下次提醒 | `Future<Task?> queryNextRemind(int id)` | 对应 [02 §8.8](./02-数据库设计.md)，卡片副标题 |
| ~~轮次 +1~~ | ~~`incrementCompletedCount(int id)`~~ | **未实现**：改由 `CycleCounter.sync` 绝对重算（幂等，且天然满足 Q13 的回退语义） |
| ~~轮次 −1~~ | ~~`decrementCompletedCount(int id)`~~ | 同上 |
| 完成回调 | `Future<void> onInstanceCompleted(Task t)` | 事务内：查该轮未完成数 → 为 0 则 `completed_count += 1` → 生成下一轮 |
| 取消完成回调 | `Future<void> onInstanceUncompleted(Task t)` | 事务内：若该轮此前已判定完结，则 `completed_count -= 1` |
| 下一轮次 | `Future<int> nextCycleIndex(int id)` | `MAX(cycle_index) + 1`，无实例时为 0 |

### 4.3 `PeriodicItemRepository`（周期项 / 模板）

| 方法 | 签名 | 说明 |
| :-- | :-- | :-- |
| 新增 | `Future<int> insert(PeriodicItem item)` | 校验 `0 <= day_offset < minCycleLength(cycleRule)`，越界抛 `ValidationException` |
| 更新 | `Future<int> update(PeriodicItem item)` | 同上校验；改动不追溯已生成实例（Q8） |
| 删除 | `Future<ItemDeleteResult> deleteById(int id)` | **条件删除**：① 删该项未完成实例 ② 删模板行（已完成实例保留，`periodic_item_id` 自动 SET NULL）。返回 `(删除数, 保留数)` |
| 删除未来实例 | `Future<int> deleteFutureInstances(int id, {String? fromDate})` | 三级删除语义之一（Q9）："删该周期项的未来实例"，已完成的一律不动 |
| 按周期查询 | `Future<List<PeriodicItem>> queryByPeriodicId(int id)` | 按 `day_offset, sort_order` 升序 |
| 按天查询 | `Future<List<PeriodicItem>> queryByDayOffset(int periodicId, int dayOffset)` | 周期管理页分天分组 |
| 重排 | `Future<void> reorder(int periodicId, List<int> orderedIds)` | 事务批量写 `sort_order` |

### 4.4 `StatisticsRepository`（只读聚合）

| 方法 | 说明 |
| :-- | :-- |
| `completionRate(String from, String to)` | 区间完成率，按 `remind_date` 归属 |
| `dailyTrend(int days)` | 近 N 天每日完成数，按 `completed_at` 归属 |
| `countOverdue()` / `countPending()` | 逾期数 / 待处理数 |
| `currentStreak()` | 连续打卡天数（今天未完成时从昨天起算，不断链） |
| `avgCompletionHours(int days)` | `completed_at - created_at` 均值 |
| `priorityDistribution()` | 按 `priority` 分组（环形图） |
| `weekdayDistribution(int days)` | 按 `strftime('%w', remind_date)` 分组（柱状图） |
| `periodicCompletionRate()` | 周期实例完成率（**含孤儿历史记录**，见下） |
| `monthHeatmap(int year, int month)` | 月历热力图每日完成数 |

**统计口径要点**：① 硬删除的记录不在任何分母中出现；② 来源周期已删除的孤儿已完成实例**仍计入**历史完成率（`source_type='PERIODIC'` 判定，与 `periodic_id` 是否为空无关）；③ 完成率按 `remind_date` 归属、完成趋势按 `completed_at` 归属，两者不可混用。详见 [05](./05-统计指标建议.md)。

---

## 5. 周期实例生成算法

```
ensureCurrentCycleInstances(today)          // 一轮一期（N13）：App 启动 + 跨日 + 新建/修改 + 本轮完结时触发
  for each periodic in periodicRepository.queryAll(onlyActive: true):
      if periodic.endDate != null && periodic.endDate < today: continue
      rule = CycleRule(periodic.intervalType, periodic.intervalValue, periodic.startDate)
      kCur = PeriodicRoundPolicy.currentRound(rule, instancesOf(periodic), today)
             // 最早的未完成轮；该轮窗口已整轮走完 → 顺延到「今天所在轮」；
             // 全部完结 / 无实例 → max(今天所在轮, 已有最大轮次 + 1)
      cycleStart = rule.cycleStart(kCur)
      cycleLen   = rule.cycleLength(kCur)
      for each item in periodicItemRepository.queryByPeriodicId(periodic.id):
          if item.dayOffset >= cycleLen: continue           // 短月份跳过（§7.2）
          remindDate = cycleStart + item.dayOffset 天
          if remindDate < today: continue                   // 不补生成历史（Q1）
          if periodic.endDate != null && remindDate > periodic.endDate: continue
          insertIgnore(Task(                                // ON CONFLICT DO NOTHING
              title: item.title, remark: item.remark,
              remind_date: remindDate, remind_time: item.remindTime,
              priority: item.priority, accent_color: item.accentColor,
              source_type: 'PERIODIC', periodic_id: periodic.id,
              periodic_item_id: item.id, cycle_index: kCur,
              periodic_name_snapshot: periodic.name))       // 名称快照，供周期删除后展示
      deletePending(cycle_index > kCur)                     // 旧口径遗留的未来未完成轮次清理
```

| 要点 | 说明 |
| :-- | :-- |
| 幂等 | `INSERT … ON CONFLICT(periodic_item_id, cycle_index) DO NOTHING` + 唯一索引，重复调用无副作用 |
| **墓碑跳过** | 生成前先取回 `periodic_skips` 中该周期的全部 `(周期项, 轮次)` 键，命中则跳过：硬删除的实例不会被写回（schema v2.2 / docs/02 §4.4）。撤销删除时清除墓碑 |
| **一轮一期** | 只保证「本轮」实例存在，不再预生成未来 30 天：本轮未结束不推进；本轮完成（`PeriodicCompletion` → 下一轮）或整轮逾期（启动/跨日时顺延到「今天所在轮」）才推进。生成与**待办页展示**共用 `PeriodicRoundPolicy`，避免两边口径不一致 |
| **旧口径遗留** | 晚于本轮的未完成实例在生成时删除；早于本轮的未完成实例（错过的那一轮）**保留在库中**，仅不进入待办页（日程页/统计口径不变，非破坏性） |
| **轮次计数** | `CycleCounter.sync` 绝对重算「拥有 ≥1 条实例且无未完成实例」的轮数，替代 `±1` 增减；一个实现同时满足 TC-08/09/10 |
| 预生成口径 | **一轮一期**：只保证每个周期「本轮」实例存在（见上表），不再有 30 天窗口常量 |
| 触发时机 | ① App 启动（`DbHelper` 就绪后）② 新建/修改周期或周期项后 ③ 完成一轮后生成下一轮 ④ 跨日（定时器或页面 resume 时校验） |
| 历史实例 | 默认**不补生成**过去日期（Q1） |
| 名称快照 | 生成时写入 `periodic_name_snapshot`，之后周期改名**不回写**已有实例（保持历史真实） |
| 轮次完结 | `onInstanceCompleted` 判定该轮未完成数为 0 → `completed_count += 1` → 对齐下一轮；手动删除的实例不参与判定 |
| 性能 | 全部写入包在一个事务里；每次只写一轮 × 数项 ≈ 十级行 |
| 异常 | 生成失败不得阻塞 UI：捕获异常 + 日志，下次触发时重试（幂等保证安全） |

---

## 6. 典型调用链

| 场景 | 调用链 |
| :-- | :-- |
| 打开待办页 | `TaskRepository.queryGrouped()` + `countTodayProgress()` → store 分组 → 页面渲染 |
| 勾选完成常规待办 | `toggleComplete(id)` → store 局部更新 |
| 勾选完成周期实例 | `toggleComplete(id)` → 事务内 `onInstanceCompleted` → 判定轮次完结 → `incrementCompletedCount` → 生成下一轮 |
| 取消完成周期实例 | `toggleComplete(id, to: false)` → `onInstanceUncompleted` → 必要时 `decrementCompletedCount` |
| 删除单条待办 | `deleteById(id)` 返回快照 → UI 展示 SnackBar → 5 秒内撤销则 `restore(snapshot)` |
| 删除周期实例（三级） | 删这一次 = `TaskRepository.deleteById`；删该周期项未来实例 = `PeriodicItemRepository.deleteFutureInstances`；删整个周期 = `PeriodicRepository.deleteById` |
| 删除周期 | `validate → PeriodicRepository.deleteById`（事务）→ 返回 `(删除 N 条未完成, 保留 M 条已完成)` → 确认弹窗前置展示该数字 |
| 新建周期 | `PeriodicRepository.insert(p, items: […])`（事务）→ `generatePeriodicInstances` → 刷新周期页与待办页 |
| 修改周期规则 | `validateIntervalChange` → 有冲突则中止并列出冲突项 → 无冲突则 `update` → 重新生成未来实例 |
| 日程页点日期 | `TaskRepository.queryByDate(date)` |
| 统计页 | `StatisticsRepository.*` 并行查询后组装 |

---

## 7. 测试要点

| 目标 | 用例 |
| :-- | :-- |
| 周期算术 | DAY/WEEK 日期序列正确；**MONTH 日号锚定**（`start=2026-09-01` → 10-01、11-01…）；**月末收敛**（`start=2026-01-31` + 1 月 → `2026-02-28`，不得为 03-03）；YEAR 闰年（2024-02-29 + 1 年 → 2025-02-28） |
| 轮长度 | `cycleLength` 对 MONTH 返回 28–31、YEAR 返回 365/366 |
| 跳过规则 | 每月周期 + `day_offset=28`，2 月轮次跳过该项（对照 [02 §7.4 示例 2](./02-数据库设计.md)） |
| `day_offset` 校验 | MONTH 类型下 `day_offset=28` 被拒（须 < 28）；DAY/2 下 `day_offset=2` 被拒 |
| 缩短周期 | 每 3 天含 `day_offset=2` 的项，改为每 2 天 → `validateIntervalChange` 返回冲突项并阻止保存（Q12） |
| 生成幂等 | 同一窗口连续调用两次，行数不变 |
| 唯一索引 | 手动插入重复 `(periodic_item_id, cycle_index)` 被拒绝 |
| **删除周期** | 未完成实例被删、**已完成实例保留**且 `periodic_id`/`periodic_item_id` 为 NULL、`cycle_index` 与 `periodic_name_snapshot` 保留、`periodic_items` 清空 |
| **删除周期项** | 同上规则；未来实例删除接口不影响已完成实例 |
| 外键开关 | 未开 `PRAGMA foreign_keys` 时删除周期会留下悬挂外键 → 断言 `DbHelper` 已开启 |
| CHECK 约束 | `interval_value=0`、`interval_type='FORTNIGHT'`、`priority='urgent'`、`is_completed=2` 均被拒 |
| 完成回调 | 一轮内最后一项完成 → `completed_count` +1；取消完成 → −1；删除唯一未完成项后 → 视为完结 |
| 删除撤销 | `deleteById` 返回的快照经 `restore` 后 id、`completed_at`、`sort_order` 完全一致 |
| 统计口径 | 硬删除的记录不进入分母；孤儿已完成实例仍计入周期完成率 |

运行方式：`sqflite_common_ffi` + `databaseFactoryFfi`，`flutter test`，无需真机（Phase 1 起建立 `test/` 目录）。周期算术与 `cycleLength` 为纯函数，优先覆盖。
