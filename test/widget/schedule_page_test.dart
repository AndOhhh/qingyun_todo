import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/pages/schedule/widgets/schedule_calendar.dart';
import 'package:qingyun_todo/routes/index.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/utils/date_util.dart';

import '../repositories/test_support.dart';

/// 日程页（FR-16 / FR-17）端到端测试：月历标记、选日、当日安排、
/// 点击卡片复用首页编辑控件、勾选落库、翻月与「今」按钮。
void main() {
  late TestStore store;
  late DateTime today;

  setUp(() async {
    store = await TestStore.create(noIsolate: true);
    today = DateUtil.today();
  });

  tearDown(() async => store.dispose());

  DateTime dayOfCurrentMonth(int day) =>
      DateTime(today.year, today.month, day);


  /// 日程页 = 月历 + 当日列表，内容较长；默认 800x600 测试视口会让当日卡片
  /// 落到悬浮导航栏下方 / 视口外（懒加载不构建、点击被导航栏拦截）。
  /// 统一用高屏跑 Widget 测试。
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
        overrides: <Override>[dbHelperProvider.overrideWithValue(store.db)],
        child: getRootWidget(),
      ),
    );
    await settle(tester);
  }

  Future<void> gotoSchedule(WidgetTester tester) async {
    await tester.tap(find.text('日程').last);
    await settle(tester);
  }

  testWidgets('月历渲染当月网格与周序号，有任务的日期带标记', (tester) async {
    useTallScreen(tester);
    await store.tasks.insert(Todo(title: '今天的事', remindDate: today));
    await pumpApp(tester);
    await gotoSchedule(tester);

    // 头部：年月 + ISO 周序号
    expect(find.text('${today.year}年${today.month}月'), findsOneWidget);
    expect(find.text('第 ${DateUtil.isoWeek(today)} 周'), findsOneWidget);
    // 周日开头的星期行
    expect(find.text('日'), findsOneWidget);
    expect(find.text('六'), findsOneWidget);
    // 当月 1 号与最后一天都在网格里
    expect(find.text('1'), findsOneWidget);
    expect(find.text('${DateUtil.lastDayOfMonth(today).day}'), findsOneWidget);
    // 当日安排列出今天的任务
    expect(find.text('今天的事'), findsOneWidget);
    expect(find.text('当日安排'), findsOneWidget);
  });

  testWidgets('点日期切换当日安排；点卡片进入编辑页（复用首页编辑控件）', (tester) async {
    useTallScreen(tester);
    final fifth = dayOfCurrentMonth(5);
    await store.tasks.insert(
      Todo(title: '五号的事', remindDate: fifth, remindTime: '09:00'),
    );
    await store.tasks.insert(Todo(title: '今天的事', remindDate: today));
    await pumpApp(tester);
    await gotoSchedule(tester);

    // 初始选中今天
    expect(find.text('今天的事'), findsOneWidget);
    expect(find.text('五号的事'), findsNothing);

    await tester.tap(find.text('5'));
    await settle(tester);
    expect(find.text('五号的事'), findsOneWidget);
    expect(find.text('今天的事'), findsNothing);
    expect(find.textContaining('· 1 项'), findsOneWidget);
    // 无提醒时间显示「全天」，有时间显示时间
    expect(find.text('09:00'), findsOneWidget);

    // 点卡片主体 → 复用待办编辑页
    await tester.tap(find.text('五号的事'));
    await settle(tester);
    expect(find.text('编辑待办'), findsOneWidget);
    expect(
      find.textContaining('${fifth.month}月${fifth.day}日'),
      findsWidgets,
    );

    await tester.pageBack();
    await settle(tester);

    // 勾选完成 → 写库 + 标记与计数刷新
    await tester.tap(find.byIcon(CupertinoIcons.circle));
    await settle(tester);
    final tasks = await store.tasks.queryByDate(fifth);
    expect(tasks.single.isCompleted, isTrue);
    expect(tasks.single.completedAt, isNotNull);
    expect(find.text('100%'), findsNothing); // 日程页不展示进度卡
  });

  testWidgets('日程页「+」预填选中日期；空日期显示引导并可添加', (tester) async {
    useTallScreen(tester);
    await pumpApp(tester);
    await gotoSchedule(tester);

    final seventh = dayOfCurrentMonth(7);
    await tester.tap(find.text('7'));
    await settle(tester);
    expect(find.textContaining('还没有安排'), findsOneWidget);

    await tester.tap(find.text('添加待办'));
    await settle(tester);
    expect(find.text('新建待办'), findsOneWidget);
    // 提醒日期已预填为选中日
    expect(
      find.textContaining('${seventh.month}月${seventh.day}日'),
      findsWidgets,
    );

    await tester.enterText(find.byType(CupertinoTextField).first, '七号新增');
    await tester.tap(find.text('保存'));
    await settle(tester);

    // 保存后回到日程页，落在 7 号
    final saved = await store.tasks.queryByDate(seventh);
    expect(saved.single.title, '七号新增');
    expect(find.text('七号新增'), findsOneWidget);
  });

  testWidgets('翻月与「今」按钮：非当月显示「今天」chip', (tester) async {
    useTallScreen(tester);
    await store.tasks.insert(Todo(title: '今天的事', remindDate: today));
    await pumpApp(tester);
    await gotoSchedule(tester);

    final nextMonth = DateUtil.addMonthsCalendar(today, 1);
    await tester.tap(
      find.descendant(
        of: find.byType(ScheduleCalendar),
        matching: find.byIcon(CupertinoIcons.chevron_right),
      ),
    );
    await settle(tester);
    expect(find.text('${nextMonth.year}年${nextMonth.month}月'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget, reason: '非当月时头部出现「今天」chip');
    // 翻月只改月历，不改选中日：当日安排仍是今天的内容
    expect(find.text('今天的事'), findsOneWidget);

    // 「今」悬浮按钮回到今天
    await tester.tap(find.text('今'));
    await settle(tester);
    expect(find.text('${today.year}年${today.month}月'), findsOneWidget);
    expect(find.text('今天的事'), findsOneWidget);
  });

  testWidgets('「当日安排」可折叠，折叠后不渲染卡片', (tester) async {
    useTallScreen(tester);
    await store.tasks.insert(Todo(title: '今天的事', remindDate: today));
    await pumpApp(tester);
    await gotoSchedule(tester);

    expect(find.text('今天的事'), findsOneWidget);
    await tester.tap(find.text('当日安排'));
    await settle(tester);
    expect(find.text('今天的事'), findsNothing);
    await tester.tap(find.text('当日安排'));
    await settle(tester);
    expect(find.text('今天的事'), findsOneWidget);
  });

  testWidgets('左滑日程卡片复用待办删除流程（二次确认 + 撤销）', (tester) async {
    useTallScreen(tester);
    await store.tasks.insert(Todo(title: '要删的', remindDate: today));
    await pumpApp(tester);
    await gotoSchedule(tester);

    await tester.drag(find.text('要删的'), const Offset(-200, 0));
    await settle(tester);
    await tester.tap(find.text('删除'));
    await settle(tester);
    expect(find.text('删除待办'), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
    await settle(tester);
    expect(await store.tasks.queryAll(), isEmpty);

    await tester.tap(find.text('撤销'));
    await settle(tester);
    expect((await store.tasks.queryAll()).single.title, '要删的');
  });
}
