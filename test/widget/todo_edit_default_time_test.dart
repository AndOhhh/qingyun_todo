import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/pages/todo/edit/index.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/utils/date_util.dart';

import '../repositories/test_support.dart';

/// 提醒时间选择器的默认值（B2-3）：
/// - 待办页新增 → 当前时刻；
/// - 日程页新增（带 initialDate）→ 保持 09:00；
/// - 编辑已有待办 → 沿用库里的提醒时间。
void main() {
  late TestStore store;

  setUp(() async {
    store = await TestStore.create(noIsolate: true);
  });

  tearDown(() async => store.dispose());

  Future<void> pumpEdit(
    WidgetTester tester, {
    int? taskId,
    DateTime? initialDate,
  }) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dbHelperProvider.overrideWithValue(store.db),
        ],
        child: MaterialApp(
          home: TodoEditPage(taskId: taskId, initialDate: initialDate),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 点开时间行 → 返回选择器滚轮的初始时间
  Future<DateTime> openTimePicker(WidgetTester tester, Finder rowText) async {
    await tester.tap(rowText);
    await tester.pumpAndSettle();
    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    return picker.initialDateTime;
  }

  bool sameMinute(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;

  testWidgets('待办页新增：时间选择器默认当前时刻（而非 09:00）', (tester) async {
    await pumpEdit(tester);

    // 选择器在「点开那一刻」取当前时间，跨越分钟边界时以 before/after 两者之一为准
    final before = DateTime.now();
    final picked = await openTimePicker(tester, find.text('不设置'));
    final after = DateTime.now();

    expect(
      sameMinute(picked, before) || sameMinute(picked, after),
      isTrue,
      reason: '选择器应落在当前时刻附近，实际 $picked'
          '（before=$before, after=$after）',
    );
  });

  testWidgets('日程页新增（带 initialDate）：保持 09:00 默认', (tester) async {
    await pumpEdit(tester, initialDate: DateUtil.today());

    final picked = await openTimePicker(tester, find.text('不设置'));

    expect(picked.hour, 9);
    expect(picked.minute, 0);
  });

  testWidgets('编辑已有待办：选择器默认沿用库里的提醒时间', (tester) async {
    final id = await store.tasks.insert(
      Todo(
        title: '带提醒的待办',
        remindDate: DateUtil.today(),
        remindTime: '18:30',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    await pumpEdit(tester, taskId: id);

    final picked = await openTimePicker(tester, find.text('18:30'));

    expect(picked.hour, 18);
    expect(picked.minute, 30);
  });
}
