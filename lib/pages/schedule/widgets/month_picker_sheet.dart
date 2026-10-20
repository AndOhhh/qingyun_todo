import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 月份选择弹层（iOS 日历同款交互：点标题跳转任意月份）。
///
/// 返回所选月份的**第一天**；取消返回 null。
/// 年份范围 = 今天 ± 10 年，覆盖补记与规划场景且滚轮不至于过长。
Future<DateTime?> showMonthPicker(
  BuildContext context, {
  required DateTime month,
  required DateTime today,
}) {
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (ctx) => _MonthPickerSheet(initialMonth: month, today: today),
  );
}

class _MonthPickerSheet extends StatefulWidget {
  final DateTime initialMonth;
  final DateTime today;

  const _MonthPickerSheet({required this.initialMonth, required this.today});

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late final int _minYear = widget.today.year - 10;
  late final int _maxYear = widget.today.year + 10;

  late int _yearIndex =
      (widget.initialMonth.year - _minYear).clamp(0, _maxYear - _minYear);
  late int _monthIndex = widget.initialMonth.month - 1;

  late final FixedExtentScrollController _yearController =
      FixedExtentScrollController(initialItem: _yearIndex);
  late final FixedExtentScrollController _monthController =
      FixedExtentScrollController(initialItem: _monthIndex);

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  int get _selectedYear => _minYear + _yearIndex;

  void _backToCurrentMonth() {
    _yearController.animateToItem(
      widget.today.year - _minYear,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    _monthController.animateToItem(
      widget.today.month - 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: <Widget>[
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(fontSize: 16, color: Color(0xFF8E8E93)),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '跳转月份',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    onPressed: () => Navigator.of(context)
                        .pop(DateTime(_selectedYear, _monthIndex + 1, 1)),
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
            ),
            const Divider(height: 1, thickness: 0.6, color: Color(0xFFE5E5EA)),
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _backToCurrentMonth,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      '回到本月（${widget.today.year}年${widget.today.month}月）',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 200,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: _yearController,
                      itemExtent: 38,
                      onSelectedItemChanged: (i) => _yearIndex = i,
                      children: <Widget>[
                        for (var y = _minYear; y <= _maxYear; y++)
                          Center(
                            child: Text(
                              '$y年',
                              style: const TextStyle(
                                fontSize: 17,
                                color: Color(0xFF1C1C1E),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: _monthController,
                      itemExtent: 38,
                      onSelectedItemChanged: (i) => _monthIndex = i,
                      children: <Widget>[
                        for (var m = 1; m <= 12; m++)
                          Center(
                            child: Text(
                              '$m月',
                              style: const TextStyle(
                                fontSize: 17,
                                color: Color(0xFF1C1C1E),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
