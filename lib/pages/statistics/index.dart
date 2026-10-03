import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/empty_state.dart';
import 'package:qingyun_todo/components/error_state.dart';
import 'package:qingyun_todo/models/statistics_models.dart';
import 'package:qingyun_todo/pages/statistics/widgets/heatmap_month.dart';
import 'package:qingyun_todo/pages/statistics/widgets/priority_donut.dart';
import 'package:qingyun_todo/pages/statistics/widgets/stat_card.dart';
import 'package:qingyun_todo/pages/statistics/widgets/trend_chart.dart';
import 'package:qingyun_todo/pages/statistics/widgets/weekday_bars.dart';
import 'package:qingyun_todo/stores/statistics_store.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 统计页（FR-18）：首屏核心指标 M1~M6（固定口径）+ 趋势/分布图表 A1~A3
/// （受时间范围影响，D2）+ 月历热力 A7（自带月份维度）。
///
/// 口径见 docs/05 §1：完成率按 `remind_date`、趋势按 `completed_at`、
/// 硬删除不进分母、孤儿周期记录计入 M6、分母为 0 显示 `--`。
class StatisticsView extends ConsumerStatefulWidget {
  const StatisticsView({super.key});

  @override
  ConsumerState<StatisticsView> createState() => _StatisticsViewState();
}

class _StatisticsViewState extends ConsumerState<StatisticsView> {
  StatsRange _range = StatsRange.week;
  late DateTime _heatMonth = DateUtil.firstDayOfMonth(DateUtil.today());

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(statsSummaryProvider);
    final chartsAsync = ref.watch(statsChartsProvider(_range));
    final heatKey = DateUtil.monthKey(_heatMonth);
    final heatAsync = ref.watch(statsHeatmapProvider(heatKey));

