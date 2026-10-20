import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/utils/date_util.dart';

/// 日期快捷项（相对今天的天数偏移）
class QuickDate {
  final String label;
  final int dayOffset;

  const QuickDate(this.label, this.dayOffset);
}

/// 时间快捷项（`HH:mm`）
class QuickTime {
  final String label;
  final String time;

  const QuickTime(this.label, this.time);
}

/// 时间选择结果：[cleared] 为 true 表示用户主动清空（提醒时间可空）
class TimePickResult {
  final String? time;
  final bool cleared;

  const TimePickResult(this.time, {this.cleared = false});
}

/// 默认日期快捷项（docs/07 B2-3）
const List<QuickDate> kDefaultQuickDates = <QuickDate>[
  QuickDate('今天', 0),
  QuickDate('明天', 1),
  QuickDate('下周', 7),
];

/// 默认时间快捷项
const List<QuickTime> kDefaultQuickTimes = <QuickTime>[
  QuickTime('早上', '08:00'),
  QuickTime('中午', '12:00'),
  QuickTime('今晚', '20:00'),
];

/// iOS 风格日期选择弹层；取消返回 null。
///
/// 允许选择过去的日期，以支持「补记」（docs/07 B2-4）。
Future<DateTime?> pickDate(
  BuildContext context, {
  DateTime? initial,
  List<QuickDate> quickDates = kDefaultQuickDates,
  String title = '提醒日期',
}) async {
    final result = await showCupertinoModalPopup<_SheetResult>(
      context: context,
      builder: (ctx) => _PickerSheet(
        title: title,
        mode: CupertinoDatePickerMode.date,
        initial: DateUtil.dateOnly(initial ?? DateUtil.today()),
        quickDates: quickDates,
      ),
    );
    return result?.value;
  }

/// iOS 风格时间选择弹层；取消返回 null，清空返回 [TimePickResult] 且 `cleared = true`。
Future<TimePickResult?> pickTime(
  BuildContext context, {
  String? initial,
  List<QuickTime> quickTimes = kDefaultQuickTimes,
  String title = '提醒时间',
}) async {
  final now = DateTime.now();
  final parts = (initial ?? '09:00').split(':');
  final hour = int.tryParse(parts[0]) ?? 9;
  final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  final result = await showCupertinoModalPopup<_SheetResult>(
    context: context,
    builder: (ctx) => _PickerSheet(
      title: title,
      mode: CupertinoDatePickerMode.time,
      initial: DateTime(now.year, now.month, now.day, hour, minute),
      quickTimes: quickTimes,
      allowClear: true,
      clearLabel: '不提醒时间',
    ),
  );
  if (result == null) return null;
  if (result.cleared) return const TimePickResult(null, cleared: true);
  return TimePickResult(DateUtil.formatTime(result.value!));
}

class _SheetResult {
  final DateTime? value;
  final bool cleared;

  const _SheetResult(this.value, {this.cleared = false});
}

class _PickerSheet extends StatefulWidget {
  final String title;
  final CupertinoDatePickerMode mode;
  final DateTime initial;
  final List<QuickDate> quickDates;
  final List<QuickTime> quickTimes;
  final bool allowClear;
  final String clearLabel;

  const _PickerSheet({
    required this.title,
    required this.mode,
    required this.initial,
    this.quickDates = const <QuickDate>[],
    this.quickTimes = const <QuickTime>[],
    this.allowClear = false,
    this.clearLabel = '清除',
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late DateTime _value = widget.initial;

  bool get _isDateMode => widget.mode == CupertinoDatePickerMode.date;

  void _setValue(DateTime value) => setState(() => _value = value);

  void _confirm() => Navigator.of(context).pop(_SheetResult(_value));

  void _clear() =>
      Navigator.of(context).pop(const _SheetResult(null, cleared: true));

  @override
  Widget build(BuildContext context) {
    final today = DateUtil.today();
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildHeader(),
            const Divider(height: 1, thickness: 0.6, color: Color(0xFFE5E5EA)),
            if (_hasQuickOptions) _buildQuickOptions(today),
            SizedBox(
              height: 216,
              child: CupertinoDatePicker(
                // key 随取值变化重建，使快捷项点击能真正改动滚轮位置
                key: ValueKey<DateTime>(_value),
                mode: widget.mode,
                initialDateTime: _value,
                use24hFormat: true,
                minuteInterval: 1,
                minimumDate: DateTime(1970),
                maximumDate: DateTime(today.year + 50, 12, 31),
                onDateTimeChanged: (v) => _value = v,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  bool get _hasQuickOptions =>
      (_isDateMode && widget.quickDates.isNotEmpty) ||
      (!_isDateMode && (widget.quickTimes.isNotEmpty || widget.allowClear));

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '取消',
              style: TextStyle(fontSize: 16, color: Color(0xFF8E8E93)),
            ),
          ),
          Expanded(
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C1E),
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            onPressed: _confirm,
            child: const Text(
              '确定',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF007AFF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickOptions(DateTime today) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: <Widget>[
          if (widget.allowClear)
            _Chip(label: widget.clearLabel, onTap: _clear, destructive: true),
          if (_isDateMode)
            for (final quick in widget.quickDates)
              _Chip(
                label: quick.label,
                selected: DateUtil.dateOnly(_value) ==
                    DateUtil.addDays(today, quick.dayOffset),
                onTap: () => _setValue(DateUtil.addDays(today, quick.dayOffset)),
              ),
          if (!_isDateMode)
            for (final quick in widget.quickTimes)
              _Chip(
                label: '${quick.label} ${quick.time}',
                selected: DateUtil.formatTime(_value) == quick.time,
                onTap: () => _setValue(
                  DateTime(
                    _value.year,
                    _value.month,
                    _value.day,
                    int.parse(quick.time.split(':')[0]),
                    int.parse(quick.time.split(':')[1]),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool destructive;

  const _Chip({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFFF3B30)
        : (selected ? const Color(0xFF007AFF) : const Color(0xFF636366));
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected || destructive
                ? color.withValues(alpha: 0.12)
                : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
