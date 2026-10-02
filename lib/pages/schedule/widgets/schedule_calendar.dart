import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/todo_groups.dart';
import 'package:qingyun_todo/utils/date_util.dart';
import 'package:qingyun_todo/utils/lunar_util.dart';

/// 日程页月历：月份头（含周序号与翻页）+ 星期行 + 日期网格（FR-16）。
///
/// - 支持**月 ↔ 单周折叠**（3）：折叠后只渲染选中日所在周，跨月日期补全并置灰；
/// - 标记（4）：当天 1 条 → 圆点；>1 条 → 数字角标；颜色语义同下；
/// - 颜色语义（逾期不入库，按「日期 < 今天」实时派生）：
///   红 = 有逾期未完成，蓝 = 有未完成，绿 = 全部完成。
///
/// 农历 / 节假日 / 班休标签不在本组件内（见 docs/07 §J 待确认清单）。
class ScheduleCalendar extends StatelessWidget {
  /// 当前展示的月份（取该月任意一天即可）
  final DateTime month;

  final DateTime selected;
  final DateTime today;

  /// `{YYYY-MM-DD: DayMarkers}`
  final Map<String, DayMarkers> markers;

  /// 是否折叠为单周视图（3）
  final bool weekOnly;

  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToggleWeekOnly;

  const ScheduleCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.today,
    required this.markers,
    required this.weekOnly,
    required this.onDaySelected,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onToggleWeekOnly,
  });

  static const Color _kBlue = Color(0xFF007AFF);
  static const Color _kRed = Color(0xFFFF3B30);
  static const Color _kGreen = Color(0xFF34C759);
  static const Color _kText = Color(0xFF1C1C1E);
  static const Color _kMuted = Color(0xFF8E8E93);
  static const Color _kDim = Color(0xFFC7C7CC);

  bool get _isCurrentMonth =>
      month.year == today.year && month.month == today.month;

  @override
  Widget build(BuildContext context) {
    final cells = weekOnly
        ? DateUtil.weekOf(selected).map<DateTime?>((d) => d).toList()
        : DateUtil.monthGrid(month);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
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
          _buildWeekToggle(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: <Widget>[
          _ArrowButton(
            icon: CupertinoIcons.chevron_left,
            semanticLabel: '上个月',
            onTap: onPrevMonth,
          ),
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
          _ArrowButton(
            icon: CupertinoIcons.chevron_right,
            semanticLabel: '下个月',
            onTap: onNextMonth,
          ),
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

  /// 月 ↔ 单周折叠把手（参考图：折叠态在周行下方显示向下箭头）
  Widget _buildWeekToggle() {
    return Semantics(
      button: true,
      label: weekOnly ? '展开月历' : '折叠为单周',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggleWeekOnly,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedRotation(
            turns: weekOnly ? 0.5 : 0,
            duration: const Duration(milliseconds: 220),
            child: const Icon(
              CupertinoIcons.chevron_up,
              size: 15,
              color: _kMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCell(DateTime? day) {
    if (day == null) return const SizedBox(height: 52);
    final key = DateUtil.formatDate(day);
    final marker = markers[key];
    final isSelected = DateUtil.dateOnly(day) == DateUtil.dateOnly(selected);
    final isToday = DateUtil.dateOnly(day) == DateUtil.dateOnly(today);
    // 单周视图下跨月日期置灰（参考图折叠态的 30 / 31）
    final isOutsideMonth = weekOnly && day.month != month.month;

    final lunar = LunarUtil.info(day);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onDaySelected(day),
      child: SizedBox(
        height: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // 数字圆 + 右上角「班/休」角标（紧贴数字，参考图样式）
            SizedBox(
              width: 42,
              height: 34,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isSelected ? _kBlue : Colors.transparent,
                        shape: BoxShape.circle,
                        border: isToday && !isSelected
                            ? Border.all(
                                color: _kBlue.withValues(alpha: 0.45),
                                width: 1.2,
                              )
                            : null,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.1,
                                fontWeight: isSelected || isToday
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : isOutsideMonth
                                        ? _kDim
                                        : (isToday ? _kBlue : _kText),
                              ),
                            ),
                            // 选中日把农历小字收进实心圆内（参考图），
                            // 避免白字落在浅色背景上看不见
                            if (isSelected)
                              Text(
                                lunar.subLabel,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  fontSize: 7.5,
                                  height: 1.1,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (lunar.cornerTag != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Text(
                        lunar.cornerTag!,
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: lunar.isWork ? const Color(0xFFFF9500) : _kBlue,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!isSelected) ...<Widget>[
              const SizedBox(height: 1),
              // 农历 / 节日 / 节气小字（参考图日期下方）
              SizedBox(
                height: 12,
                child: Center(
                  child: Text(
                    lunar.subLabel,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 8.5,
                      height: 1.1,
                      color: isOutsideMonth
                          ? _kDim
                          : lunar.isFestival
                              ? const Color(0xFF636366)
                              : const Color(0xFFAEAEB2),
                    ),
                  ),
                ),
              ),
            ],
            DayMarkerBadge(
              count: marker == null ? 0 : marker.pending + marker.done,
              color: _markerColor(day, marker),
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

/// 日期标记（4）：0 条不占位，1 条画圆点，>1 条显示数字角标
class DayMarkerBadge extends StatelessWidget {
  final int count;
  final Color color;

  const DayMarkerBadge({super.key, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    if (count <= 0 || color == Colors.transparent) {
      return const SizedBox(width: 14, height: 10);
    }
    if (count == 1) {
      return SizedBox(
        width: 14,
        height: 10,
        child: Center(
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      );
    }
    return SizedBox(
      width: 14,
      height: 10,
      child: Center(
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// 月份翻页小箭头
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  const _ArrowButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Icon(icon, size: 16, color: const Color(0xFF8E8E93)),
        ),
      ),
    );
  }
}
