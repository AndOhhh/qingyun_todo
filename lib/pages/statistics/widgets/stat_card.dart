import 'package:flutter/material.dart';

/// 统计小卡（M2~M6 通用）：标题 + 大数字 + 可选副标题 / 附加内容（如周点阵）
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final Color color;
  final IconData? icon;
  final Widget? extra;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    this.subtitle,
    this.icon,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -0.5,
              color: color,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFFAEAEB2)),
            ),
          ],
          if (extra != null) ...<Widget>[const SizedBox(height: 8), extra!],
        ],
      ),
    );
  }
}

/// 图表卡容器：标题 + 口径说明 + 内容
class ChartCard extends StatelessWidget {
  final String title;
  final String? caption;
  final Widget child;

  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1E),
            ),
          ),
          if (caption != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              caption!,
              style: const TextStyle(fontSize: 11, color: Color(0xFFAEAEB2)),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// 图表空态占位
class ChartEmpty extends StatelessWidget {
  final String message;

  const ChartEmpty({super.key, this.message = '该范围内暂无数据'});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          message,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFFAEAEB2)),
        ),
      ),
    );
  }
}