    return CupertinoTheme(
      data: const CupertinoThemeData(
        primaryColor: Color(0xFF007AFF),
        scaffoldBackgroundColor: Color(0xFFF2F2F7),
      ),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: <Widget>[
          CupertinoSliverNavigationBar(
            backgroundColor: const Color(0xFFF2F2F7),
            heroTag: 'statistics-large-title',
            border: null,
            largeTitle: const Text('统计', style: TextStyle(color: Colors.black)),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () async {
              ref
                ..invalidate(statsSummaryProvider)
                ..invalidate(statsChartsProvider)
                ..invalidate(statsHeatmapProvider);
              await ref.read(statsSummaryProvider.future);
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: <Widget>[
                  // S2：范围只作用于趋势 / 分布类图表（D2）
                  CupertinoSlidingSegmentedControl<StatsRange>(
                    groupValue: _range,
                    onValueChanged: (value) {
                      if (value != null) setState(() => _range = value);
                    },
                    children: <StatsRange, Widget>{
                      for (final range in StatsRange.values)
                        range: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            range.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    },
                  ),
                  const SizedBox(height: 16),
                  summaryAsync.when(
                    loading: () => const _LoadingBlock(height: 260),
                    error: (error, _) => ErrorState(
                      error: error,
                      title: '统计加载失败',
                      onRetry: () => ref.invalidate(statsSummaryProvider),
                    ),
                    data: (summary) =>
                        summary.isEmpty ? _empty() : _summaryBlocks(summary),
                  ),
                  const SizedBox(height: 16),
                  chartsAsync.when(
                    loading: () => const _LoadingBlock(height: 200),
                    error: (error, _) => ErrorState(
                      error: error,
                      title: '图表加载失败',
                      onRetry: () => ref.invalidate(statsChartsProvider(_range)),
                    ),
                    data: (charts) => Column(
                      children: <Widget>[
                        ChartCard(
                          title: '完成趋势',
                          caption: _trendCaption(),
                          child: TrendChart(points: charts.trend),
                        ),
                        const SizedBox(height: 12),
                        ChartCard(
                          title: '优先级分布',
                          caption: '范围内任务按优先级构成',
                          child: PriorityDonut(slices: charts.priorities),
                        ),
                        const SizedBox(height: 12),
                        ChartCard(
                          title: '星期分布',
                          caption: '范围内任务集中在星期几',
                          child: WeekdayBars(bars: charts.weekdays),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  heatAsync.when(
                    loading: () => const _LoadingBlock(height: 240),
                    error: (error, _) => ErrorState(
                      error: error,
                      title: '热力图加载失败',
                      onRetry: () => ref.invalidate(statsHeatmapProvider(heatKey)),
                    ),
                    data: (counts) => ChartCard(
                      title: '完成热力',
                      caption: '按实际完成日期着色（completed_at）',
                      child: HeatmapMonth(
                        month: _heatMonth,
                        counts: counts,
                        onPrevMonth: () => setState(
                          () => _heatMonth =
                              DateUtil.addMonthsCalendar(_heatMonth, -1),
                        ),
                        onNextMonth: () => setState(
                          () => _heatMonth =
                              DateUtil.addMonthsCalendar(_heatMonth, 1),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 140),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _trendCaption() {
    switch (_range) {
      case StatsRange.today:
        return '今天 · 按小时（实际完成时间）';
      case StatsRange.week:
        return '本周 · 按天（实际完成时间）';
      case StatsRange.month:
        return '本月 · 按天（实际完成时间）';
      case StatsRange.all:
        return '全部 · 按月（实际完成时间）';
    }
  }

  /// S3：完全无数据时的引导，而不是一排 `--`
  Widget _empty() {
    return const EmptyState(
      icon: CupertinoIcons.chart_bar,
      iconColor: Color(0xFF007AFF),
      title: '还没有统计数据',
      subtitle: '完成第一个待办后，这里会出现完成率、\n连续打卡与趋势图。',
    );
  }

  Widget _summaryBlocks(StatsSummary s) {
    return Column(
      children: <Widget>[
        // IntrinsicHeight + stretch：同一行两张卡等高，
        // 且避免在无界高度约束下直接使用 stretch 触发布局断言
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _RingCard(stat: s.today)),
              const SizedBox(width: 12),
              Expanded(child: _StreakCard(days: s.streak)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: StatCard(
                  title: '本周完成率',
                  value: s.week.rateText,
                  color: const Color(0xFF007AFF),
                  subtitle: '应完成 ${s.week.total} 项',
                  extra: _WeekStrip(cells: s.weekCells),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  title: '逾期任务',
                  value: '${s.overdue}',
                  color: const Color(0xFFFF3B30),
                  icon: CupertinoIcons.exclamationmark_triangle,
                  subtitle: '未完成且已过期',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: StatCard(
                  title: '待处理总数',
                  value: '${s.pending}',
                  color: const Color(0xFF1C1C1E),
                  icon: CupertinoIcons.checkmark_rectangle,
                  subtitle: '全部未完成待办',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  title: '周期完成率',
                  value: s.periodic.rateText,
                  color: const Color(0xFFFF9500),
                  icon: CupertinoIcons.refresh,
                  subtitle: '仅统计已到期实例',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// M1 今日完成率环形卡
class _RingCard extends StatelessWidget {
  final RateStat stat;

  const _RingCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    final rate = stat.rate;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '今日完成率',
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 10),
          Center(
            child: SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: rate ?? 0,
                      strokeWidth: 9,
                      strokeCap: StrokeCap.round,
                      backgroundColor: const Color(0xFFE5E5EA),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF007AFF),
                      ),
                    ),
                  ),
                  Text(
                    stat.rateText,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF007AFF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${stat.done}/${stat.total} 项应完成',
            style: const TextStyle(fontSize: 11, color: Color(0xFFAEAEB2)),
          ),
        ],
      ),
    );
  }
}

/// M3 连续打卡卡
class _StreakCard extends StatelessWidget {
  final int days;

  const _StreakCard({required this.days});

  @override
  Widget build(BuildContext context) {
    final active = days > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '连续打卡',
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 10),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  CupertinoIcons.flame,
                  size: 30,
                  color: active ? const Color(0xFFFF9500) : const Color(0xFFC7C7CC),
                ),
                const SizedBox(width: 8),
                Text(
                  '$days',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    letterSpacing: -1,
                    color: active
                        ? const Color(0xFFFF9500)
                        : const Color(0xFFC7C7CC),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '天',
                  style: TextStyle(
                    fontSize: 13,
                    color: active
                        ? const Color(0xFFFF9500)
                        : const Color(0xFFC7C7CC),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            active ? '保持住，别断链' : '完成一个待办开始打卡',
            style: const TextStyle(fontSize: 11, color: Color(0xFFAEAEB2)),
          ),
        ],
      ),
    );
  }
}

/// M2 本周点阵：周一 ~ 周日
class _WeekStrip extends StatelessWidget {
  final List<WeekDayCell> cells;

  const _WeekStrip({required this.cells});

  @override
  Widget build(BuildContext context) {
    final today = DateUtil.today();
    const labels = <String>['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: <Widget>[
        for (var i = 0; i < cells.length && i < 7; i++)
          Expanded(
            child: Column(
              children: <Widget>[
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _color(cells[i]),
                    border: cells[i].isEmpty
                        ? Border.all(
                            color: cells[i].date == today
                                ? const Color(0xFF007AFF)
                                : const Color(0xFFD1D1D6),
                            width: 1,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 9,
                    color: cells[i].date == today
                        ? const Color(0xFF007AFF)
                        : const Color(0xFFAEAEB2),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _color(WeekDayCell cell) {
    if (cell.isAllDone) return const Color(0xFF34C759);
    if (cell.isPartial) return const Color(0xFF007AFF);
    return Colors.transparent;
  }
}

class _LoadingBlock extends StatelessWidget {
  final double height;

  const _LoadingBlock({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(child: CupertinoActivityIndicator(radius: 13)),
    );
  }
}
