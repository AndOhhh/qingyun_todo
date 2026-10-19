import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/models/todo_groups.dart';
import 'package:qingyun_todo/pages/schedule/widgets/schedule_calendar.dart';

/// 月历组件：首尾相邻月日期灰色补齐 + 点击回调（N17）。
void main() {
  Future<void> pumpCalendar(
    WidgetTester tester, {
    required DateTime month,
    required ValueChanged<DateTime> onDaySelected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScheduleCalendar(
              month: month,
              selected: DateTime(2026, 10, 19),
              today: DateTime(2026, 10, 19),
              markers: const <String, DayMarkers>{},
              weekOnly: false,
              onDaySelected: onDaySelected,
              onPrevMonth: () {},
              onNextMonth: () {},
              onToggleWeekOnly: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('2026-10：前导补上月末 4 天，点击灰色日期回调该日', (tester) async {
    DateTime? tapped;
    await pumpCalendar(
      tester,
      month: DateTime(2026, 10),
      onDaySelected: (day) => tapped = day,
    );

    // 9/27~9/30 以灰色补在首周；10 月正好收在周六，尾部无补齐
    for (final day in <int>[27, 28, 29, 30]) {
      expect(find.text('$day'), findsWidgets, reason: '应补出 9 月 $day 日');
    }
    // 9/30 与 10/30 同日号各一格
    expect(find.text('30'), findsNWidgets(2));

    await tester.tap(find.text('30').first);
    expect(tapped, DateTime(2026, 9, 30));
  });

  testWidgets('2026-11：尾部补下月初 5 天，点击灰色日期回调该日', (tester) async {
    DateTime? tapped;
    await pumpCalendar(
      tester,
      month: DateTime(2026, 11),
      onDaySelected: (day) => tapped = day,
    );

    // 11/1 为周日 → 无前导补齐；但尾部补出的 12/1 同日号，故 '1' 出现两格
    expect(find.text('1'), findsNWidgets(2));
    expect(find.text('5'), findsWidgets, reason: '应补出 12 月 5 日');

    // 尾部最后一格是 12/5
    final lastCellDay = find.text('5').last;
    await tester.tap(lastCellDay);
    expect(tapped, DateTime(2026, 12, 5));
  });
}
