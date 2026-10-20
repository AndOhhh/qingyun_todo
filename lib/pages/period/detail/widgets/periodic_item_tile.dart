import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/components/todo_tag.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/models/todo_priority.dart';

/// 周期项行（模板项）：左侧色条 + 标题 + 提醒时间 / 优先级标签。
class PeriodicItemTile extends StatelessWidget {
  final PeriodicItem item;
  final VoidCallback? onTap;

  const PeriodicItemTile({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(0, 11, 12, 11),
        child: Row(
          children: <Widget>[
            // 左侧色条 = 生成实例后的卡片色带
            Container(width: 4, height: 30, color: item.accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  if (item.remark != null && item.remark!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      item.remark!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (item.remindTime != null)
              TodoTag(
                text: item.remindTime!,
                icon: CupertinoIcons.clock,
                color: const Color(0xFF007AFF),
              ),
            if (item.priority != TodoPriority.none) ...<Widget>[
              const SizedBox(width: 6),
              TodoTag(text: item.priority.label, color: item.priority.color),
            ],
            const SizedBox(width: 4),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 13,
              color: Color(0xFFC7C7CC),
            ),
          ],
        ),
      ),
    );
  }
}
