import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/pages/period/detail/widgets/periodic_item_tile.dart';

/// 「第 N 天」分组（C3-1）：标题 + 该天的周期项列表 + 新增入口。
///
/// 同一天可安排多个事项，按 `sort_order` 排列（C3-4）。
class DayGroup extends StatelessWidget {
  final int dayOffset;
  final List<PeriodicItem> items;
  final VoidCallback onAdd;
  final ValueChanged<PeriodicItem> onEdit;

  /// 天序上限（用于标题上的「共 N 天」提示与越界判断）
  final int dayCount;

  const DayGroup({
    super.key,
    required this.dayOffset,
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.dayCount,
  });

  @override
  Widget build(BuildContext context) {
    final outOfRange = dayOffset >= dayCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: <Widget>[
              Text(
                '第 ${dayOffset + 1} 天',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: outOfRange
                      ? const Color(0xFFFF3B30)
                      : const Color(0xFF1C1C1E),
                ),
              ),
              if (items.isNotEmpty) ...<Widget>[
                const SizedBox(width: 6),
                Text(
                  '${items.length} 项',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                ),
              ],
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAdd,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(CupertinoIcons.add, size: 15, color: Color(0xFF007AFF)),
                      SizedBox(width: 2),
                      Text(
                        '添加',
                        style: TextStyle(fontSize: 13, color: Color(0xFF007AFF)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (outOfRange)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              '该天序已超出当前周期长度，这些事项不会被生成',
              style: TextStyle(fontSize: 11.5, color: Color(0xFFFF3B30)),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: items.isEmpty
              ? _EmptyDay(onAdd: onAdd)
              : Column(
                  children: <Widget>[
                    for (var i = 0; i < items.length; i++) ...<Widget>[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          thickness: 0.6,
                          indent: 16,
                          color: Color(0xFFE5E5EA),
                        ),
                      PeriodicItemTile(
                        item: items[i],
                        onTap: () => onEdit(items[i]),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _EmptyDay extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyDay({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: const Row(
          children: <Widget>[
            Icon(CupertinoIcons.plus_circle, size: 16, color: Color(0xFFC7C7CC)),
            SizedBox(width: 8),
            Text(
              '这一天还没有事项，点击添加',
              style: TextStyle(fontSize: 13, color: Color(0xFFAEAEB2)),
            ),
          ],
        ),
      ),
    );
  }
}
