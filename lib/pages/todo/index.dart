import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/empty_state.dart';
import 'package:qingyun_todo/components/error_state.dart';
import 'package:qingyun_todo/components/swipe_action.dart';
import 'package:qingyun_todo/logic/todo_actions.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/models/todo_groups.dart';
import 'package:qingyun_todo/pages/todo/widgets/section_header.dart';
import 'package:qingyun_todo/pages/todo/widgets/todo_card.dart';
import 'package:qingyun_todo/pages/todo/widgets/today_progress.dart';
import 'package:qingyun_todo/stores/todo_store.dart';

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

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(todoGroupsProvider);
    final progressAsync = ref.watch(todayProgressProvider);

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
            // IndexedStack 会同时持有多个带大标题导航栏的页面，
            // 必须给每页唯一 heroTag，否则路由切换时报「multiple heroes share the same tag」
            heroTag: 'todo-large-title',
            largeTitle: const Text('待办', style: TextStyle(color: Colors.black)),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => openTodoEdit(context),
              child: const Icon(
                CupertinoIcons.add_circled,
                size: 26,
                color: Color(0xFF007AFF),
              ),
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
          // 底部留白：避让悬浮导航栏
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
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
            child: EmptyState(
              icon: CupertinoIcons.checkmark_seal_fill,
              title: '全部搞定！',
              subtitle: '点击右上角添加新待办，\n或在「周期」页安排重复事项',
              action: CupertinoButton.filled(
                borderRadius: BorderRadius.circular(20),
                onPressed: () => openTodoEdit(context),
                child: const Text('新建待办', style: TextStyle(fontSize: 15)),
              ),
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
            // 间距放在卡片外层：SwipeAction 的动作区才能与卡片等高
            padding: const EdgeInsets.only(bottom: 10),
            child: SwipeAction(
              actions: <SwipeActionItem>[
                SwipeActionItem(
                  icon: CupertinoIcons.trash,
                  label: '删除',
                  // 红色垃圾桶：与绿色勾选在颜色、手势、确认强度上全部区分（Q5）
                  color: const Color(0xFFFF3B30),
                  onTap: () => requestDeleteTodo(context, ref, task),
                ),
              ],
              child: TodoCard(
                todo: task,
                onToggle: (_) => toggleTodoComplete(context, ref, task),
                onTap: () => openTodoEdit(context, taskId: task.id),
              ),
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
