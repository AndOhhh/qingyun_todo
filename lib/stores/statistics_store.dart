import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/models/statistics_models.dart';
import 'package:qingyun_todo/repositories/statistics_repository.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 统计页读数据 provider（docs/04 §4.4 / docs/05）。
///
/// - [statsSummaryProvider]：首屏 M1~M6，**固定口径**，不受时间范围影响（D2）；
///   内部用 `Future.wait` 并行 7 条聚合 SQL（docs/05 §4.2）；
/// - [statsChartsProvider]：A1~A3，按 [StatsRange] family；
/// - [statsHeatmapProvider]：A7 月历热力，按 `YYYY-MM` family（自带月份维度）。
final Provider<StatisticsRepository> statisticsRepositoryProvider =
    Provider<StatisticsRepository>(
  (ref) => StatisticsRepository(ref.watch(dbHelperProvider)),
);

final FutureProvider<StatsSummary> statsSummaryProvider =
    FutureProvider<StatsSummary>((ref) async {
  final repo = ref.watch(statisticsRepositoryProvider);
  final today = DateUtil.today();
  final todayKey = DateUtil.formatDate(today);
  final weekBounds = StatsRange.week.bounds(today);

  final results = await Future.wait(<Future<Object>>[
    repo.completionRate(todayKey, todayKey), // M1
    repo.completionRate(weekBounds[0], weekBounds[1]), // M2
    repo.weekCells(today), // M2 点阵
    repo.currentStreak(), // M3
    repo.countOverdue(), // M4
    repo.countPending(), // M5
    repo.periodicDueRate(), // M6
  ]);

  return StatsSummary(
    today: results[0] as RateStat,
    week: results[1] as RateStat,
    weekCells: results[2] as List<WeekDayCell>,
    streak: results[3] as int,
    overdue: results[4] as int,
    pending: results[5] as int,
    periodic: results[6] as RateStat,
  );
});

final FutureProviderFamily<StatsCharts, StatsRange> statsChartsProvider =
    FutureProvider.family<StatsCharts, StatsRange>((ref, range) async {
  final repo = ref.watch(statisticsRepositoryProvider);
  final today = DateUtil.today();
  final bounds = range.bounds(today);
  final granularity = switch (range) {
    StatsRange.today => TrendGranularity.hour,
    StatsRange.week => TrendGranularity.day,
    StatsRange.month => TrendGranularity.day,
    StatsRange.all => TrendGranularity.month,
  };

  final results = await Future.wait(<Future<Object>>[
    repo.completionTrend(
      from: bounds[0],
      to: bounds[1],
      granularity: granularity,
    ),
    repo.priorityDistribution(bounds[0], bounds[1]),
    repo.weekdayDistribution(bounds[0], bounds[1]),
    repo.countInRange(bounds[0], bounds[1]),
  ]);

  return StatsCharts(
    trend: results[0] as List<TrendPoint>,
    priorities: results[1] as List<PrioritySlice>,
    weekdays: results[2] as List<WeekdayBar>,
    rangeTotal: results[3] as int,
  );
});

final FutureProviderFamily<Map<String, int>, String> statsHeatmapProvider =
    FutureProvider.family<Map<String, int>, String>(
  (ref, monthKey) =>
      ref.watch(statisticsRepositoryProvider).completionHeatmap(monthKey),
);
