import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/empty_state.dart';
import 'package:qingyun_todo/components/error_state.dart';
import 'package:qingyun_todo/components/width_guard.dart';
import 'package:qingyun_todo/models/statistics_models.dart';
import 'package:qingyun_todo/pages/statistics/widgets/heatmap_month.dart';
import 'package:qingyun_todo/pages/statistics/widgets/priority_donut.dart';
import 'package:qingyun_todo/pages/statistics/widgets/stat_card.dart';
import 'package:qingyun_todo/pages/statistics/widgets/trend_chart.dart';
import 'package:qingyun_todo/pages/statistics/widgets/weekday_bars.dart';
import 'package:qingyun_todo/stores/statistics_store.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 连续打卡的里程碑档位（天）：用于「下一档」进度提示
const List<int> kStreakMilestones = <int>[3, 7, 14, 30, 60, 100, 180, 365];

/// 连续打卡的下一档里程碑；已达最高档返回 null（纯函数，单测覆盖）
int? nextStreakMilestone(int days) {
  for (final milestone in kStreakMilestones) {
    if (milestone > days) return milestone;
  }
  return null;
}

/// 当前档位下界（进度条起点）：已达成的最小档位；未达首档为 0（纯函数）
int previousStreakMilestone(int days) {
  var previous = 0;
  for (final milestone in kStreakMilestones) {
    if (milestone > days) break;
    previous = milestone;
  }
  return previous;
}

/// 统计页（FR-18）：首屏核心指标 M1~M6（固定口径）+ 趋势/分布图表 A1~A3
/// （受时间范围影响，D2）+ 月历热力 A7（自带月份维度）。
///
/// 口径见 docs/05 §1：完成率按 `remind_date`、趋势按 `completed_at`、
/// 硬删除不进分母、孤儿周期记录计入 M6、分母为 0 显示 `--`。
class StatisticsView extends ConsumerStatefulWidget {
  /// 范围切换选中块颜色：主色 12% 浅调（用户反馈默认灰白组合过于违和）
  static const Color kRangeThumbColor = Color(0x1F007AFF);

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
                  // S2：范围只作用于趋势 / 分布类图表（D2）。
                  // 选中态用主色浅调胶囊（与底部 Tab 胶囊同一设计语言），
                  // 替代默认灰底白块的高对比组合。
                  //
                  // WidthGuard：预热帧视图宽度为 0 时分段控件会算出负段宽并断言
                  // （BoxConstraints has a negative minimum width），此处先跳过构建。
                  WidthGuard(
                    child: CupertinoSlidingSegmentedControl<StatsRange>(
                      groupValue: _range,
                      backgroundColor: Colors.white,
                      thumbColor: StatisticsView.kRangeThumbColor,
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
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: _range == range
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: _range == range
                                    ? const Color(0xFF007AFF)
                                    : const Color(0xFF636366),
                              ),
                            ),
                          ),
                      },
                    ),
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
              Expanded(child: _OverdueCard(count: s.overdue)),
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

/// M3 连续打卡卡：暖色高亮 + 「下一档里程碑」进度；断链（0 天）回落中性灰。
///
/// 视觉动机：连击是**状态型**指标而非数值型 —— 有连击时用暖色渐变与火焰强调
/// 「在连击中」，断了则保持安静的灰色，避免用红色制造挫败感。
class _StreakCard extends StatelessWidget {
  static const Color _flame = Color(0xFFFF9500);
  static const Color _flameDeep = Color(0xFFFF7A00);
  static const Color _idle = Color(0xFF8E8E93);

  final int days;

  const _StreakCard({required this.days});

  @override
  Widget build(BuildContext context) {
    final active = days > 0;
    final next = nextStreakMilestone(days);
    final color = active ? _flame : _idle;
    final previous = previousStreakMilestone(days);
    final progress = next == null
        ? 1.0
        : ((days - previous) / (next - previous)).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFFF7EC) : const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? const Color(0xFFFFE2BC) : const Color(0xFFE5E5EA),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                '连续打卡',
                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
              const Spacer(),
              if (next != null)
                Text(
                  '目标 $next 天',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Icon(
                active ? CupertinoIcons.flame_fill : CupertinoIcons.flame,
                size: 26,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                '$days',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -1,
                  color: color,
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '天',
                  style: TextStyle(fontSize: 13, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MilestoneBar(
            progress: progress,
            color: color,
            track: active ? const Color(0xFFFFE2BC) : const Color(0xFFE5E5EA),
            gradientEnd: _flameDeep,
          ),
          const SizedBox(height: 6),
          Text(
            _caption(days, next),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFFAEAEB2)),
          ),
        ],
      ),
    );
  }

  static String _caption(int days, int? next) {
    if (days <= 0) return '完成一个待办开始打卡';
    if (next == null) return '已达成全部里程碑，太强了';
    return '还差 ${next - days} 天达成 $next 天连击';
  }
}

/// M4 逾期任务卡：**状态化**配色 —— 0 条给正向反馈（绿），有逾期才警示（红），
/// 避免「一切正常时也挂一个红色 0」造成的无谓压力。
class _OverdueCard extends StatelessWidget {
  static const Color _alert = Color(0xFFFF3B30);
  static const Color _calm = Color(0xFF34C759);

  final int count;

  const _OverdueCard({required this.count});

  @override
  Widget build(BuildContext context) {
    final clean = count == 0;
    final color = clean ? _calm : _alert;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: clean ? const Color(0xFFF1FAF3) : const Color(0xFFFFF4F3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: clean ? const Color(0xFFCBEFD5) : const Color(0xFFFFD9D6),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  clean
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.exclamationmark_circle_fill,
                  size: 14,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '逾期任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -1,
                  color: color,
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('项', style: TextStyle(fontSize: 13, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            clean ? '没有逾期任务，继续保持' : '未完成且已过期，尽快处理',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFFAEAEB2)),
          ),
        ],
      ),
    );
  }
}

/// 里程碑细进度条（连续打卡用）：轨道 + 渐变填充
class _MilestoneBar extends StatelessWidget {
  final double progress;
  final Color color;
  final Color track;
  final Color gradientEnd;

  const _MilestoneBar({
    required this.progress,
    required this.color,
    required this.track,
    required this.gradientEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 5,
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress <= 0 ? 0 : progress,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[color, gradientEnd],
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
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
