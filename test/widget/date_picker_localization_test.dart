import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/components/floating_add_button.dart';
import 'package:qingyun_todo/pages/todo/index.dart';
import 'package:qingyun_todo/routes/index.dart';
import 'package:qingyun_todo/stores/db_providers.dart';

import '../repositories/test_support.dart';

/// 日期选择器中文化：`CupertinoDatePicker` 的月份 / 星期文案取自
/// `CupertinoLocalizations`，根 `MaterialApp` 不注册 `Global*Localizations`
/// 就会回落到框架内置英文（Oct / Sun…）。
void main() {
  late TestStore store;

  setUp(() async {
    store = await TestStore.create(noIsolate: true);
  });

  tearDown(() async => store.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dbHelperProvider.overrideWithValue(store.db),
        ],
        child: getRootWidget(),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  /// 中文月份带「月」后缀（十月 / 10月），英文为 October / Oct
  void expectChineseMonthInPicker(WidgetTester tester) {
    final picker = find.byType(CupertinoDatePicker);
    expect(picker, findsOneWidget);
    expect(
      find.descendant(of: picker, matching: find.textContaining('月')),
      findsWidgets,
      reason: '日期滚轮应显示中文月份',
    );
  }

  testWidgets('根应用固定中文：CupertinoLocalizations 已注册并生效', (tester) async {
    await pumpApp(tester);

    final context = tester.element(find.byType(TodoView));
    expect(Localizations.localeOf(context).languageCode, 'zh');

    final localizations = CupertinoLocalizations.of(context);
    expect(localizations.datePickerMonth(10), contains('月'));
    expect(localizations.datePickerMonth(10), isNot(contains('Oct')));
  });

  testWidgets('待办新增：日期选择器为中文', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byType(FloatingAddButton));
    await settle(tester);
    expect(find.text('新建待办'), findsOneWidget);

    await tester.tap(find.text('日期'));
    await settle(tester);

    expectChineseMonthInPicker(tester);
  });

  testWidgets('周期新增：日期选择器为中文', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('周期'));
    await settle(tester);
    await tester.tap(find.byType(FloatingAddButton));
    await settle(tester);
    expect(find.text('周期规则'), findsOneWidget);

    await tester.tap(find.text('起始日期'));
    await settle(tester);

    expectChineseMonthInPicker(tester);
  });
}
