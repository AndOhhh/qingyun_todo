import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// 当日任务进度卡片：日期 + 已完成/总数 + 渐变进度条
class TodayProgress extends StatelessWidget {
  final int total;
  final int done;

  const TodayProgress({super.key, required this.total, required this.done});

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final pctText = '${(percent * 100).round()}%';
    final now = DateTime.now();
    final dateText = '${now.month}月${now.day}日';
    final weekday = _weekday(now.weekday);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            spreadRadius: -3,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  CupertinoIcons.calendar,
                  size: 18,
                  color: Color(0xFF007AFF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '今日进度',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E),
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dateText · $weekday',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$done/$total',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF007AFF),
                      height: 1.0,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pctText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildBar(percent),
          const SizedBox(height: 8),
          Text(
            percent >= 1.0
                ? '今日任务全部完成 ✓'
                : '还差 ${total - done} 项任务，加油',
            style: const TextStyle(fontSize: 12, color: Color(0xFF636366)),
          ),
        ],
      ),
    );
  }

  /// 渐变进度条（蓝 → 绿）
  Widget _buildBar(double percent) {
    return Stack(
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFFE5E5EA),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        LayoutBuilder(
          builder: (context, c) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              height: 8,
              width: c.maxWidth * percent,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF007AFF), Color(0xFF34C759)],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          },
        ),
      ],
    );
  }

  String _weekday(int w) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[(w - 1) % 7];
  }
}
