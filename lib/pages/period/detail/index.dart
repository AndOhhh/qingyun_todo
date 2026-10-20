import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/empty_state.dart';
import 'package:qingyun_todo/components/error_state.dart';
import 'package:qingyun_todo/components/form_card.dart';
import 'package:qingyun_todo/logic/periodic_actions.dart';
import 'package:qingyun_todo/logic/todo_actions.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/pages/period/detail/widgets/day_group.dart';
import 'package:qingyun_todo/stores/periodic_store.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 周期详情页 = 周期项管理页（FR-12 / C3）。
///
/// 按「第 1 天 / 第 2 天 …」分组展示模板项，可增删改；
/// 顶部统计区展示总实例 / 已完成 / 完成率 / 当前轮进度（C3-8）。
class PeriodicDetailPage extends ConsumerWidget {
  final int periodicId;

  const PeriodicDetailPage({super.key, required this.periodicId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(periodicDetailProvider(periodicId));

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: CupertinoNavigationBar(
        middle: Text(
          async.valueOrNull?.periodic.name ?? '周期',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: async.valueOrNull == null
              ? null
              : () => openPeriodicEdit(context, periodicId: periodicId),
          child: const Text(
            '编辑',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF007AFF),
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () =>
            const Center(child: CupertinoActivityIndicator(radius: 13)),
        error: (error, _) => ErrorState(
          error: error,
          title: '周期加载失败',
          onRetry: () => ref.invalidate(periodicDetailProvider(periodicId)),
        ),
        data: (detail) {
          if (detail == null) {
            return EmptyState(
              icon: CupertinoIcons.question_circle,
              iconColor: const Color(0xFF8E8E93),
              title: '周期不存在',
              subtitle: '它可能已被删除',
              action: CupertinoButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            );
          }
          return _buildBody(context, ref, detail);
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    PeriodicDetail detail,
  ) {
    final periodic = detail.periodic;
    final days = _visibleDays(detail);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      children: <Widget>[
        _StatsCard(detail: detail),
        const SizedBox(height: 14),
        FormCard(
          children: <Widget>[
            FormRow(
              label: '启用',
              trailing: Transform.scale(
                scale: 0.86,
                child: CupertinoSwitch(
                  value: periodic.isActive,
                  activeTrackColor: const Color(0xFF007AFF),
                  onChanged: (_) =>
                      togglePeriodicActive(context, ref, periodic),
                ),
              ),
            ),
            FormRow(
              label: '周期',
              valueText:
                  '${periodic.intervalLabel} · ${periodic.startDateLabel}起'
                  '${periodic.endDate == null ? '' : ' ~ ${DateUtil.humanDate(periodic.endDate!)}'}',
            ),
            FormRow(
              label: '下次提醒',
              valueText: _nextRemindText(detail.nextRemind, periodic),
            ),
            if (periodic.remark != null && periodic.remark!.isNotEmpty)
              FormRow(label: '备注', valueText: periodic.remark),
          ],
        ),
        const SizedBox(height: 20),
        // D7：周期项全部删除后不自动暂停，只提示无可生成事项
        if (detail.hasNoItems)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: InfoBanner(
              text: '当前无可生成事项。为某一天添加事项后，才会自动生成待办。',
              color: Color(0xFF007AFF),
            ),
          ),
        for (final day in days) ...<Widget>[
          DayGroup(
            dayOffset: day,
            dayCount: detail.dayCount,
            items: detail.itemsByDay[day] ?? const <PeriodicItem>[],
            onAdd: () => openPeriodicItemEdit(
              context,
              periodicId: periodicId,
              dayOffset: day,
            ),
            onEdit: (item) =>
                openPeriodicItemEdit(context, itemId: item.id),
          ),
          const SizedBox(height: 16),
        ],
        // 轮长度较长（自定义 N 天 / 每月 / 每年）时只展示已安排事项的天，
        // 另给一个总入口（N25）
        if (detail.dayCount > 7)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: CupertinoButton.filled(
              borderRadius: BorderRadius.circular(14),
              onPressed: () => openPeriodicItemEdit(
                context,
                periodicId: periodicId,
              ),
              child: const Text('添加事项', style: TextStyle(fontSize: 15)),
            ),
          ),
        const SizedBox(height: 4),
        _InstancesSection(
          periodicId: periodicId,
          periodicName: periodic.name,
        ),
        const SizedBox(height: 28),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => requestDeletePeriodic(
            context,
            periodicId: periodicId,
            periodicName: periodic.name,
            onDeleted: () => Navigator.of(context).pop(),
          ),
          child: const Text(
            '删除周期',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFF3B30),
            ),
          ),
        ),
      ],
    );
  }

  /// 需要展示的天序：
  /// - 轮长度 ≤ 7 天（每天 / 每周）：全展示（含空白天，方便按天添加）；
  /// - 更长的轮（自定义 N 天 / 每月 / 每年）：只展示已安排事项的天 + 一个「添加事项」
  ///   总入口，避免「每月」渲染 28 个「这一天还没有事项」空块（N25）。
  List<int> _visibleDays(PeriodicDetail detail) {
    final days = <int>{};
    if (detail.dayCount <= 7) {
      days.addAll(List<int>.generate(detail.dayCount, (i) => i));
    }
    days.addAll(detail.itemsByDay.keys);
    final sorted = days.toList()..sort();
    return sorted;
  }

  String _nextRemindText(Todo? next, Periodic periodic) {
    if (!periodic.isActive) return '已暂停，不再生成新待办';
    if (next == null) return '暂无待生成事项';
    return '${next.dueDateLabel}'
        '${next.remindTime == null ? '' : ' ${next.remindTime}'} · ${next.title}';
  }
}

