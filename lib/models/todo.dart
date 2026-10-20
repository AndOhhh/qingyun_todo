import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/utils/color_util.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 任务来源（`tasks.source_type`）。
///
/// 来源周期被删除后，历史记录**仍保持** [TaskSourceType.periodic]（docs/02 §4.3）。
enum TaskSourceType {
  regular('REGULAR'),
  periodic('PERIODIC');

  final String dbName;

  const TaskSourceType(this.dbName);

  static TaskSourceType fromDbName(String? name) =>
      TaskSourceType.values.firstWhere(
        (e) => e.dbName == name,
        orElse: () => TaskSourceType.regular,
      );
}

/// 待办任务模型，对应 `tasks` 表（schema v2.1，docs/02 §4.3）。
///
/// **不可变**：状态变更一律通过 [copyWith] 产生新对象后由 Repository 写回，
/// 不再像旧 mock 版本那样直接改字段（docs/03 §5）。
///
/// 派生值**不入库**：逾期、周期文案等一律实时计算（docs/02 §1 原则 7）。
class Todo {
  /// 主键；新建时为 null，落库后由 Repository 回填
  final int? id;

  final String title;

  /// 备注（DB 字段 `remark`，旧代码叫 `note`）
  final String? remark;

  /// 提醒日期（date-only，DB 存 `YYYY-MM-DD`）
  final DateTime remindDate;

  /// 提醒时间 `HH:mm`，可为空（不提醒具体时刻）
  final String? remindTime;

  final TodoPriority priority;

  /// 色带颜色原始值 `#RRGGBB`，为空时按 [priority] 推导
  final String? accentColorHex;

  final bool isCompleted;

  /// 完成时刻；取消完成时置 null
  final DateTime? completedAt;

  final TaskSourceType sourceType;

  /// 来源周期 id；常规待办为 null，**周期被删后自动置 null**（孤儿记录）
  final int? periodicId;

  /// 来源周期项（模板）id，与 [cycleIndex] 共同构成幂等键
  final int? periodicItemId;

  /// 第几轮，0-based；来源周期删除后仍保留
  final int? cycleIndex;

  /// 生成实例时写入的周期名快照；周期改名不回写（docs/07 D8）
  final String? periodicNameSnapshot;

  final int sortOrder;

  /// 提醒是否已发出（Phase 6 通知用）
  final bool isNotified;

  /// 创建时间；由 Repository 统一写入（docs/04 §3.2），UI 无需传
  final DateTime? createdAt;

  /// 最后更新时间；同上
  final DateTime? updatedAt;

  const Todo({
    this.id,
    required this.title,
    this.remark,
    required this.remindDate,
    this.remindTime,
    this.priority = TodoPriority.none,
    this.accentColorHex,
    this.isCompleted = false,
    this.completedAt,
    this.sourceType = TaskSourceType.regular,
    this.periodicId,
    this.periodicItemId,
    this.cycleIndex,
    this.periodicNameSnapshot,
    this.sortOrder = 0,
    this.isNotified = false,
    this.createdAt,
    this.updatedAt,
  });

  // ---------------- 派生属性 ----------------

  /// 是否周期实例（由 `source_type` 派生，修 R12）
  bool get isPeriodic => sourceType == TaskSourceType.periodic;

  /// 孤儿记录：来源周期已被删除的历史记录（docs/02 §4.3）
  bool get isOrphanPeriodic => isPeriodic && periodicId == null;

  /// 是否逾期：`remind_date < today AND is_completed = 0`（实时派生，修 R4）
  bool get isOverdue =>
      !isCompleted && DateUtil.dateOnly(remindDate).isBefore(DateUtil.today());

  /// 色带颜色（`accent_color` 为空时按优先级推导）
  Color get accentColor => ColorUtil.resolveAccent(accentColorHex, priority);

  /// 日期标签：今天 / 明天 / 昨天 / N 天后 / M-D
  String get dueDateLabel => DateUtil.dateLabel(remindDate);

  /// 周期标签文案：`周期·{名称}`；常规待办返回 null
  ///
  /// 名称一律取快照，来源周期改名或删除后仍能正确展示（docs/07 C6-4）。
  String? get periodicTagLabel {
    if (!isPeriodic) return null;
    final name = periodicNameSnapshot;
    return (name == null || name.isEmpty) ? '周期' : '周期·$name';
  }

  /// `第 N 轮` 文案，无轮次信息时为 null
  String? get cycleLabel =>
      cycleIndex == null ? null : '第 ${cycleIndex! + 1} 轮';

