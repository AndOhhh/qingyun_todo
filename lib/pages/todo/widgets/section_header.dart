import 'package:flutter/cupertino.dart';

/// 列表分组标题：`标题 · 数量`，可选折叠箭头
class SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool? expanded;
  final VoidCallback? onTap;

  const SectionHeader({
    super.key,
    required this.title,
    required this.count,
    this.expanded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return Row(
      children: [
        Text(
          '$title · $count',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8E8E93),
            letterSpacing: 0.4,
          ),
        ),
        const Spacer(),
        if (tap != null)
          GestureDetector(
            onTap: tap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedRotation(
                turns: (expanded ?? false) ? 0.0 : -0.5,
                duration: const Duration(milliseconds: 220),
                child: const Icon(
                  CupertinoIcons.chevron_down,
                  size: 14,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
