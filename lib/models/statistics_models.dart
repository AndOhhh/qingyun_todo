import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 统计页时间范围（S2 / D2）：只作用于趋势与分布类图表，
/// 首屏核心指标卡（M1~M6）固定口径不受其影响。
enum StatsRange {
  today('今天'),
  week('本周'),
  month('本月'),
  all('全部');

  final String label;

  const StatsRange(this.label);

  /// 闭区间 `[from, to]`，`YYYY-MM-DD` 字符串（可直接与库内日期比较）
  List<String> bounds(DateTime today) {
    final t = DateUtil.dateOnly(today);
    switch (this) {
      case StatsRange.today:
        final s = DateUtil.formatDate(t);
        return <String>[s, s];
      case StatsRange.week:
        final monday = DateUtil.addDays(t, -((t.weekday - 1) % 7));
        return <String>[
          DateUtil.formatDate(monday),
          DateUtil.formatDate(DateUtil.addDays(monday, 6)),
        ];
      case StatsRange.month:
        return <String>[
          DateUtil.formatDate(DateUtil.firstDayOfMonth(t)),
          DateUtil.formatDate(DateUtil.lastDayOfMonth(t)),
        ];
      case StatsRange.all:
        return const <String>['0000-01-01', '9999-12-31'];
    }
  }
}

/// 趋势图粒度：今天 → 小时；本周/本月 → 天；全部 → 月
enum TrendGranularity { hour, day, month }

/// 完成率类指标：分母为 0 时 [rate] 为 null，UI 显示 `--`（S4）
class RateStat {
  final int total;
  final int done;

  const RateStat({required this.total, required this.done});

  static const RateStat empty = RateStat(total: 0, done: 0);

  /// 分母为 0 → null（展示 `--`）
  double? get rate => total == 0 ? null : (done / total).clamp(0.0, 1.0);

  String get rateText {
    final r = rate;
    return r == null ? '--' : '${(r * 100).round()}%';
  }

  int get remaining => total - done > 0 ? total - done : 0;
}

/// 本周点阵的一格（M2）
class WeekDayCell {
  final DateTime date;
  final int total;
  final int done;

  const WeekDayCell({required this.date, required this.total, required this.done});

  bool get isAllDone => total > 0 && done >= total;
  bool get isEmpty => total == 0;
  bool get isPartial => total > 0 && done > 0 && done < total;
}

/// 首屏核心指标（M1~M6，口径见 docs/05 §1）
class StatsSummary {
  /// M1 今日完成率（提醒日 = 今天）
  final RateStat today;

  /// M2 本周完成率（周一起算）
  final RateStat week;

  /// M2 点阵：周一 ~ 周日
  final List<WeekDayCell> weekCells;

  /// M3 连续打卡天数
  final int streak;

  /// M4 逾期任务数
  final int overdue;

  /// M5 待处理总数
  final int pending;

  /// M6 周期任务完成率（仅已到期实例）
  final RateStat periodic;

  const StatsSummary({
    required this.today,
    required this.week,
    required this.weekCells,
    required this.streak,
    required this.overdue,
    required this.pending,
    required this.periodic,
  });

  /// 完全无数据（S3：展示引导而非一排 `--`）
  bool get isEmpty =>
      today.total == 0 &&
      week.total == 0 &&
      streak == 0 &&
      overdue == 0 &&
      pending == 0 &&
      periodic.total == 0;
}

/// 趋势图的一个点（A1）
class TrendPoint {
  /// 展示标签：`9/26` / `14` / `2026-10`
  final String label;
  final int count;

  const TrendPoint({required this.label, required this.count});
}

/// 优先级分布的一片（A2）
class PrioritySlice {
  final TodoPriority priority;
  final int total;
  final int done;

  const PrioritySlice({
    required this.priority,
    required this.total,
    required this.done,
  });
}

/// 星期分布的一柱（A3）：[weekday] 1=周一 … 7=周日
class WeekdayBar {
  final int weekday;
  final int count;

  const WeekdayBar({required this.weekday, required this.count});
}

/// 趋势 / 分布类图表数据（A1~A3，受 [StatsRange] 影响）
class StatsCharts {
  final List<TrendPoint> trend;
  final List<PrioritySlice> priorities;
  final List<WeekdayBar> weekdays;

  /// 范围内任务总数（图表空态判断用）
  final int rangeTotal;

  const StatsCharts({
    required this.trend,
    required this.priorities,
    required this.weekdays,
    required this.rangeTotal,
  });
}
