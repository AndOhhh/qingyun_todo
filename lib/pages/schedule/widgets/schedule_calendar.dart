import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/todo_groups.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 日程页月历：月份头（含周序号与翻页）+ 星期行 + 周日开头的日期网格（FR-16）。
///
/// 标记点语义（逾期不入库，按「日期 < 今天」实时派生）：
/// - 红点：当天有**逾期未完成**
/// - 蓝点：当天有未完成
/// - 绿点：当天全部完成
///
/// 农历 / 节假日 / 班休标签不在本组件内（见 docs/07 §J 待确认清单）。
class ScheduleCalendar extends StatelessWidget {
  /// 当前展示的月份（取该月任意一天即可）
  final DateTime month;

  final DateTime selected;
  final DateTime today;

  /// `{YYYY-MM-DD: DayMarkers}`
  final Map<String, DayMarkers> markers;

  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const ScheduleCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.today,
    required this.markers,
    required this.onDaySelected,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  static const Color _kBlue = Color(0xFF007AFF);
  static const Color _kRed = Color(0xFFFF3B30);
  static const Color _kGreen = Color(0xFF34C759);
  static const Color _kText = Color(0xFF1C1C1E);
  static const Color _kMuted = Color(0xFF8E8E93);

  bool get _isCurrentMonth =>
      month.year == today.year && month.month == today.month;

  @override
  Widget build(BuildContext context) {
    final cells = DateUtil.monthGrid(month);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        children: <Widget>[
          _buildHeader(),
          const SizedBox(height: 10),
          _buildWeekdayRow(),
          const SizedBox(height: 4),
          // 左右滑动翻月
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -200) {
                onNextMonth();
              } else if (velocity > 200) {
                onPrevMonth();
              }
            },
            child: Column(
              children: <Widget>[
                for (var week = 0; week * 7 < cells.length; week++)
                  Row(
                    children: <Widget>[
                      for (var col = 0; col < 7; col++)
                        Expanded(child: _buildCell(cells[week * 7 + col])),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: <Widget>[
          _ArrowButton(icon: CupertinoIcons.chevron_left, onTap: onPrevMonth),
          const SizedBox(width: 4),
          Text(
            '${month.year}年${month.month}月',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: _kText,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '第 ${DateUtil.isoWeek(selected)} 周',
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
          const Spacer(),
          if (!_isCurrentMonth)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onDaySelected(today),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '今天',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _kBlue,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          _ArrowButton(icon: CupertinoIcons.chevron_right, onTap: onNextMonth),
        ],
      ),
    );
  }

  Widget _buildWeekdayRow() {
    const names = <String>['日', '一', '二', '三', '四', '五', '六'];
    return Row(
      children: <Widget>[
        for (final name in names)
          Expanded(
            child: Center(
              child: Text(
                name,
                style: const TextStyle(fontSize: 11, color: _kMuted),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCell(DateTime? day) {
    if (day == null) return const SizedBox(height: 52);
    final key = DateUtil.formatDate(day);
    final marker = markers[key];
    final isSelected = DateUtil.dateOnly(day) == DateUtil.dateOnly(selected);
    final isToday = DateUtil.dateOnly(day) == DateUtil.dateOnly(today);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onDaySelected(day),
      child: SizedBox(
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? _kBlue : Colors.transparent,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: _kBlue.withValues(alpha: 0.45), width: 1.2)
                    : null,
              ),
              child: Center(
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        isSelected || isToday ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : (isToday ? _kBlue : _kText),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            // 事件标记点
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: _markerColor(day, marker),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _markerColor(DateTime day, DayMarkers? marker) {
    if (marker == null || marker.isEmpty) return Colors.transparent;
    if (marker.hasPending && day.isBefore(today)) return _kRed;
    if (marker.hasPending) return _kBlue;
    return _kGreen;
  }
}

/// 月份翻页小箭头
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Icon(icon, size: 16, color: const Color(0xFF8E8E93)),
      ),
    );
  }
}
