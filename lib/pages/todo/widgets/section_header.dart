import 'package:flutter/cupertino.dart';

/// 列表分组标题：`标题 · 数量`，可指定标题色与折叠箭头
class SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final bool? expanded;
  final VoidCallback? onTap;

  const SectionHeader({
    super.key,
    required this.title,
    required this.count,
    this.color = const Color(0xFF8E8E93),
    this.expanded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return GestureDetector(
      // 整行可点（折叠），而不只是箭头
      onTap: tap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: <Widget>[
          Text(
            '$title · $count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          if (tap != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              // 收起 → 向下（⌄）；展开 → 向上（⌃）。chevron_down 旋转半圈即向上，
              // 方向写反会让「收起」看起来像「展开」（N23）。
              child: AnimatedRotation(
                turns: (expanded ?? false) ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: const Icon(
                  CupertinoIcons.chevron_down,
                  size: 14,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
