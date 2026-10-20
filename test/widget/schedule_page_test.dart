import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/components/floating_add_button.dart';
import 'package:qingyun_todo/pages/schedule/widgets/day_timeline.dart';
import 'package:qingyun_todo/pages/schedule/widgets/schedule_calendar.dart';
import 'package:qingyun_todo/pages/schedule/widgets/schedule_task_card.dart';
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

    // 标题栏：年月 + ISO 周序号（Text.rich，用 contains 断言）
    expect(
      find.textContaining('${today.year}年${today.month}月'),
      findsWidgets,
    );
    expect(
      find.textContaining('第 ${DateUtil.isoWeek(today)} 周'),
      findsWidgets,
    );
    // 周日开头的星期行
    expect(find.text('日'), findsOneWidget);
    expect(find.text('六'), findsOneWidget);
    // 当月 1 号与最后一天都在网格里（首尾可能同时出现相邻月的同日号，故用 findsWidgets）
    expect(find.text('1'), findsWidgets);
    expect(find.text('${DateUtil.lastDayOfMonth(today).day}'), findsWidgets);
    // 当日安排列出今天的任务
    expect(find.text('今天的事'), findsOneWidget);
    expect(find.text('当日安排'), findsOneWidget);
  });

  testWidgets('点日期切换当日安排；点卡片进入编辑页（复用首页编辑控件）', (tester) async {
    useTallScreen(tester);
    // 取一个与「今天」不同的日期（避免当天恰为 5 号时两条数据同天）
    final otherDayNumber = today.day <= 20 ? today.day + 3 : today.day - 3;
    final otherDay = dayOfCurrentMonth(otherDayNumber);
    await store.tasks.insert(
      Todo(title: '另一天的事', remindDate: otherDay, remindTime: '09:00'),
    );
    await store.tasks.insert(Todo(title: '今天的事', remindDate: today));
    await pumpApp(tester);
    await gotoSchedule(tester);

    // 初始选中今天
    expect(find.text('今天的事'), findsOneWidget);
    expect(find.text('另一天的事'), findsNothing);

    // 只点月历里的日期格子：当日时间轴里也有 "18"（0/6/12/18/24 小时刻度），
    // 直接用 find.text 会在部分日期（如 21 号 → 18 号）命中两个控件
    await tester.tap(
      find
          .descendant(
            of: find.byType(ScheduleCalendar),
            matching: find.text('$otherDayNumber'),
          )
          .first,
    );
    await settle(tester);
    expect(find.text('另一天的事'), findsOneWidget);
    expect(find.text('今天的事'), findsNothing);
    expect(find.textContaining('· 1 项'), findsOneWidget);
    // 无提醒时间显示「全天」，有时间显示时间
    expect(find.text('09:00'), findsOneWidget);

    // 点卡片主体 → 复用待办编辑页
    await tester.tap(find.text('另一天的事'));
    await settle(tester);
    expect(find.text('编辑待办'), findsOneWidget);
    expect(
      find.textContaining('${otherDay.month}月${otherDay.day}日'),
      findsWidgets,
    );

    await tester.pageBack();
    await settle(tester);

    // 勾选完成 → 写库 + 标记与计数刷新
    await tester.tap(find.byIcon(CupertinoIcons.circle));
    await settle(tester);
    final tasks = await store.tasks.queryByDate(otherDay);
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
    // 居中按钮已移除，引导文案指向右下角 FAB（且 FAB 预填选中日期）
    expect(find.text('添加待办'), findsNothing);
    expect(find.textContaining('点击右下角'), findsOneWidget);
    expect(
      find.textContaining('为 ${seventh.month}月${seventh.day}日 添加待办'),
      findsOneWidget,
    );

    await tester.tap(find.byType(FloatingAddButton));
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
    // 右上角箭头已取消：横滑月历翻月
    await tester.fling(find.byType(ScheduleCalendar), const Offset(-400, 0), 1200);
    await settle(tester);
    // 标题栏随翻月联动
    expect(
      find.textContaining('${nextMonth.year}年${nextMonth.month}月'),
      findsWidgets,
    );
    expect(
      find.textContaining('${today.year}年${today.month}月'),
      findsNothing,
    );
    // 翻月只改月历，不改选中日：当日安排仍是今天的内容
    expect(find.text('今天的事'), findsOneWidget);

    // 「今」悬浮按钮回到今天
    await tester.tap(find.text('今'));
    await settle(tester);
    expect(
      find.textContaining('${today.year}年${today.month}月'),
      findsWidgets,
    );
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

  testWidgets('2a 时间轴：带时间的任务画刻度点，全天任务单独标签', (tester) async {
    useTallScreen(tester);
    await store.tasks.insert(
      Todo(title: '早会', remindDate: today, remindTime: '09:30'),
    );
    await store.tasks.insert(
      Todo(title: '晚课', remindDate: today, remindTime: '20:00'),
    );
    await store.tasks.insert(Todo(title: '不限时阅读', remindDate: today));
    await pumpApp(tester);
    await gotoSchedule(tester);

    expect(find.byType(DayTimeline), findsOneWidget);
    // 小时刻度标签在时间轴内部（与月历日期数字区分）
    for (final hour in const <String>['0', '6', '12', '18', '24']) {
      expect(
        find.descendant(
          of: find.byType(DayTimeline),
          matching: find.text(hour),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('全天 1'), findsOneWidget);
  });

  testWidgets('3 单周折叠：折叠后只渲染选中日所在周（含跨月补全）', (tester) async {
    useTallScreen(tester);
    await store.tasks.insert(Todo(title: '今天的事', remindDate: today));
    await pumpApp(tester);
    await gotoSchedule(tester);

    // 找一个「同月但不在选中周」的日期
    final week = DateUtil.weekOf(today);
    final lastDay = DateUtil.lastDayOfMonth(today).day;
    var outsideDay = 0;
    for (var d = 1; d <= lastDay; d++) {
      final date = DateTime(today.year, today.month, d);
      if (!week.contains(date)) {
        outsideDay = d;
        break;
      }
    }
    expect(outsideDay, isNot(0), reason: '当月应存在不在选中周的日期');

    expect(find.text('$outsideDay'), findsOneWidget);
    // 折叠
    await tester.tap(find.byIcon(CupertinoIcons.chevron_up));
    await settle(tester);
    expect(find.text('$outsideDay'), findsNothing);
    // 跨月补全：选中周里属于上个月的日期仍会渲染（置灰）
    final crossMonth = week.where((d) => d.month != today.month).toList();
    for (final d in crossMonth) {
      expect(find.text('${d.day}'), findsOneWidget);
    }
    // 选中日与当日安排不受折叠影响
    expect(find.text('今天的事'), findsOneWidget);
    // 展开恢复
    await tester.tap(find.byIcon(CupertinoIcons.chevron_up));
    await settle(tester);
    expect(find.text('$outsideDay'), findsOneWidget);
  });

  testWidgets('4 角标条数：同一天 2 条时显示数字而非圆点', (tester) async {
    useTallScreen(tester);
    await store.tasks.insert(
      Todo(title: '甲', remindDate: today, remindTime: '08:00'),
    );
    await store.tasks.insert(
      Todo(title: '乙', remindDate: today, remindTime: '18:00'),
    );
    await store.tasks.insert(
      Todo(title: '丙', remindDate: DateUtil.addDays(today, 2)),
    );
    await pumpApp(tester);
    await gotoSchedule(tester);

    expect(
      find.byWidgetPredicate(
        (w) => w is DayMarkerBadge && w.count == 2,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is DayMarkerBadge && w.count == 1,
      ),
      findsOneWidget,
    );
  });

  testWidgets('5 已完成沉底：未完成在前，已完成排最后', (tester) async {
    useTallScreen(tester);
    final doneId = await store.tasks.insert(
      Todo(title: '已完成早事', remindDate: today, remindTime: '08:00'),
    );
    await store.tasks.insert(
      Todo(title: '未完成晚事', remindDate: today, remindTime: '09:00'),
    );
    await store.tasks.toggleComplete(doneId, to: true);
    await pumpApp(tester);
    await gotoSchedule(tester);

    final cards = tester
        .widgetList<ScheduleTaskCard>(find.byType(ScheduleTaskCard))
        .toList();
    expect(
      cards.map((c) => c.task.title).toList(),
      <String>['未完成晚事', '已完成早事'],
    );
  });

  testWidgets('9 当月概览：本月 N 项 / 已完成 M / 完成率', (tester) async {
    useTallScreen(tester);
    final doneId = await store.tasks.insert(
      Todo(title: '已完成', remindDate: today),
    );
    await store.tasks.insert(Todo(title: '今天', remindDate: today));
    await store.tasks.insert(
      Todo(
        title: '同月另一天',
        remindDate: dayOfCurrentMonth(
          today.day <= 20 ? today.day + 3 : today.day - 3,
        ),
      ),
    );
    await store.tasks.toggleComplete(doneId, to: true);
    await pumpApp(tester);
    await gotoSchedule(tester);

    expect(find.textContaining('本月 3 项'), findsOneWidget);
    expect(find.textContaining('已完成 1'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
  });

  testWidgets('9 当月概览：空月不渲染', (tester) async {
    useTallScreen(tester);
    await pumpApp(tester);
    await gotoSchedule(tester);
    expect(find.textContaining('本月'), findsNothing);
  });

  testWidgets('1 农历/节日/班休：月历小字与角标渲染正确', (tester) async {
    useTallScreen(tester);
    await pumpApp(tester);
    await gotoSchedule(tester);

    // 默认展示当月（10 月）：国庆节小字 + 10/10 的「班」角标
    expect(find.text('国庆节'), findsOneWidget);
    expect(find.text('班'), findsOneWidget);
    // 当日安排头部带农历文案
    expect(find.textContaining('农历'), findsWidgets);

    // 翻到上月（9 月）：中秋 / 白露 / 教师节 / 纪念日 + 「休」角标
    await tester.fling(find.byType(ScheduleCalendar), const Offset(400, 0), 1200);
    await settle(tester);
    expect(find.text('中秋节'), findsOneWidget);
    expect(find.text('白露'), findsOneWidget);
    expect(find.text('教师节'), findsOneWidget);
    expect(find.text('抗战胜利纪念日'), findsOneWidget);
    expect(find.text('休'), findsWidgets);
  });

  testWidgets('点标题弹出月份选择器：滚动月份轮并确定后标题与月历联动', (tester) async {
    await store.tasks.insert(Todo(title: '今天的事', remindDate: today));
    await pumpApp(tester);
    await gotoSchedule(tester);

    // 点标题（Text.rich 位于可点击区域内）；真机侧另有「选择月份」语义标签
    await tester.tap(find.textContaining('${today.year}年${today.month}月'));
    await settle(tester);
    expect(find.text('跳转月份'), findsOneWidget);
    expect(find.textContaining('回到本月'), findsOneWidget);

    // 月份滚轮上滑一格 → 下一个月
    await tester.drag(
      find.byType(CupertinoPicker).last,
      const Offset(0, -40),
    );
    await settle(tester);
    await tester.tap(find.text('确定'));
    await settle(tester);

    final next = DateUtil.addMonthsCalendar(today, 1);
    expect(
      find.textContaining('${next.year}年${next.month}月'),
      findsWidgets,
    );
    // 选中日落到跳转月的月首（当日头部 / 空态文案都会带上该日期）
    expect(
      find.textContaining('${next.month}月1日'),
      findsWidgets,
    );
  });

  testWidgets('月份选择器取消不改变当前月份', (tester) async {
    await pumpApp(tester);
    await gotoSchedule(tester);

    await tester.tap(find.textContaining('${today.year}年${today.month}月'));
    await settle(tester);
    await tester.drag(find.byType(CupertinoPicker).last, const Offset(0, -80));
    await settle(tester);
    await tester.tap(find.text('取消'));
    await settle(tester);

    expect(
      find.textContaining('${today.year}年${today.month}月'),
      findsWidgets,
    );
  });

  testWidgets('点击灰色相邻月日期 → 跳转到该月并选中该日（N17）', (tester) async {
    useTallScreen(tester);
    await pumpApp(tester);
    await gotoSchedule(tester);

    // 取当前展示月份的前导相邻月日期；若当月 1 号恰为周日则向后翻月（最多 3 次必命中）
    var month = DateTime(today.year, today.month);
    var leading = DateUtil.monthGridWithAdjacent(month).first;
    for (var i = 0; i < 3 && leading.month == month.month; i++) {
      await tester.fling(
        find.byType(ScheduleCalendar),
        const Offset(-300, 0),
        1200,
      );
      await settle(tester);
      month = DateUtil.addMonthsCalendar(month, 1);
      leading = DateUtil.monthGridWithAdjacent(month).first;
    }
    expect(leading.month, isNot(month.month), reason: '应存在前导相邻月日期');

    // 灰色格子排在网格最前，故取第一个同日号文本
    await tester.tap(find.text('${leading.day}').first);
    await settle(tester);

    final prevMonth = DateUtil.addMonthsCalendar(month, -1);
    // 标题切到相邻月
    expect(
      find.textContaining('${prevMonth.year}年${prevMonth.month}月'),
      findsWidgets,
    );
    // 当日安排标题已选中该日
    expect(
      find.textContaining('${leading.month}月${leading.day}日'),
      findsWidgets,
    );
  });
}
