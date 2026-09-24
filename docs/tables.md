# 数据库表结构


### 周期配置表：`periodic_configs`

| 字段名 | 数据类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | 主键 ID，自增 |
| `name` | TEXT | NOT NULL | 周期名称（如“隔天喝饮品计划”） |
| `start_date` | TEXT | NOT NULL | 周期起始日期，格式为 `YYYY-MM-DD`，该日期视为周期第 1 天 |
| `interval_days` | INTEGER | NOT NULL DEFAULT 1 | 自定义周期间隔天数（如每 2 天则为 2，每天则为 1） |
| `completed_count` | INTEGER | NOT NULL DEFAULT 0 | **周期已循环完结次数**（冗余字段，便于快速统计） |
| `remark` | TEXT | | 周期备注信息（可选） |
| `create_time` | TEXT | NOT NULL | 记录创建时间（格式：`YYYY-MM-DD HH:mm:ss`） |
| `update_time` | TEXT | NOT NULL | 记录最后更新时间（格式同上） |

---

### 表2：`tasks`（待办任务表）

| 字段名 | 数据类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | 主键 ID，自增 |
| `title` | TEXT | NOT NULL | 待办事项标题 |
| `remark` | TEXT | | 备注信息（可选） |
| `remind_date` | TEXT | NOT NULL | 提醒日期，格式 `YYYY-MM-DD`（常规任务由用户指定，周期任务由周期规则自动推算） |
| `remind_time` | TEXT | | 提醒时间点，格式 `HH:mm`（常规与周期实例均可独立设置） |
| `priority_color` | TEXT | | 优先级颜色标识（如 `#FF0000` 或 `high`/`medium`/`low`，业务自定义） |
| `is_completed` | INTEGER | DEFAULT 0 | 完成状态：`0` 表示未完成，`1` 表示已完成 |
| `periodic_id` | INTEGER | DEFAULT NULL | 关联的周期配置 ID。若为 `NULL` 表示为常规待办；若不为 `NULL` 表示该任务属于某个周期配置 |
| `source_type` | TEXT | DEFAULT 'REGULAR' | 类型标识：`'REGULAR'` 表示常规待办，`'PERIODIC'` 表示周期待办实例 |
| `created_at` | TEXT | NOT NULL | 记录创建时间（格式：`YYYY-MM-DD HH:mm:ss`） |
| `updated_at` | TEXT | NOT NULL | 记录最后更新时间（格式同上） |

---

如需调整或补充说明，请随时告知。


```sql
-- 周期配置表
CREATE TABLE periodic_configs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    start_date TEXT NOT NULL,
    interval_days INTEGER NOT NULL DEFAULT 1,
    completed_count INTEGER NOT NULL DEFAULT 0, 
    remark TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- 待办任务表
CREATE TABLE tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    remark TEXT,
    remind_date TEXT NOT NULL,
    remind_time TEXT,  -- 独立控制时间点
    priority_color TEXT,
    is_completed INTEGER DEFAULT 0,
    periodic_id INTEGER DEFAULT NULL,
    source_type TEXT DEFAULT 'REGULAR',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```