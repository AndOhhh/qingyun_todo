import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/cycle_rule.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 未来 3 轮日期预览时间轴（C2-5）：**所见即所得**。
///
/// 直接复用生成引擎用的同一套 [CycleRule]，因此预览出来的日期
/// 就是将要写进 `tasks` 的日期；短月份被跳过的事项也会如实显示（C2-6 / TC-04）。
class CyclePreviewTimeline extends StatelessWidget {
  final List<CyclePreview> previews;
  final List<PeriodicItem> items;

  const CyclePreviewTimeline({
    super.key,
    required this.previews,
    this.items = const <PeriodicItem>[],
  });

  @override
  Widget build(BuildContext context) {
    if (previews.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < previews.length; i++)
          _CycleRow(
            preview: previews[i],
            items: items,
            isLast: i == previews.length - 1,
          ),
      ],
    );
  }
}

class _CycleRow extends StatelessWidget {
  final CyclePreview preview;
  final List<PeriodicItem> items;
  final bool isLast;

  const _CycleRow({
    required this.preview,
    required this.items,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 时间轴：圆点 + 竖线
          Column(
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5),
                decoration: const BoxDecoration(
                  color: Color(0xFF007AFF),
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: const Color(0xFFD1D1D6),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '第 ${preview.cycleIndex + 1} 轮 · '
                    '${_short(preview.startDate)} ~ ${_short(preview.endDate)}'
                    '（${preview.length} 天）',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  if (items.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 5),
                    ..._itemLines(preview),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _short(DateTime d) => '${d.month}月${d.day}日';

  List<Widget> _itemLines(CyclePreview preview) {
    final widgets = <Widget>[];
    final sorted = items.toList()
      ..sort((a, b) => a.dayOffset.compareTo(b.dayOffset));
    for (final item in sorted) {
      final skipped = item.dayOffset >= preview.length;
      final date = skipped
          ? null
          : DateUtil.addDays(preview.startDate, item.dayOffset);
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: <Widget>[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: skipped ? const Color(0xFFC7C7CC) : item.accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  date == null
                      ? '${item.dayLabel}：本轮只有 ${preview.length} 天，跳过「${item.title}」'
                      : '${_short(date)}'
                          '${item.remindTime == null ? '' : ' ${item.remindTime}'}'
                          '　${item.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: skipped
                        ? const Color(0xFFAEAEB2)
                        : const Color(0xFF636366),
                    decoration:
                        skipped ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }
}
