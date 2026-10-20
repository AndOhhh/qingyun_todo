import 'package:qingyun_todo/models/cycle_rule.dart';
import 'package:qingyun_todo/models/interval_type.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 周期配置，对应 `periodic_configs` 表（schema v2.1，docs/02 §4.1）。
///
/// 周期 = 名称 + 起始日 + 规则（每 [intervalValue] 个 [intervalType] 一轮）；
/// 轮内每天做什么是 [PeriodicItem]（模板），真实待办是生成的 `tasks` 实例。
class Periodic {
  final int? id;
  final String name;

  /// 起始日期：视为第 1 轮第 1 天；MONTH/YEAR 下同时锚定「每月/每年的第几号」
  final DateTime startDate;

  final IntervalType intervalType;

  /// 每 [intervalValue] 个 [intervalType] 一轮，恒 >= 1
  final int intervalValue;

  /// 已完结的轮数（有意冗余，便于列表与统计快速读取，docs/02 §4.1）
  final int completedCount;

  /// 是否启用；`false` = 暂停，停止生成新实例，已有实例保留（FR-14）
  final bool isActive;

  /// 终止日期（含）；null = 无限循环
  final DateTime? endDate;

  final String? remark;

  /// 创建时间；由 Repository 统一写入（docs/04 §3.2），UI 无需传
  final DateTime? createdAt;

  /// 最后更新时间；同上
  final DateTime? updatedAt;

  const Periodic({
    this.id,
    required this.name,
    required this.startDate,
    this.intervalType = IntervalType.day,
    this.intervalValue = 1,
    this.completedCount = 0,
    this.isActive = true,
    this.endDate,
    this.remark,
    this.createdAt,
    this.updatedAt,
  });

  /// 周期规则（纯函数对象）
  CycleRule get rule => CycleRule(
        type: intervalType,
        value: intervalValue,
        startDate: startDate,
      );

  /// 周期文案：每天 / 每 N 天 / 每周 / 每 N 周 / 每月 / 每 N 个月 / 每年 / 每 N 年
  /// （docs/07 C1，与 [CycleRule.label] 共用一套文案）
  String get intervalLabel => rule.label;

  /// 一轮的最短天数（周期项 `day_offset` 上限 = 该值 - 1）
  int get minCycleLength => rule.minCycleLength;

  /// 起始日文案
  String get startDateLabel => DateUtil.humanDate(startDate);

  /// 是否已到终止日期之后（到期的周期不再生成实例）
  bool isEnded(DateTime day) {
    final end = endDate;
    return end != null && DateUtil.dateOnly(day).isAfter(DateUtil.dateOnly(end));
  }

