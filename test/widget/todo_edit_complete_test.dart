import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/pages/todo/index.dart';
import 'package:qingyun_todo/routes/index.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/utils/date_util.dart';

import '../repositories/test_support.dart';

/// 编辑页「标记完成 / 取消完成」：状态即时落库并直接返回上一页（N20）。
void main() {
  late TestStore store;

  setUp(() async {
    store = await TestStore.create(noIsolate: true);
  });

  tearDown(() async => store.dispose());

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dbHelperProvider.overrideWithValue(store.db),
        ],
        child: getRootWidget(),
      ),
    );
    await settle(tester);
  }

  testWidgets('标记完成 → 落库并直接返回；取消完成同样直接返回', (tester) async {
    useTallScreen(tester);
    final id = await store.tasks.insert(
      Todo(title: '要完成的待办', remindDate: DateUtil.today()),
    );
    await pumpApp(tester);

    // 打开编辑页
    await tester.tap(find.text('要完成的待办'));
    await settle(tester);
    expect(find.text('编辑待办'), findsOneWidget);

    // 标记完成：无需再点保存，直接回列表
    await tester.tap(find.text('标记完成'));
    await settle(tester);
    expect(find.text('编辑待办'), findsNothing, reason: '完成后应直接返回上一页');
    expect(find.byType(TodoView), findsOneWidget);
    expect((await store.tasks.findById(id))!.isCompleted, isTrue);

    // 展开「已完成」分组 → 重新打开 → 取消完成 → 同样直接返回
    await tester.tap(find.textContaining('已完成 · 1'));
    await settle(tester);
    await tester.tap(find.text('要完成的待办'));
    await settle(tester);
    expect(find.text('取消完成'), findsOneWidget);

    await tester.tap(find.text('取消完成'));
    await settle(tester);
    expect(find.text('编辑待办'), findsNothing, reason: '取消完成也应直接返回上一页');
    expect((await store.tasks.findById(id))!.isCompleted, isFalse);
  });
}
