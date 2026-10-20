import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/utils/date_util.dart';

/// A7 月历热力图：按 `completed_at` 统计每日完成数，色深 = 数量。
///
/// 复用 [DateUtil.monthGrid] 的网格算法（与日程页同源），自带月份翻页；
/// 全局时间范围切换会把它重置回当前月（月历热力本质按月，见 docs/05 §J 说明）。
class HeatmapMonth extends StatelessWidget {
  final DateTime month;
  final Map<String, int> counts;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const HeatmapMonth({
    super.key,
    required this.month,
    required this.counts,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  static const Color _kBlue = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final cells = DateUtil.monthGrid(month);
    final activeDays = counts.values.where((c) => c > 0).length;
    final total = counts.values.fold<int>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _arrow(CupertinoIcons.chevron_left, onPrevMonth),
            Text(
              '${month.year}年${month.month}月',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C1E),
              ),
            ),
            _arrow(CupertinoIcons.chevron_right, onNextMonth),
            const Spacer(),
            Text(
              '$activeDays 天有完成 · 共 $total 次',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            for (final name in <String>['日', '一', '二', '三', '四', '五', '六'])
              Expanded(
                child: Center(
                  child: Text(
                    name,
                    style: TextStyle(fontSize: 10, color: Color(0xFFAEAEB2)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var week = 0; week * 7 < cells.length; week++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: <Widget>[
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _cell(cells[week * 7 + col]),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            const Text(
              '少',
              style: TextStyle(fontSize: 10, color: Color(0xFFAEAEB2)),
            ),
            for (final level in const <int>[0, 1, 2, 4])
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(
                  color: _colorFor(level),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const Text(
              '多',
              style: TextStyle(fontSize: 10, color: Color(0xFFAEAEB2)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cell(DateTime? day) {
    if (day == null) return const SizedBox(height: 30);
    final count = counts[DateUtil.formatDate(day)] ?? 0;
    return AspectRatio(
      aspectRatio: 1.15,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: _colorFor(count),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: count > 0 ? FontWeight.w600 : FontWeight.w400,
              color: count >= 2 ? Colors.white : const Color(0xFF8E8E93),
            ),
          ),
        ),
      ),
    );
  }

  Color _colorFor(int count) {
    if (count <= 0) return const Color(0xFFEDEDF0);
    if (count == 1) return _kBlue.withValues(alpha: 0.30);
    if (count == 2) return _kBlue.withValues(alpha: 0.55);
    if (count == 3) return _kBlue.withValues(alpha: 0.80);
    return _kBlue;
  }

  Widget _arrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(icon, size: 14, color: const Color(0xFF8E8E93)),
      ),
    );
  }
}
