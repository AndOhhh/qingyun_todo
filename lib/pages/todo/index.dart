import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/pages/todo/widgets/todo_card.dart';
import 'package:qingyun_todo/pages/todo/widgets/section_header.dart';
import 'package:qingyun_todo/pages/todo/widgets/today_progress.dart';

class TodoView extends StatefulWidget {
  const TodoView({super.key});

  @override
  State<TodoView> createState() => _TodoViewState();
}

class _TodoViewState extends State<TodoView> {
  // mock 数据
  final List<Todo> _todos = [
    Todo(
      id: '1',
      title: '计算机证书考试',
      note: '复习第 3 章操作系统',
      dueDate: DateTime(2026, 8, 20),
      isOverdue: true,
      subDone: 7,
      subTotal: 12,
      priority: TodoPriority.high,
      accentColor: const Color(0xFFFF3B30),
    ),
    Todo(
      id: '2',
      title: '晨跑 5 公里',
      isPeriodic: true,
      dueDate: DateTime(2026, 8, 17),
      subDone: 3,
      subTotal: 5,
      priority: TodoPriority.medium,
      accentColor: const Color(0xFFFF9500),
    ),
    Todo(
      id: '3',
      title: '阅读《设计的法则》',
      note: '第 4-6 章',
      dueDate: DateTime(2026, 8, 19),
      isOverdue: true,
      isPeriodic: true,
      subDone: 2,
      subTotal: 8,
      priority: TodoPriority.low,
      accentColor: const Color(0xFFFFCC00),
    ),
    Todo(
      id: '4',
      title: '整理周报',
      dueDate: DateTime(2026, 8, 18),
      priority: TodoPriority.medium,
      accentColor: const Color(0xFF34C759),
    ),
    Todo(
      id: '5',
      title: '学 Flutter 动画',
      note: 'Hero / ImplicitAnimations',
      dueDate: DateTime(2026, 8, 22),
      subDone: 1,
      subTotal: 4,
      priority: TodoPriority.low,
      accentColor: const Color(0xFF007AFF),
    ),
    Todo(
      id: '6',
      title: '给爸妈打电话',
      done: true,
      accentColor: const Color(0xFF5856D6),
    ),
  ];

  bool _showCompleted = true;

  @override
  Widget build(BuildContext context) {
    final pending = _todos.where((t) => !t.done).toList();
    final completed = _todos.where((t) => t.done).toList();

    return CupertinoTheme(
      data: CupertinoThemeData(
        primaryColor: const Color(0xFF007AFF),
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      ),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // 顶部大标题
          CupertinoSliverNavigationBar(
            backgroundColor: const Color(0xFFF2F2F7),
            largeTitle: Text('待办', style: TextStyle(color: Colors.black)),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _handleAdd,
              child: const Icon(
                CupertinoIcons.add_circled,
                size: 26,
                color: Color(0xFF007AFF),
              ),
            ),
          ),
          // 当日任务进度条
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TodayProgress(
                total: _todos.length,
                done: _todos.where((t) => t.done).length,
              ),
            ),
          ),
          // 待办分组标题 + 卡片
          if (pending.isNotEmpty) ...[
            _sectionSliver(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: SectionHeader(title: '待处理', count: pending.length),
            ),
            _cardListSliver(pending),
          ],
          // 已完成分组标题 + 卡片（可折叠）
          if (completed.isNotEmpty) ...[
            _sectionSliver(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: SectionHeader(
                title: '已完成',
                count: completed.length,
                expanded: _showCompleted,
                onTap: () =>
                    setState(() => _showCompleted = !_showCompleted),
              ),
            ),
            if (_showCompleted) _cardListSliver(completed),
          ],
          // 空状态
          if (_todos.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 100),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      CupertinoIcons.checkmark_seal_fill,
                      size: 64,
                      color: Color(0xFF34C759),
                    ),
                    SizedBox(height: 16),
                    Text(
                      '全部搞定！',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '点击右上角添加新待办',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 底部留白
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  /// 分组标题 Sliver
  SliverToBoxAdapter _sectionSliver({
    required EdgeInsets padding,
    required Widget child,
  }) {
    return SliverToBoxAdapter(
      child: Padding(padding: padding, child: child),
    );
  }

  /// 卡片列表 Sliver
  SliverPadding _cardListSliver(List<Todo> todos) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      sliver: SliverList.builder(
        itemCount: todos.length,
        itemBuilder: (context, index) =>
            TodoCard(todo: todos[index], onToggle: _toggle),
      ),
    );
  }

  void _toggle(String id) {
    setState(() {
      final t = _todos.firstWhere((e) => e.id == id);
      t.done = !t.done;
    });
  }

  void _handleAdd() {
    // TODO：后续接入状态管理后触发添加逻辑
  }
}
