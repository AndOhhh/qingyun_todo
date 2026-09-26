import 'package:qingyun_todo/models/interval_type.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 周期规则**纯函数**：由 `(intervalType, intervalValue, startDate)` 推算任意轮次
/// 的起始日与轮长度（docs/01 §4.2、docs/02 §7.1）。
///
/// 全部日历算术在 Dart 层完成，**不依赖 SQLite 日期函数**（MONTH/YEAR 会溢出进位）。
class CycleRule {
  /// 周期单位
  final IntervalType type;

  /// 每 [value] 个 [type] 为一轮，恒 >= 1
  final int value;

  /// 第 1 轮第 1 天（date-only）；MONTH/YEAR 类型下同时锚定「每月/每年的第几号」
  final DateTime startDate;

  CycleRule({
    required this.type,
    required this.value,
    required DateTime startDate,
  })  : assert(value > 0, 'interval_value 必须 > 0'),
        startDate = DateUtil.dateOnly(startDate);

  /// 第 [k] 轮（0-based）的起始日
  DateTime cycleStart(int k) {
    if (k < 0) {
      throw ArgumentError.value(k, 'k', '轮次不能为负');
    }
    switch (type) {
      case IntervalType.day:
        return DateUtil.addDays(startDate, k * value);
      case IntervalType.week:
        return DateUtil.addDays(startDate, k * value * 7);
      case IntervalType.month:
        return DateUtil.addMonths(startDate, k * value);
      case IntervalType.year:
        return DateUtil.addYears(startDate, k * value);
    }
  }

  /// 第 [k] 轮的长度（天）：DAY/WEEK 固定，MONTH 28~31，YEAR 365/366
  int cycleLength(int k) =>
      DateUtil.daysBetween(cycleStart(k), cycleStart(k + 1));

  /// 保存校验用的**最短**轮长度（docs/02 §7.2）：
  /// DAY/WEEK 取精确值，MONTH 取 28，YEAR 取 365，避免 2 月 / 平年失效。
  int get minCycleLength {
    switch (type) {
      case IntervalType.day:
        return value;
      case IntervalType.week:
        return value * 7;
      case IntervalType.month:
        return 28;
      case IntervalType.year:
        return 365;
    }
  }

  /// 周期文案：每天 / 每 N 天 / 每周 / 每 N 周 / 每月 / 每 N 个月 / 每年 / 每 N 年
  /// （docs/07 C1）
  String get label {
    switch (type) {
      case IntervalType.day:
        return value == 1 ? '每天' : '每 $value 天';
      case IntervalType.week:
        return value == 1 ? '每周' : '每 $value 周';
      case IntervalType.month:
        return value == 1 ? '每月' : '每 $value 个月';
      case IntervalType.year:
        return value == 1 ? '每年' : '每 $value 年';
    }
  }

  /// 首个满足 `cycleStart(k) >= from` 的轮次（from 早于起始日时返回 0）
  int firstCycleIndexOnOrAfter(DateTime from) {
    final f = DateUtil.dateOnly(from);
    if (!f.isAfter(startDate)) return 0;
    var k = _estimate(f);
    // 估算值可能因月末收敛而偏移，双向夹逼修正（最多几步）
    while (k > 0 && !cycleStart(k - 1).isBefore(f)) {
      k--;
    }
    while (cycleStart(k).isBefore(f)) {
      k++;
    }
    return k;
  }

  /// [date] 落在第几轮；早于起始日返回 `-1`
  int cycleIndexOf(DateTime date) {
    final d = DateUtil.dateOnly(date);
    if (d.isBefore(startDate)) return -1;
    var k = _estimate(d);
    while (k > 0 && !cycleStart(k - 1).isAfter(d)) {
      k--;
    }
    while (!cycleStart(k + 1).isAfter(d)) {
      k++;
    }
    return k;
  }

  /// 未来 [cycles] 轮预览（C2-5「所见即所得」时间轴），从包含 [from] 的那一轮起算
  List<CyclePreview> preview({int cycles = 3, DateTime? from}) {
    final base = DateUtil.dateOnly(from ?? DateUtil.today());
    final start = base.isBefore(startDate) ? 0 : cycleIndexOf(base);
    return List<CyclePreview>.generate(cycles, (i) {
      final k = start + i;
      final s = cycleStart(k);
      return CyclePreview(
        cycleIndex: k,
        startDate: s,
        length: cycleLength(k),
        endDate: DateUtil.addDays(s, cycleLength(k) - 1),
      );
    });
  }

  /// 某个 `day_offset` 在未来 [cycles] 轮中真实落到的日期；
  /// 该轮长度不足（短月份）时**跳过**，故返回列表可能短于 [cycles]（docs/02 §7.2）。
  List<DateTime> datesForDayOffset(
    int dayOffset, {
    int cycles = 3,
    DateTime? from,
  }) {
    final base = DateUtil.dateOnly(from ?? DateUtil.today());
    final start = base.isBefore(startDate) ? 0 : cycleIndexOf(base);
    final result = <DateTime>[];
    for (var i = 0; i < cycles; i++) {
      final k = start + i;
      if (dayOffset >= cycleLength(k)) continue;
      result.add(DateUtil.addDays(cycleStart(k), dayOffset));
    }
    return result;
  }

  int _estimate(DateTime d) {
    final days = DateUtil.daysBetween(startDate, d);
    switch (type) {
      case IntervalType.day:
        return (days / value).ceil();
      case IntervalType.week:
        return (days / (value * 7)).ceil();
      case IntervalType.month:
        return (DateUtil.monthsBetween(startDate, d) / value).floor();
      case IntervalType.year:
        return (DateUtil.monthsBetween(startDate, d) / (value * 12)).floor();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CycleRule &&
      other.type == type &&
      other.value == value &&
      other.startDate == startDate;

  @override
  int get hashCode => Object.hash(type, value, startDate);
}

/// 一轮的预览信息
class CyclePreview {
  /// 轮次，0-based
  final int cycleIndex;

  final DateTime startDate;
  final DateTime endDate;

  /// 轮长度（天）
  final int length;

  const CyclePreview({
    required this.cycleIndex,
    required this.startDate,
    required this.endDate,
    required this.length,
  });
}