  Periodic copyWith({
    int? id,
    String? name,
    DateTime? startDate,
    IntervalType? intervalType,
    int? intervalValue,
    int? completedCount,
    bool? isActive,
    DateTime? endDate,
    bool clearEndDate = false,
    String? remark,
    bool clearRemark = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Periodic(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      intervalType: intervalType ?? this.intervalType,
      intervalValue: intervalValue ?? this.intervalValue,
      completedCount: completedCount ?? this.completedCount,
      isActive: isActive ?? this.isActive,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      remark: clearRemark ? null : (remark ?? this.remark),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const String table = 'periodic_configs';

  Map<String, Object?> toMap({bool withId = false}) => <String, Object?>{
        if (withId && id != null) 'id': id,
        'name': name,
        'start_date': DateUtil.formatDate(startDate),
        'interval_type': intervalType.dbName,
        'interval_value': intervalValue,
        'completed_count': completedCount,
        'is_active': isActive ? 1 : 0,
        'end_date': endDate == null ? null : DateUtil.formatDate(endDate!),
        'remark': remark,
        'created_at': DateUtil.formatTimestamp(createdAt ?? DateTime.now()),
        'updated_at': DateUtil.formatTimestamp(updatedAt ?? DateTime.now()),
      };

  factory Periodic.fromMap(Map<String, Object?> map) {
    final endRaw = map['end_date'] as String?;
    return Periodic(
      id: (map['id'] as num?)?.toInt(),
      name: map['name'] as String,
      startDate: DateUtil.parseDate(map['start_date'] as String),
      intervalType: IntervalType.fromDbName(map['interval_type'] as String?),
      intervalValue: (map['interval_value'] as num? ?? 1).toInt(),
      completedCount: (map['completed_count'] as num? ?? 0).toInt(),
      isActive: (map['is_active'] as num? ?? 1).toInt() == 1,
      endDate: (endRaw == null || endRaw.isEmpty) ? null : DateUtil.parseDate(endRaw),
      remark: map['remark'] as String?,
      createdAt: DateUtil.parseTimestampOrNull(map['created_at']),
      updatedAt: DateUtil.parseTimestampOrNull(map['updated_at']),
    );
  }

  @override
  String toString() =>
      'Periodic(id: $id, name: $name, $intervalLabel, start: '
      '${DateUtil.formatDate(startDate)}, completedCount: $completedCount, '
      'isActive: $isActive)';
}

/// 某一轮的进度：`done / total`（docs/02 §8.7）
class CycleProgress {
  /// 轮次，0-based
  final int cycleIndex;
  final int done;
  final int total;

  const CycleProgress({
    required this.cycleIndex,
    required this.done,
    required this.total,
  });

  double get rate => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);

  bool get isFinished => total > 0 && done >= total;

  /// `x/y`
  String get label => '$done/$total';

  /// `第 N 轮`
  String get cycleLabel => '第 ${cycleIndex + 1} 轮';
}

/// 周期列表页卡片数据（周期 + 本轮进度 + 下次提醒）
class PeriodicListEntry {
  final Periodic periodic;

  /// 当前轮进度；该周期尚无实例时为 null
  final CycleProgress? currentCycle;

  /// 下一条未完成实例（卡片副标题）；无则为 null
  final Todo? nextRemind;

  const PeriodicListEntry({
    required this.periodic,
    this.currentCycle,
    this.nextRemind,
  });
}

/// 周期详情页聚合数据（docs/04 §4.2 `queryDetail`）
class PeriodicDetail {
  final Periodic periodic;

  /// 周期项，按 `day_offset, sort_order` 升序
  final List<PeriodicItem> items;

  /// 已生成实例总数（含已完成）
  final int totalInstances;

  /// 已完成实例数
  final int completedInstances;

  final CycleProgress? currentCycle;
  final Todo? nextRemind;

  const PeriodicDetail({
    required this.periodic,
    required this.items,
    required this.totalInstances,
    required this.completedInstances,
    this.currentCycle,
    this.nextRemind,
  });

  /// 完成率（总实例口径）
  double get completionRate => totalInstances == 0
      ? 0
      : (completedInstances / totalInstances).clamp(0.0, 1.0);

  /// 按天序分组：`{0: [第1天的项…], 1: […]}`，key 升序
  Map<int, List<PeriodicItem>> get itemsByDay {
    final map = <int, List<PeriodicItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.dayOffset, () => <PeriodicItem>[]).add(item);
    }
    final sorted = <int, List<PeriodicItem>>{};
    for (final key in map.keys.toList()..sort()) {
      sorted[key] = map[key]!;
    }
    return sorted;
  }

  /// 一轮的天数上限（周期项「第 N 天」选择器的取值范围）
  int get dayCount => periodic.minCycleLength;

  /// 是否一个周期项都没有（详情页提示「当前无可生成事项」，docs/07 D7）
  bool get hasNoItems => items.isEmpty;
}

/// 删除周期的结果（条件删除，docs/02 §7.3）
class PeriodicDeleteResult {
  /// 被物理删除的未完成实例数
  final int removedPending;

  /// 保留为孤儿历史记录的已完成实例数
  final int keptCompleted;

  const PeriodicDeleteResult({
    required this.removedPending,
    required this.keptCompleted,
  });

  /// 删除确认弹窗的前置文案数据（docs/07 C6-2）
  String describe(String periodicName) =>
      '删除周期「$periodicName」将移除 $removedPending 条未完成待办；'
      '已完成的 $keptCompleted 条会作为历史记录保留。'
      '若只想停止提醒，建议改用「暂停」。';
}
