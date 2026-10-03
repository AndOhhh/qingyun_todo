import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qingyun_todo/models/statistics_models.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/pages/statistics/index.dart';
import 'package:qingyun_todo/routes/index.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/utils/date_util.dart';

import '../repositories/test_support.dart';

/// 统计页（FR-18）端到端：空态引导、M1~M6 指标卡、范围切换、热力图。
void main() {
  late TestStore store;
  late DateTime today;

  setUp(() async {
    store = await TestStore.create(noIsolate: true);
    today = DateUtil.today();
  });

  tearDown(() async => store.dispose());

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );

  Future<void> gotoStatistics(WidgetTester tester) async {
    await tester.tap(find.text('统计').last);
    await settle(tester);
  }

  testWidgets('空库显示统计引导，而不是一排 --', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[dbHelperProvider.overrideWithValue(store.db)],
        child: getRootWidget(),
      ),
    );
    await settle(tester);
    await gotoStatistics(tester);

    expect(find.text('还没有统计数据'), findsOneWidget);
    expect(find.text('--'), findsNothing);
    expect(find.textContaining('完成第一个待办'), findsOneWidget);
  });

  testWidgets('M1~M6 指标卡按口径渲染', (tester) async {
    // 今日：1 完成 + 1 未完成 → 50%
    final doneId = await store.tasks.insert(
      Todo(title: '已完成', remindDate: today),
    );
    await store.tasks.insert(Todo(title: '未完成', remindDate: today));
    await store.tasks.toggleComplete(doneId, to: true);
    // 逾期 1 条
    await store.tasks.insert(
      Todo(title: '逾期', remindDate: DateUtil.addDays(today, -2)),
    );
    // 孤儿周期已完成实例 → 计入 M6（100%）
    final db = await store.db.database;
    await db.insert('tasks', <String, Object?>{
      'title': '孤儿周期实例',
      'remind_date': DateUtil.formatDate(DateUtil.addDays(today, -1)),
      'priority': 'none',
      'is_completed': 1,
      'completed_at':
          DateUtil.formatTimestamp(DateUtil.addDays(today, -1)),
      'source_type': 'PERIODIC',
      'periodic_id': null,
      'cycle_index': 0,
      'periodic_name_snapshot': '已删除的周期',
      'sort_order': 0,
      'is_notified': 0,
      'created_at': DateUtil.formatTimestamp(today),
      'updated_at': DateUtil.formatTimestamp(today),
    });

    useTallScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[dbHelperProvider.overrideWithValue(store.db)],
        child: getRootWidget(),
      ),
    );
    await settle(tester);
    await gotoStatistics(tester);

    // 六张指标卡标题齐全
    for (final title in const <String>[
      '今日完成率',
      '连续打卡',
      '本周完成率',
      '逾期任务',
      '待处理总数',
      '周期完成率',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    // M1 与 M2 同数据同口径 → 两处 50%；M6 = 100%（孤儿记录计入）
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.text('100%'), findsOneWidget);
    // M4 = 1 逾期，M5 = 2 待处理
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    // M3 连续打卡 = 2（昨天 + 今天）
    expect(find.textContaining('保持住'), findsOneWidget);
  });

  testWidgets('范围切换只影响趋势/分布卡片文案与数据', (tester) async {
    await store.tasks.insert(Todo(title: '今天的事', remindDate: today));
    useTallScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[dbHelperProvider.overrideWithValue(store.db)],
        child: getRootWidget(),
      ),
    );
    await settle(tester);
    await gotoStatistics(tester);

    expect(find.text('本周 · 按天（实际完成时间）'), findsOneWidget);
    await tester.tap(find.text('本月'));
    await settle(tester);
    expect(find.text('本月 · 按天（实际完成时间）'), findsOneWidget);
    await tester.tap(find.text('今天'));
    await settle(tester);
    expect(find.text('今天 · 按小时（实际完成时间）'), findsOneWidget);
    await tester.tap(find.text('全部'));
    await settle(tester);
    expect(find.text('全部 · 按月（实际完成时间）'), findsOneWidget);
    // 核心指标卡不受范围影响，始终在
    expect(find.text('今日完成率'), findsOneWidget);
  });

  testWidgets('月历热力图渲染当月并带图例', (tester) async {
    final doneId = await store.tasks.insert(
      Todo(title: '已完成', remindDate: today),
    );
    await store.tasks.toggleComplete(doneId, to: true);
    useTallScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[dbHelperProvider.overrideWithValue(store.db)],
        child: getRootWidget(),
      ),
    );
    await settle(tester);
    await gotoStatistics(tester);

    expect(find.text('完成热力'), findsOneWidget);
    expect(find.text('${today.year}年${today.month}月'), findsOneWidget);
    expect(find.text('少'), findsOneWidget);
    expect(find.text('多'), findsOneWidget);
    expect(find.textContaining('1 天有完成 · 共 1 次'), findsOneWidget);
  });

  testWidgets('范围切换选中态为主色浅调而非默认灰白', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[dbHelperProvider.overrideWithValue(store.db)],
        child: getRootWidget(),
      ),
    );
    await settle(tester);
    await gotoStatistics(tester);

    final control = tester.widget<CupertinoSlidingSegmentedControl<StatsRange>>(
      find.byType(CupertinoSlidingSegmentedControl<StatsRange>),
    );
    expect(control.thumbColor, StatisticsView.kRangeThumbColor);
    expect(control.backgroundColor, Colors.white);
    // 选中项文字为主色加粗
    final selected = tester.widget<Text>(
      find.descendant(
        of: find.byType(CupertinoSlidingSegmentedControl<StatsRange>),
        matching: find.text('本周'),
      ),
    );
    expect(selected.style?.color, const Color(0xFF007AFF));
    expect(selected.style?.fontWeight, FontWeight.w600);
  });
}
