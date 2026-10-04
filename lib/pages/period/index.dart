import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/empty_state.dart';
import 'package:qingyun_todo/components/error_state.dart';
import 'package:qingyun_todo/components/floating_add_button.dart';
import 'package:qingyun_todo/logic/periodic_actions.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/pages/period/widgets/periodic_card.dart';
import 'package:qingyun_todo/stores/periodic_store.dart';

/// 周期页（FR-10）：周期列表 + 新增入口 + 启用开关 + 左滑删除。
///
/// 数据全部来自 SQLite（`periodicListProvider`），无 mock。
class PeriodView extends ConsumerWidget {
  const PeriodView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(periodicListProvider);

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
            // 与待办页区分，避免同一路由子树内 Hero tag 冲突
            heroTag: 'periodic-large-title',
                // 去掉大标题导航栏底部的发丝分割线（视觉更干净）
                border: null,
            largeTitle: const Text('周期', style: TextStyle(color: Colors.black)),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () async {
              ref.invalidate(periodicListProvider);
              await ref.read(periodicListProvider.future);
            },
          ),
          ...listAsync.when(
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
                  title: '周期加载失败',
                  onRetry: () => ref.invalidate(periodicListProvider),
                ),
              ),
            ],
            data: (entries) => entries.isEmpty
                ? <Widget>[_emptySliver(context)]
                : <Widget>[_listSliver(context, ref, entries)],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
          Positioned(
            right: 16,
            bottom: 96,
            child: FloatingAddButton(
              semanticLabel: '新建周期',
              onPressed: () => openPeriodicEdit(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySliver(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 100),
        // 不再放居中新建按钮：与右下角浮动按钮重复，
        // 空态只负责说明「周期是什么」并引导点击右下角 +
        child: EmptyState(
          icon: CupertinoIcons.repeat,
          iconColor: const Color(0xFF007AFF),
          title: '还没有周期',
          subtitle: '把「每 2 天喝牛奶 / 喝豆浆」这类重复安排交给周期，\n'
              '它会自动生成待办，并按轮次记录完成情况。\n'
              '点击右下角的蓝色 + 按钮新建第一个周期。',
        ),
      ),
    );
  }

  Widget _listSliver(
    BuildContext context,
    WidgetRef ref,
    List<PeriodicListEntry> entries,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      sliver: SliverList.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final periodic = entry.periodic;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PeriodicCard(
              entry: entry,
              onTap: () => openPeriodicDetail(context, periodic.id!),
              onToggleActive: (value) =>
                  togglePeriodicActive(context, ref, periodic),
            ),
          );
        },
      ),
    );
  }
}