  /// 提醒的完整时刻（`remind_date` + `remind_time`）；未设置时间时为 null
  /// （通知排期依赖精确时刻，无时间的任务只做日期展示、不发通知）
  DateTime? get remindAt {
    final time = remindTime;
    if (time == null) return null;
    final parts = time.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(
      remindDate.year,
      remindDate.month,
      remindDate.day,
      hour,
      minute,
    );
  }

  /// 提醒日期 + 时间的完整文案
  String get remindText {
    final date = DateUtil.humanDate(remindDate);
    return remindTime == null ? date : '$date $remindTime';
  }

  Todo copyWith({
    int? id,
    String? title,
    String? remark,
    bool clearRemark = false,
    DateTime? remindDate,
    String? remindTime,
    bool clearRemindTime = false,
    TodoPriority? priority,
    String? accentColorHex,
    bool clearAccentColor = false,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    TaskSourceType? sourceType,
    int? periodicId,
    int? periodicItemId,
    int? cycleIndex,
    String? periodicNameSnapshot,
    int? sortOrder,
    bool? isNotified,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      remark: clearRemark ? null : (remark ?? this.remark),
      remindDate: remindDate ?? this.remindDate,
      remindTime: clearRemindTime ? null : (remindTime ?? this.remindTime),
      priority: priority ?? this.priority,
      accentColorHex:
          clearAccentColor ? null : (accentColorHex ?? this.accentColorHex),
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
      sourceType: sourceType ?? this.sourceType,
      periodicId: periodicId ?? this.periodicId,
      periodicItemId: periodicItemId ?? this.periodicItemId,
      cycleIndex: cycleIndex ?? this.cycleIndex,
      periodicNameSnapshot:
          periodicNameSnapshot ?? this.periodicNameSnapshot,
      sortOrder: sortOrder ?? this.sortOrder,
      isNotified: isNotified ?? this.isNotified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ---------------- DB 映射 ----------------

  static const String table = 'tasks';

  /// 写库用；[withId] 为 true 时带上主键（仅供撤销删除按原 id 写回）
  Map<String, Object?> toMap({bool withId = false}) => <String, Object?>{
        if (withId && id != null) 'id': id,
        'title': title,
        'remark': remark,
        'remind_date': DateUtil.formatDate(remindDate),
        'remind_time': remindTime,
        'priority': priority.dbName,
        'accent_color': accentColorHex,
        'is_completed': isCompleted ? 1 : 0,
        'completed_at': completedAt == null
            ? null
            : DateUtil.formatTimestamp(completedAt!),
        'source_type': sourceType.dbName,
        'periodic_id': periodicId,
        'periodic_item_id': periodicItemId,
        'cycle_index': cycleIndex,
        'periodic_name_snapshot': periodicNameSnapshot,
        'sort_order': sortOrder,
        'is_notified': isNotified ? 1 : 0,
        'created_at': DateUtil.formatTimestamp(createdAt ?? DateTime.now()),
        'updated_at': DateUtil.formatTimestamp(updatedAt ?? DateTime.now()),
      };

  factory Todo.fromMap(Map<String, Object?> map) {
    final completedAtRaw = map['completed_at'] as String?;
    return Todo(
      id: (map['id'] as num?)?.toInt(),
      title: map['title'] as String,
      remark: map['remark'] as String?,
      remindDate: DateUtil.parseDate(map['remind_date'] as String),
      remindTime: map['remind_time'] as String?,
      priority: TodoPriority.fromDbName(map['priority'] as String?),
      accentColorHex: map['accent_color'] as String?,
      isCompleted: (map['is_completed'] as num? ?? 0).toInt() == 1,
      completedAt: completedAtRaw == null
          ? null
          : DateUtil.parseTimestamp(completedAtRaw),
      sourceType: TaskSourceType.fromDbName(map['source_type'] as String?),
      periodicId: (map['periodic_id'] as num?)?.toInt(),
      periodicItemId: (map['periodic_item_id'] as num?)?.toInt(),
      cycleIndex: (map['cycle_index'] as num?)?.toInt(),
      periodicNameSnapshot: map['periodic_name_snapshot'] as String?,
      sortOrder: (map['sort_order'] as num? ?? 0).toInt(),
      isNotified: (map['is_notified'] as num? ?? 0).toInt() == 1,
      createdAt: DateUtil.parseTimestampOrNull(map['created_at']),
      updatedAt: DateUtil.parseTimestampOrNull(map['updated_at']),
    );
  }

  @override
  String toString() =>
      'Todo(id: $id, title: $title, remindDate: ${DateUtil.formatDate(remindDate)}, '
      'isCompleted: $isCompleted, sourceType: $sourceType, cycleIndex: $cycleIndex)';
}
