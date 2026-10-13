import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/empty_state.dart';
import 'package:qingyun_todo/components/error_state.dart';
import 'package:qingyun_todo/components/notification_banner.dart';
import 'package:qingyun_todo/components/floating_add_button.dart';
import 'package:qingyun_todo/logic/todo_actions.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/models/todo_groups.dart';
import 'package:qingyun_todo/pages/todo/widgets/section_header.dart';
import 'package:qingyun_todo/pages/todo/widgets/todo_card.dart';
import 'package:qingyun_todo/pages/todo/widgets/today_progress.dart';
import 'package:qingyun_todo/stores/todo_store.dart';
import 'package:qingyun_todo/services/notification_service.dart';
import 'package:qingyun_todo/stores/db_providers.dart';

/// 待办页：今日进度卡 + 五组列表（逾期 / 今天 / 明天 / 后续 / 已完成）。
///
/// 数据**全部来自 SQLite**（`todoGroupsProvider` / `todayProgressProvider`），
/// 页面只负责渲染与派发意图（docs/04 §2 分层约定）。
class TodoView extends ConsumerStatefulWidget {
  const TodoView({super.key});

  @override
  ConsumerState<TodoView> createState() => _TodoViewState();
}

class _TodoViewState extends ConsumerState<TodoView> {
  /// 「已完成」分组是否展开（Q10：默认折叠）。
  /// 纯 UI 偏好，按 docs/07 §A.1 的边界约定留在 Widget 内，不进 provider。
  bool _showCompleted = false;

  /// 通知自检结果；仅当存在阻断项时展示横幅
  NotificationHealth? _health;
  bool _healthDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshHealth();
    });
  }

  Future<void> _refreshHealth() async {
    final health =
        await ref.read(notificationServiceProvider).checkHealth();
    if (!mounted) return;
    setState(() => _health = health);
  }

  Future<void> _fixNotification() async {
    final service = ref.read(notificationServiceProvider);
    final blocker = _health?.blocker;
    if (blocker == NotificationBlocker.permissionDenied) {
      await service.openNotificationSettings();
    } else if (blocker == NotificationBlocker.exactAlarmDenied) {
      await service.requestExactAlarms();
    }
    await service.reconcile();
    if (!mounted) return;
    await _refreshHealth();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(todoGroupsProvider);
    final progressAsync = ref.watch(todayProgressProvider);

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
          CupertinoSliverNavigationBar(
            backgroundColor: const Color(0xFFF2F2F7),
            // IndexedStack 会同时持有多个带大标题导航栏的页面，
            // 必须给每页唯一 heroTag，否则路由切换时报「multiple heroes share the same tag」
            heroTag: 'todo-large-title',
                // 去掉大标题导航栏底部的发丝分割线（视觉更干净）
                border: null,
            largeTitle: const Text('待办', style: TextStyle(color: Colors.black)),
          ),
          // 通知自检横幅：权限/精确闹钟被拒时给出原因与一键修复
          if (_health != null &&
              !_healthDismissed &&
              _health!.blocker != NotificationBlocker.none &&
              _health!.blocker != NotificationBlocker.unavailable)
            SliverToBoxAdapter(
              child: NotificationBanner(
                health: _health!,
                onDismiss: () => setState(() => _healthDismissed = true),
                onFix: _fixNotification,
                onFixed: _refreshHealth,
              ),
            ),
          // 下拉刷新：重取分组与今日进度
          CupertinoSliverRefreshControl(
            onRefresh: () async {
              ref
                ..invalidate(todoGroupsProvider)
                ..invalidate(todayProgressProvider);
              await ref.read(todoGroupsProvider.future);
            },
          ),
          // 当日任务进度条（口径：仅 remind_date = today，修 R5）
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: progressAsync.when(
                loading: () => const _ProgressSkeleton(),
                error: (error, _) => const SizedBox(height: 96),
                data: (progress) =>
                    TodayProgress(total: progress.total, done: progress.done),
              ),
            ),
          ),
          ...groupsAsync.when(
            loading: () => <Widget>[
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CupertinoActivityIndicator(radius: 14)),
              ),
            ],
            error: (error, _) => <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorState(
                  error: error,
                  title: '待办加载失败',
                  onRetry: () => ref.invalidate(todoGroupsProvider),
                ),
              ),
            ],
            data: _buildSections,
          ),
          // 底部留白：避让悬浮导航栏与浮动按钮
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
          // 右下角浮动新增按钮（替代原导航栏右上角 +）
          Positioned(
            right: 16,
            bottom: floatingBottomOffset(context),
            child: FloatingAddButton(
              semanticLabel: '新建待办',
              onPressed: () => openTodoEdit(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSections(TodoGroups groups) {
    if (groups.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 100),
            // 与周期页空态一致：不放居中新建按钮（与右下角 FAB 重复），只给引导文案
            child: EmptyState(
              icon: CupertinoIcons.checkmark_seal_fill,
              title: '全部搞定！',
              subtitle: '点击右下角的蓝色 + 按钮添加待办，\n'
                  '或在「周期」页安排重复事项',
            ),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    for (final section in groups.sections) {
      if (section.isEmpty) continue; // 空分组不渲染
      final expanded = section.collapsible ? _showCompleted : true;
      widgets.add(
        _sectionSliver(
          padding: EdgeInsets.fromLTRB(20, section == groups.sections.first ? 6 : 12, 20, 10),
          child: SectionHeader(
            title: section.title,
            count: section.count,
            color: section.color,
            expanded: section.collapsible ? _showCompleted : null,
            onTap: section.collapsible
                ? () => setState(() => _showCompleted = !_showCompleted)
                : null,
          ),
        ),
      );
      if (expanded) widgets.add(_cardListSliver(section.items));
    }
    return widgets;
  }

  SliverToBoxAdapter _sectionSliver({
    required EdgeInsets padding,
    required Widget child,
  }) {
    return SliverToBoxAdapter(
      child: Padding(padding: padding, child: child),
    );
  }

  SliverPadding _cardListSliver(List<Todo> todos) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      sliver: SliverList.builder(
        itemCount: todos.length,
        itemBuilder: (context, index) {
          final task = todos[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TodoCard(
              todo: task,
              onToggle: (_) => toggleTodoComplete(context, ref, task),
              onTap: () => openTodoEdit(context, taskId: task.id),
            ),
          );
        },
      ),
    );
  }
}

/// 今日进度卡骨架屏（避免加载时页面跳动）
class _ProgressSkeleton extends StatelessWidget {
  const _ProgressSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Center(
        child: CupertinoActivityIndicator(radius: 11),
      ),
    );
  }
}
