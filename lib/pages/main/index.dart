import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/pages/period/index.dart';
import 'package:qingyun_todo/pages/schedule/index.dart';
import 'package:qingyun_todo/pages/statistics/index.dart';
import 'package:qingyun_todo/pages/todo/index.dart';
import 'package:qingyun_todo/stores/bootstrap.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/stores/todo_store.dart';

/// 选中态统一使用的蓝色（iOS Files 风格）
const Color _kSelectedColor = Color(0xFF007AFF);

/// 底部 Tab 数据模型
class _TabItem {
  final String label;
  final IconData icon;

  const _TabItem({required this.label, required this.icon});
}

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage>
    with WidgetsBindingObserver {
  // 各个页面视图
  final List<Widget> _children = const [
    TodoView(),
    PeriodView(),
    ScheduleView(),
    StatisticsView(),
  ];

  // 导航栏下标位置
  int _currentIndex = 0;

  // 底部 Tab 列表（iOS 时钟 App 风格：图标 + 中文 label）
  static const List<_TabItem> _tabList = [
    _TabItem(label: '待办', icon: Icons.checklist_rounded),
    _TabItem(label: '周期', icon: Icons.autorenew_rounded),
    _TabItem(label: '日程', icon: Icons.event_note_rounded),
    _TabItem(label: '统计', icon: Icons.insights_rounded),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 触发时机①：App 启动 → 建库 + 滚动生成周期实例（docs/07 C4-2）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) bootstrapApp(ref);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 触发时机④：跨日校准。
  /// 用「回到前台 + 日期比对」而不是常驻定时器，避免后台耗电（docs/07 C4-2）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      recalibrateIfDayChanged(ref);
      // 回前台：重排 OS 通知 + 启动前台兜底巡检
      final service = ref.read(notificationServiceProvider);
      service
        ..reconcile()
        ..startForegroundWatch();
    } else if (state == AppLifecycleState.paused && mounted) {
      // 进后台：停止兜底巡检，把提醒交还给 OS 排期
      final service = ref.read(notificationServiceProvider);
      service.stopForegroundWatch();
      service.reconcile();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 任何待办写操作都会失效 todoGroupsProvider → 借此统一触发通知重排，
    // 避免在各写操作调用点零散维护通知状态
    ref.listen<Object?>(todoGroupsProvider, (previous, next) {
      ref.read(notificationServiceProvider).reconcile();
    });
    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFF2F2F7),
      body: IndexedStack(index: _currentIndex, children: _children),
      bottomNavigationBar: SafeArea(top: false, child: _buildTabBar()),
    );
  }

  /// iOS 风格日间胶囊底部导航栏
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              // 整体白色半透明玻璃背景（日间效果）
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.06),
                width: 0.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(_tabList.length, (index) {
                final selected = index == _currentIndex;
                return Expanded(
                  child: _ClockTabItem(
                    label: _tabList[index].label,
                    icon: _tabList[index].icon,
                    selected: selected,
                    onTap: () {
                      setState(() => _currentIndex = index);
                    },
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个 Tab 项：仅选中项显示浅色胶囊背景，图标/文字变色；
/// 未选中项图标与 label 均为白色。
class _ClockTabItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ClockTabItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? _kSelectedColor : const Color(0xFF1C1C1E);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          // ✅ 胶囊背景包裹 icon + 文本整体
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            decoration: BoxDecoration(
              // 圆角 = 内容高度的一半，呈现完全圆滑的胶囊形
              borderRadius: BorderRadius.circular(28),
              color: selected
                  ? const Color(0xFF007AFF).withValues(alpha: 0.10)
                  : Colors.transparent,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: foreground),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: foreground,
                    letterSpacing: 0.2,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