/// 统计区（C3-8）：总实例 / 已完成 / 完成率 / 当前轮进度
class _StatsCard extends StatelessWidget {
  final PeriodicDetail detail;

  const _StatsCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final progress = detail.currentCycle;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            spreadRadius: -3,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          _metric('总实例', '${detail.totalInstances}'),
          _divider(),
          _metric('已完成', '${detail.completedInstances}'),
          _divider(),
          _metric('完成率', '${(detail.completionRate * 100).round()}%'),
          _divider(),
          _metric(
            progress == null ? '当前轮' : progress.cycleLabel,
            progress?.label ?? '—',
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 0.6,
        height: 28,
        color: const Color(0xFFE5E5EA),
      );

  Widget _metric(String label, String value, {bool highlight = false}) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: highlight
                  ? const Color(0xFF007AFF)
                  : const Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }
}

/// 近期实例（只读）：让用户确认模板已经生成了哪些待办，点击可进入待办编辑页
class _InstancesSection extends ConsumerWidget {
  final int periodicId;
  final String periodicName;

  const _InstancesSection({
    required this.periodicId,
    required this.periodicName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(periodicInstancesProvider(periodicId));
    final instances = async.valueOrNull ?? const <Todo>[];
    final today = DateUtil.today();
    final upcoming = instances
        .where((t) => !t.isCompleted && !t.remindDate.isBefore(today))
        .take(6)
        .toList(growable: false);

    return FormCard(
      header: '近期已生成',
      footer: upcoming.isEmpty
          ? '「$periodicName」当前没有待完成的实例。'
          : '这些待办由周期自动生成，点击可单独修改（不回写模板）。',
      children: <Widget>[
        if (upcoming.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Text(
              '暂无待完成的实例',
              style: TextStyle(fontSize: 13, color: Color(0xFFAEAEB2)),
            ),
          )
        else
          for (final task in upcoming)
            FormRow(
              label: task.remindTime == null
                  ? task.dueDateLabel
                  : '${task.dueDateLabel} ${task.remindTime}',
              valueText: task.title,
              valueColor: const Color(0xFF1C1C1E),
              showChevron: true,
              minHeight: 46,
              onTap: () => openTodoEdit(context, taskId: task.id),
            ),
      ],
    );
  }
}
