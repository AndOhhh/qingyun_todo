import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/error_state.dart';
import 'package:qingyun_todo/components/floating_add_button.dart';
import 'package:qingyun_todo/components/swipe_action.dart';
import 'package:qingyun_todo/logic/todo_actions.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/models/todo_groups.dart';
import 'package:qingyun_todo/pages/schedule/widgets/day_timeline.dart';
import 'package:qingyun_todo/pages/schedule/widgets/month_summary.dart';
import 'package:qingyun_todo/pages/schedule/widgets/schedule_calendar.dart';
import 'package:qingyun_todo/pages/schedule/widgets/schedule_task_card.dart';
import 'package:qingyun_todo/stores/schedule_store.dart';
import 'package:qingyun_todo/utils/date_util.dart';
import 'package:qingyun_todo/utils/lunar_util.dart';

/// 日程页（FR-16 / FR-17）：月历 + 当日安排。
///
/// - 月历标记点：红 = 有逾期未完成，蓝 = 有未完成，绿 = 全部完成；
/// - 点日期 → 下方列出该日**全部**待办（常规 + 周期实例），可直接勾选完成；
/// - 点卡片主体 → 复用待办页的编辑控件（`openTodoEdit`）；
/// - 左滑卡片 → 复用待办页的删除动作（含周期实例三级删除）；
/// - 右下角「今」按钮回到今天。
///
/// 数据全部来自 SQLite（`monthMarkersProvider` / `dayTasksProvider`）。
class ScheduleView extends ConsumerStatefulWidget {
  const ScheduleView({super.key});

