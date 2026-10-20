import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/components/todo_tag.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 周期列表卡片（C1-1 / C1-2）：
/// 名称、周期文案、起始日、本轮进度 `x/y`、已完成轮数、下次提醒、启用开关。
class PeriodicCard extends StatelessWidget {
  final PeriodicListEntry entry;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback? onTap;

  const PeriodicCard({
    super.key,
    required this.entry,
    required this.onToggleActive,
    this.onTap,
  });

  static const Color _kBlue = Color(0xFF007AFF);
  static const Color _kGrey = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    final periodic = entry.periodic;
    final paused = !periodic.isActive;
    final ended = periodic.isEnded(DateUtil.today());
    final progress = entry.currentCycle;
    final next = entry.nextRemind;
    final accent = paused ? _kGrey : _kBlue;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: paused ? 0.66 : 1,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: paused ? 0.05 : 0.14),
                blurRadius: 18,
                spreadRadius: -3,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(CupertinoIcons.refresh, size: 18, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          periodic.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: Color(0xFF1C1C1E),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${periodic.intervalLabel} · ${periodic.startDateLabel}起',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 启用开关（C6-1）：暂停后停止生成，已有实例保留
                  Transform.scale(
                    scale: 0.86,
                    child: CupertinoSwitch(
                      value: periodic.isActive,
                      activeTrackColor: _kBlue,
                      onChanged: onToggleActive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (progress != null) ...<Widget>[
                _ProgressBar(percent: progress.rate, color: accent),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Text(
                      '${progress.cycleLabel} ${progress.label}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '已完成 ${periodic.completedCount} 轮',
                      style: const TextStyle(fontSize: 12, color: _kGrey),
                    ),
                  ],
                ),
              ] else ...<Widget>[
                Text(
                  periodic.completedCount > 0
                      ? '已完成 ${periodic.completedCount} 轮 · 暂无进行中的轮次'
                      : '尚未生成待办',
                  style: const TextStyle(fontSize: 12, color: _kGrey),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: next == null
                        ? Text(
                            paused
                                ? '已暂停，不再生成新待办'
                                : (ended ? '已到终止日期' : '暂无待生成事项'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: _kGrey),
                          )
                        : Text(
                            '下次：${next.dueDateLabel}'
                            '${next.remindTime == null ? '' : ' ${next.remindTime}'}'
                            ' · ${next.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF636366),
                            ),
                          ),
                  ),
                  if (paused || ended) ...<Widget>[
                    const SizedBox(width: 6),
                    TodoTag(
                      text: paused ? '已暂停' : '已结束',
                      color: _kGrey,
                    ),
                  ],
                  const SizedBox(width: 4),
                  const Icon(
                    CupertinoIcons.chevron_right,
                    size: 13,
                    color: Color(0xFFC7C7CC),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 本轮进度条（细条，蓝 → 绿渐变，与今日进度卡一致）
class _ProgressBar extends StatelessWidget {
  final double percent;
  final Color color;

  const _ProgressBar({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: <Widget>[
          Container(
            height: 5,
            width: constraints.maxWidth,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E5EA),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            height: 5,
            width: constraints.maxWidth * percent.clamp(0.0, 1.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[color, const Color(0xFF34C759)],
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}
