import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/utils/color_util.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 周期项（模板），对应 `periodic_items` 表（schema v2.1，docs/02 §4.2）。
///
/// 周期项描述「一轮中第几天做什么」，本身**不出现在待办列表**；
/// 由生成引擎按轮次实例化为 `tasks` 行（docs/02 §1 原则 1）。
class PeriodicItem {
  final int? id;

  /// 所属周期 id；新建周期时可在事务内回填，故允许为 null
  final int? periodicId;

  /// 天序，**0-based**（0 = 周期第 1 天），上限 = `CycleRule.minCycleLength - 1`
  final int dayOffset;

  final String title;
  final String? remark;

  /// 提醒时间 `HH:mm`，可为空
  final String? remindTime;

  final TodoPriority priority;

  /// 色带颜色 `#RRGGBB`，为空时按 [priority] 推导
  final String? accentColorHex;

  /// 同一天多项时的排序
  final int sortOrder;

  /// 创建时间；由 Repository 统一写入（docs/04 §3.2），UI 无需传
  final DateTime? createdAt;

  /// 最后更新时间；同上
  final DateTime? updatedAt;

  const PeriodicItem({
    this.id,
    this.periodicId,
    this.dayOffset = 0,
    required this.title,
    this.remark,
    this.remindTime,
    this.priority = TodoPriority.none,
    this.accentColorHex,
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// `第 N 天`
  String get dayLabel => '第 ${dayOffset + 1} 天';

  Color get accentColor => ColorUtil.resolveAccent(accentColorHex, priority);

  PeriodicItem copyWith({
    int? id,
    int? periodicId,
    int? dayOffset,
    String? title,
    String? remark,
    bool clearRemark = false,
    String? remindTime,
    bool clearRemindTime = false,
    TodoPriority? priority,
    String? accentColorHex,
    bool clearAccentColor = false,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PeriodicItem(
      id: id ?? this.id,
      periodicId: periodicId ?? this.periodicId,
      dayOffset: dayOffset ?? this.dayOffset,
      title: title ?? this.title,
      remark: clearRemark ? null : (remark ?? this.remark),
      remindTime: clearRemindTime ? null : (remindTime ?? this.remindTime),
      priority: priority ?? this.priority,
      accentColorHex:
          clearAccentColor ? null : (accentColorHex ?? this.accentColorHex),
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const String table = 'periodic_items';

  Map<String, Object?> toMap({bool withId = false}) => <String, Object?>{
        if (withId && id != null) 'id': id,
        'periodic_id': periodicId,
        'day_offset': dayOffset,
        'title': title,
        'remark': remark,
        'remind_time': remindTime,
        'priority': priority.dbName,
        'accent_color': accentColorHex,
        'sort_order': sortOrder,
        'created_at': DateUtil.formatTimestamp(createdAt ?? DateTime.now()),
        'updated_at': DateUtil.formatTimestamp(updatedAt ?? DateTime.now()),
      };

  factory PeriodicItem.fromMap(Map<String, Object?> map) => PeriodicItem(
        id: (map['id'] as num?)?.toInt(),
        periodicId: (map['periodic_id'] as num?)?.toInt(),
        dayOffset: (map['day_offset'] as num? ?? 0).toInt(),
        title: map['title'] as String,
        remark: map['remark'] as String?,
        remindTime: map['remind_time'] as String?,
        priority: TodoPriority.fromDbName(map['priority'] as String?),
        accentColorHex: map['accent_color'] as String?,
        sortOrder: (map['sort_order'] as num? ?? 0).toInt(),
        createdAt: DateUtil.parseTimestampOrNull(map['created_at']),
        updatedAt: DateUtil.parseTimestampOrNull(map['updated_at']),
      );
}

/// 删除周期项的结果（条件删除：未完成实例删、已完成实例保留，docs/02 §7.3）
class ItemDeleteResult {
  /// 被物理删除的未完成实例数
  final int removedPending;

  /// 保留为历史记录的已完成实例数（`periodic_item_id` 已置 NULL）
  final int keptCompleted;

  const ItemDeleteResult({
    required this.removedPending,
    required this.keptCompleted,
  });
}