  @override
  ConsumerState<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends ConsumerState<ScheduleView> {
  late DateTime _selected = DateUtil.today();
  late DateTime _month = DateUtil.firstDayOfMonth(_selected);

  /// 「当日安排」是否折叠（纯 UI 状态，留在 Widget 内）
  bool _dayCollapsed = false;

  /// 月历是否折叠为单周（3，纯 UI 状态）
  bool _weekOnly = false;

  void _selectDay(DateTime day) {
    setState(() {
      _selected = DateUtil.dateOnly(day);
      _month = DateUtil.firstDayOfMonth(day);
      _dayCollapsed = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateUtil.addMonthsCalendar(_month, delta));
  }

  void _jumpToday() => _selectDay(DateUtil.today());

  @override
  Widget build(BuildContext context) {
    final today = DateUtil.today();
    final monthKey = DateUtil.monthKey(_month);
    final dateKey = DateUtil.formatDate(_selected);
    final markersAsync = ref.watch(monthMarkersProvider(monthKey));
    final tasksAsync = ref.watch(dayTasksProvider(dateKey));

    return CupertinoTheme(
      data: const CupertinoThemeData(
        primaryColor: Color(0xFF007AFF),
        scaffoldBackgroundColor: Color(0xFFF2F2F7),
      ),
      child: Stack(
        children: <Widget>[
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: <Widget>[
              // 不用 CupertinoSliverNavigationBar：它的「middle 行 + 大标题行」
              // 两段式结构在去掉标题文字后仍占据约 50px 空白；改为紧凑标题行，
              // 整页内容上移。翻月只保留月历上的横滑手势（右上角箭头已取消）。
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: Semantics(
                      header: true,
                      child: Center(
                        child: _MonthTitle(month: _month, selected: _selected),
                      ),
                    ),
                  ),
                ),
              ),
              CupertinoSliverRefreshControl(
                onRefresh: () async {
                  ref
                    ..invalidate(monthMarkersProvider)
                    ..invalidate(dayTasksProvider);
                  await ref.read(dayTasksProvider(dateKey).future);
                },
              ),
              SliverToBoxAdapter(
                child: ScheduleCalendar(
                  month: _month,
                  selected: _selected,
                  today: today,
                  markers: markersAsync.valueOrNull ?? const <String, DayMarkers>{},
                  weekOnly: _weekOnly,
                  onDaySelected: _selectDay,
                  onPrevMonth: () => _shiftMonth(-1),
                  onNextMonth: () => _shiftMonth(1),
                  onToggleWeekOnly: () =>
                      setState(() => _weekOnly = !_weekOnly),
                ),
              ),
              // 当月概览（9）：复用月历标记的聚合结果，不新增查询
              SliverToBoxAdapter(
                child: MonthSummary(
                  markers: markersAsync.valueOrNull ?? const <String, DayMarkers>{},
                ),
              ),
              SliverToBoxAdapter(
                child: _buildDayHeader(tasksAsync.valueOrNull?.length),
              ),
              // 当日时间轴（2a）：仅在有安排且未折叠时展示
              if (!_dayCollapsed)
                ...tasksAsync.when(
                  loading: () => <Widget>[],
                  error: (error, _) => <Widget>[],
                  data: (tasks) => tasks.isEmpty
                      ? <Widget>[]
                      : <Widget>[
                          SliverToBoxAdapter(child: DayTimeline(tasks: tasks)),
                        ],
                ),
              if (!_dayCollapsed)
                ...tasksAsync.when(
                  loading: () => <Widget>[_skeletonSliver()],
                  error: (error, _) => <Widget>[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: ErrorState(
                          error: error,
                          title: '当日安排加载失败',
                          onRetry: () =>
                              ref.invalidate(dayTasksProvider(dateKey)),
                        ),
                      ),
                    ),
                  ],
                  data: (tasks) => tasks.isEmpty
                      ? <Widget>[_emptyDaySliver()]
                      : <Widget>[_cardsSliver(tasks)],
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 150)),
            ],
          ),
          // 「今」在上、新增在下：新增是更高频的主操作，放在最顺手的角落；
          // 两个按钮尺寸统一为 56
          Positioned(
            right: 16,
            bottom: 164,
            child: _TodayFab(onTap: _jumpToday),
          ),
          Positioned(
            right: 16,
            bottom: 96,
            child: FloatingAddButton(
              semanticLabel: '新建待办（预填选中日期）',
              onPressed: () => openTodoEdit(context, initialDate: _selected),
            ),
          ),
        ],
      ),
    );
  }

  /// 拖拽把手 + 「当日安排」折叠头（参考图样式）
  Widget _buildDayHeader(int? count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: <Widget>[
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D1D6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _dayCollapsed = !_dayCollapsed),
            child: Row(
              children: <Widget>[
                Text(
                  '${DateUtil.dateLabel(_selected)} · '
                  '${_selected.month}月${_selected.day}日 '
                  '${DateUtil.weekdayLabel(_selected)} · '
                  '${LunarUtil.info(_selected).lunarFull}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                if (count != null && count > 0)
                  Text(
                    ' · $count 项',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                  ),
                const Spacer(),
                const Text(
                  '当日安排',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _dayCollapsed ? -0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(
                    CupertinoIcons.chevron_down,
                    size: 13,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardsSliver(List<Todo> tasks) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      sliver: SliverList.builder(
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SwipeAction(
              borderRadius: 16,
              actions: <SwipeActionItem>[
                SwipeActionItem(
                  icon: CupertinoIcons.trash,
                  label: '删除',
                  color: const Color(0xFFFF3B30),
                  onTap: () => requestDeleteTodo(context, ref, task),
                ),
              ],
              child: ScheduleTaskCard(
                task: task,
                onToggle: (_) => toggleTodoComplete(context, ref, task),
                // 复用首页的编辑控件（含周期实例「只影响这一次」提示）
                onTap: () => openTodoEdit(context, taskId: task.id),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyDaySliver() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: <Widget>[
              const Icon(
                CupertinoIcons.calendar_badge_plus,
                size: 34,
                color: Color(0xFFC7C7CC),
              ),
              const SizedBox(height: 10),
              Text(
                '${_selected.month}月${_selected.day}日还没有安排',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 6),
              // 与周期页空态一致：不放居中按钮（与右下角 FAB 重复），
              // 只引导点击右下角 +；FAB 会预填当前选中日期
              Text(
                '点击右下角的蓝色 + 按钮\n为 ${_selected.month}月${_selected.day}日 添加待办',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Color(0xFFAEAEB2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeletonSliver() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: CupertinoActivityIndicator(radius: 11),
          ),
        ),
      ),
    );
  }
}

/// 右下角「回到今天」悬浮按钮（参考图）
class _TodayFab extends StatelessWidget {
  final VoidCallback onTap;

  const _TodayFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '回到今天',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          // 与 FloatingAddButton 同尺寸（56）
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              '今',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF007AFF),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 标题栏：`2026年10月  第 42 周`。
///
/// 周序号取「选中日」（选中日在当前展示月内时），否则取展示月 1 号，
/// 保证左右滑动翻月时标题整体联动变化。
class _MonthTitle extends StatelessWidget {
  final DateTime month;
  final DateTime selected;

  const _MonthTitle({required this.month, required this.selected});

  @override
  Widget build(BuildContext context) {
    final inMonth =
        selected.year == month.year && selected.month == month.month;
    final anchor = inMonth ? selected : month;
    return Text.rich(
      TextSpan(
        children: <TextSpan>[
          TextSpan(
            text: '${month.year}年${month.month}月',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Color(0xFF1C1C1E),
            ),
          ),
          TextSpan(
            text: '  第 ${DateUtil.isoWeek(anchor)} 周',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8E8E93),
            ),
          ),
        ],
      ),
    );
  }
}
