import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite 单例（docs/04 §3.1）。
///
/// - `onConfigure` 中开启 `PRAGMA foreign_keys = ON`：**必须**，否则
///   `ON DELETE SET NULL` / `CASCADE` 全部静默失效，删除周期会留下悬挂外键。
/// - `onCreate` 执行 schema v2.1 的 3 张业务表 + 墓碑表 + 7 条索引（docs/02 §5）。
/// - 测试用 `sqflite_common_ffi` 时通过构造参数注入 [factory] 与 [path]。
class DbHelper {
  DbHelper({DatabaseFactory? factory, String? path, this.verbose = false})
      : _factory = factory,
        _path = path;

  /// App 运行期单例
  static final DbHelper instance = DbHelper();

  /// DB 版本号。v1 = schema v2.1 首次建库，无历史数据需要迁移（docs/02 §6.2）。
  static const int kVersion = 1;

  /// 默认库文件名
  static const String kDbName = 'qingyun_todo.db';

  final DatabaseFactory? _factory;
  final String? _path;

  /// 是否打印建库日志
  final bool verbose;

  Database? _db;
  Future<Database>? _opening;

  /// 懒初始化；并发调用只会真正 open 一次
  Future<Database> get database {
    final existing = _db;
    if (existing != null) return Future<Database>.value(existing);
    return _opening ??= _init().whenComplete(() => _opening = null);
  }

  Future<Database> _init() async {
    final factory = _factory ?? databaseFactory;
    final path = _path ?? '${await _defaultDir()}/$kDbName';
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: kVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onDowngrade: onDatabaseDowngradeDelete,
      ),
    );
    _db = db;
    return db;
  }

  Future<String> _defaultDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// 开启外键约束（见类注释）
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    for (final statement in kSchema) {
      await db.execute(statement);
    }
  }

  /// v1 阶段无历史版本，留空壳；后续按 `oldVersion` 分段迁移（docs/04 §3.1）
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 预留：if (oldVersion < 2) { … }
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  /// 仅供测试：删除库文件
  Future<void> deleteForTest() async {
    final path = _path;
    if (path == null) return;
    final factory = _factory ?? databaseFactory;
    await close();
    await factory.deleteDatabase(path);
  }
}

/// schema v2.1 完整 DDL（docs/02 §5，已在 sqlite3 3.50.6 实测通过）
const List<String> kSchema = <String>[
  // ============ 表1：周期配置表 ============
  '''
CREATE TABLE IF NOT EXISTS periodic_configs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT    NOT NULL,
    start_date      TEXT    NOT NULL,
    interval_type   TEXT    NOT NULL DEFAULT 'DAY'
                    CHECK (interval_type IN ('DAY', 'WEEK', 'MONTH', 'YEAR')),
    interval_value  INTEGER NOT NULL DEFAULT 1 CHECK (interval_value > 0),
    completed_count INTEGER NOT NULL DEFAULT 0 CHECK (completed_count >= 0),
    is_active       INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    end_date        TEXT,
    remark          TEXT,
    created_at      TEXT    NOT NULL,
    updated_at      TEXT    NOT NULL
)''',
  // ============ 表2：周期项（模板）表 ============
  '''
CREATE TABLE IF NOT EXISTS periodic_items (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    periodic_id  INTEGER NOT NULL,
    day_offset   INTEGER NOT NULL DEFAULT 0 CHECK (day_offset >= 0),
    title        TEXT    NOT NULL,
    remark       TEXT,
    remind_time  TEXT,
    priority     TEXT    NOT NULL DEFAULT 'none'
                 CHECK (priority IN ('none', 'low', 'medium', 'high')),
    accent_color TEXT,
    sort_order   INTEGER NOT NULL DEFAULT 0,
    created_at   TEXT    NOT NULL,
    updated_at   TEXT    NOT NULL,
    FOREIGN KEY (periodic_id) REFERENCES periodic_configs (id) ON DELETE CASCADE
)''',
  // ============ 表3：待办任务表（常规 + 周期实例 + 历史保留记录） ============
  '''
CREATE TABLE IF NOT EXISTS tasks (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    title                  TEXT    NOT NULL,
    remark                 TEXT,
    remind_date            TEXT    NOT NULL,
    remind_time            TEXT,
    priority               TEXT    NOT NULL DEFAULT 'none'
                           CHECK (priority IN ('none', 'low', 'medium', 'high')),
    accent_color           TEXT,
    is_completed           INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0, 1)),
    completed_at           TEXT,
    source_type            TEXT    NOT NULL DEFAULT 'REGULAR'
                           CHECK (source_type IN ('REGULAR', 'PERIODIC')),
    periodic_id            INTEGER,
    periodic_item_id       INTEGER,
    cycle_index            INTEGER CHECK (cycle_index IS NULL OR cycle_index >= 0),
    periodic_name_snapshot TEXT,
    sort_order             INTEGER NOT NULL DEFAULT 0,
    is_notified            INTEGER NOT NULL DEFAULT 0 CHECK (is_notified IN (0, 1)),
    created_at             TEXT    NOT NULL,
    updated_at             TEXT    NOT NULL,
    FOREIGN KEY (periodic_id)      REFERENCES periodic_configs (id) ON DELETE SET NULL,
    FOREIGN KEY (periodic_item_id) REFERENCES periodic_items (id)   ON DELETE SET NULL
)''',
  // ============ 表4：周期实例删除墓碑表 ============
  // 用户删掉的周期实例必须「删了就别再回来」：生成引擎的幂等键是
  // (periodic_item_id, cycle_index)，实例被物理删除后该键就空出来了，
  // 下次窗口生成会把它重新写回。此表记录「用户主动删除过的组合」，
  // 生成时跳过。周期项被删除时级联清理，不会无限增长。
  '''
CREATE TABLE IF NOT EXISTS periodic_skips (
    periodic_item_id INTEGER NOT NULL,
    cycle_index      INTEGER NOT NULL,
    reason           TEXT    NOT NULL DEFAULT 'USER_DELETED',
    created_at       TEXT    NOT NULL,
    PRIMARY KEY (periodic_item_id, cycle_index),
    FOREIGN KEY (periodic_item_id) REFERENCES periodic_items (id) ON DELETE CASCADE
)''',
  // ============ 索引（7 条） ============
  'CREATE INDEX IF NOT EXISTS idx_tasks_remind_date    ON tasks (remind_date)',
  'CREATE INDEX IF NOT EXISTS idx_tasks_pending        ON tasks (is_completed, remind_date)',
  'CREATE INDEX IF NOT EXISTS idx_tasks_periodic       ON tasks (periodic_id)',
  'CREATE INDEX IF NOT EXISTS idx_tasks_source_type    ON tasks (source_type)',
  'CREATE INDEX IF NOT EXISTS idx_tasks_completed_at   ON tasks (completed_at)',
  'CREATE INDEX IF NOT EXISTS idx_periodic_items_group ON periodic_items (periodic_id, day_offset)',
  // 幂等键：同一模板项在同一轮次只能有一个实例。
  // 常规待办与历史保留记录的 periodic_item_id 为 NULL，SQLite 中 NULL 互不相等，故不受影响。
  '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_instance_unique
    ON tasks (periodic_item_id, cycle_index)''',
];
