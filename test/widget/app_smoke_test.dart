import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qingyun_todo/models/interval_type.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/pages/todo/index.dart';
import 'package:qingyun_todo/components/floating_add_button.dart';
import 'package:qingyun_todo/routes/index.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/utils/date_util.dart';

import '../repositories/test_support.dart';

/// 端到端冒烟测试：验证 `ProviderScope → Repository → SQLite → 页面` 全链路接通，
/// 页面上**没有任何 mock 数据**，看到的一切都来自内存库。
void main() {
  late TestStore store;

  setUp(() async {
    store = await TestStore.create(noIsolate: true);
  });

  tearDown(() async => store.dispose());

  /// 收敛动画；给一个短超时，避免某个组件无限动画时把测试挂死
  /// `IndexedStack` 会同时构建待办页与日程页，同一条待办会在两处渲染，
  /// 因此涉及卡片标题 / 勾选圈的断言必须限定到具体页面。
  Finder inTodo(Finder finder) =>
      find.descendant(of: find.byType(TodoView), matching: finder);


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
        overrides: <Override>[
          dbHelperProvider.overrideWithValue(store.db),
        ],
        child: getRootWidget(),
      ),
    );
    await settle(tester);
  }

  testWidgets('待办页按数据库数据渲染五组分组，且已完成默认折叠（Q10）', (tester) async {
    useTallScreen(tester);
    final today = DateUtil.today();
    await store.tasks.insert(Todo(title: '写周报', remindDate: today));
    await store.tasks.insert(
      Todo(title: '交房租', remindDate: DateUtil.addDays(today, -2)),
    );
    await store.tasks.insert(
      Todo(title: '看牙医', remindDate: DateUtil.addDays(today, 1)),
    );
    final doneId = await store.tasks.insert(
      Todo(title: '给爸妈打电话', remindDate: today),
    );
    await store.tasks.toggleComplete(doneId, to: true);

    await pumpApp(tester);

    // 分组标题：逾期 / 今天 / 明天 / 已完成（「后续」为空，不渲染）
    expect(find.text('逾期 · 1'), findsOneWidget);
    expect(find.text('今天 · 1'), findsOneWidget);
    expect(find.text('明天 · 1'), findsOneWidget);
    expect(find.text('已完成 · 1'), findsOneWidget);
    expect(find.text('后续 · 1'), findsNothing);

    expect(inTodo(find.text('写周报')), findsOneWidget);
    expect(inTodo(find.text('交房租')), findsOneWidget);
    // 已完成分组默认折叠 → 折叠内容不可见。
    // 注：IndexedStack 的非选中页被 Visibility(maintainState) 包裹且处于 offstage，
    // 默认 finder 会跳过，因此这里无需（也无法）断言日程页的内容。
    expect(inTodo(find.text('给爸妈打电话')), findsNothing);

    // 今日进度口径：今天 2 条（写周报 + 已完成），完成 1 条（修 R5）
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    // 鼓励文案必须是插值后的结果，不能出现字面量 \${...}
    expect(find.text('还差 1 项任务，加油'), findsOneWidget);
    expect(find.textContaining('\${total'), findsNothing);
  });

  testWidgets('点击圆圈勾选完成：写库 + 计数变化 + 移入已完成分组', (tester) async {
    useTallScreen(tester);
    await store.tasks.insert(Todo(title: '写周报', remindDate: DateUtil.today()));
    await pumpApp(tester);

    expect(find.text('已完成 · 1'), findsNothing);
    await tester.tap(inTodo(find.byIcon(CupertinoIcons.circle)));
    await settle(tester);

    // 数据库里真的写进去了（不是内存 setState）
    final all = await store.tasks.queryAll();
    expect(all.single.isCompleted, isTrue);
    expect(all.single.completedAt, isNotNull);

    expect(find.text('今天 · 1'), findsNothing);
    expect(find.text('已完成 · 1'), findsOneWidget);
    // 今日进度随之变成 1/1（100%）
    expect(find.text('1/1'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('今日任务全部完成 ✓'), findsOneWidget);
  });

  testWidgets('展开「已完成」分组后可见已完成条目', (tester) async {
    useTallScreen(tester);
    final id = await store.tasks.insert(
      Todo(title: '给爸妈打电话', remindDate: DateUtil.today()),
    );
    await store.tasks.toggleComplete(id, to: true);
    await pumpApp(tester);

    expect(inTodo(find.text('给爸妈打电话')), findsNothing);
    await tester.tap(find.text('已完成 · 1'));
    await settle(tester);
    expect(find.text('给爸妈打电话'), findsOneWidget);
  });

  testWidgets('空库显示空态引导，没有残留 mock 数据', (tester) async {
    useTallScreen(tester);
    await pumpApp(tester);
    expect(find.text('全部搞定！'), findsOneWidget);
    // 旧 mock 里的 6 条数据必须彻底消失
    expect(find.text('计算机证书考试'), findsNothing);
    expect(find.text('晨跑 5 公里'), findsNothing);
    expect(find.text('阅读《设计的法则》'), findsNothing);
    expect(find.text('整理周报'), findsNothing);
    expect(find.text('学 Flutter 动画'), findsNothing);
    expect(find.text('给爸妈打电话'), findsNothing);
    // 子任务标签已按 Q2 移除
    expect(find.text('7/12'), findsNothing);
  });

  testWidgets('周期页渲染数据库中的周期卡片与实例进度', (tester) async {
    useTallScreen(tester);
    await store.periodics.insert(
      Periodic(
        name: '隔天喝饮品计划',
        startDate: DateUtil.today(),
        intervalValue: 2,
      ),
      items: <PeriodicItem>[
        PeriodicItem(dayOffset: 0, title: '喝牛奶', remindTime: '09:00'),
        PeriodicItem(dayOffset: 1, title: '喝豆浆', remindTime: '09:00'),
      ],
    );

    await pumpApp(tester);
    // 切到「周期」Tab
    await tester.tap(find.text('周期'));
    await settle(tester);

    expect(find.text('隔天喝饮品计划'), findsOneWidget);
    expect(find.textContaining('每 2 天'), findsOneWidget);
    expect(find.text('第 1 轮 0/2'), findsOneWidget);
    expect(find.textContaining('下次：今天 09:00 · 喝牛奶'), findsOneWidget);
  });

  testWidgets('启动时自动生成周期实例，并出现在待办页（FR-13 / D5）', (tester) async {
    useTallScreen(tester);
    await store.periodics.insert(
      Periodic(
        name: '每天喝水',
        startDate: DateUtil.today(),
        intervalType: IntervalType.day,
      ),
      items: <PeriodicItem>[
        PeriodicItem(dayOffset: 0, title: '喝水 2000ml', remindTime: '08:00'),
      ],
    );
    // 先清空启动前可能已生成的实例，验证「App 启动触发」这条路径
    final db = await store.db.database;
    await db.delete('tasks');

    await pumpApp(tester);

    // 每天一轮 → 今天 / 明天 / 后续 都会各生成一条同名实例
    expect(find.text('喝水 2000ml'), findsWidgets);
    expect(find.text('周期·每天喝水'), findsWidgets);
    expect(find.text('今天 · 1'), findsOneWidget);
    expect(find.text('明天 · 1'), findsOneWidget);
    final all = await store.tasks.queryAll();
    expect(all, isNotEmpty);
    expect(all.every((t) => t.isPeriodic), isTrue);
  });

  testWidgets('新增待办闭环：+ → 表单 → 保存 → 落库并出现在列表（FR-02）', (tester) async {
    useTallScreen(tester);
    await pumpApp(tester);

    await tester.tap(find.byType(FloatingAddButton));
    await settle(tester);
    expect(find.text('新建待办'), findsOneWidget);

    // 空标题不允许保存（B2-4）
    await tester.tap(find.text('保存'));
    await settle(tester);
    expect(find.text('请填写标题'), findsOneWidget);
    expect(await store.tasks.queryAll(), isEmpty);

    await tester.enterText(
      find.byType(CupertinoTextField).first,
      '买牛奶',
    );
    await tester.tap(find.text('保存'));
    await settle(tester);

    // 已返回列表，并且数据库里真的写进去了
    expect(inTodo(find.text('买牛奶')), findsOneWidget);
    final all = await store.tasks.queryAll();
    expect(all, hasLength(1));
    expect(all.single.title, '买牛奶');
    expect(all.single.remindDate, DateUtil.today());
    expect(all.single.sourceType, TaskSourceType.regular);
  });

  testWidgets('左滑露出红色垃圾桶 → 二次确认 → 硬删除 → 5 秒内可撤销（Q5 / B3）', (tester) async {
    useTallScreen(tester);
    await store.tasks.insert(
      Todo(title: '要删的待办', remindDate: DateUtil.today()),
    );
    await pumpApp(tester);

    // 左滑：露出动作按钮，但不会滑走即删
    await tester.drag(inTodo(find.text('要删的待办')), const Offset(-200, 0));
    await settle(tester);
    expect(find.text('删除'), findsOneWidget);
    expect(await store.tasks.queryAll(), hasLength(1), reason: '仅滑动不应删除');

    await tester.tap(find.text('删除'));
    await settle(tester);
    // 二次确认弹窗：文案必须与「标记完成」区分
    expect(find.text('删除待办'), findsOneWidget);
    expect(find.textContaining('永久移除'), findsOneWidget);

    await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
    await settle(tester);

    // 物理删除：记录与统计分母同时消失
    expect(await store.tasks.queryAll(), isEmpty);
    expect(inTodo(find.text('要删的待办')), findsNothing);

    // SnackBar 撤销（B3-2）：按原 id / 原字段恢复
    expect(find.text('撤销'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await settle(tester);
    final restored = await store.tasks.queryAll();
    expect(restored, hasLength(1));
    expect(restored.single.title, '要删的待办');
    expect(inTodo(find.text('要删的待办')), findsOneWidget);
  });

  testWidgets('新建周期闭环：预设「每 2 天」→ 保存 → 详情页按天分组（FR-11 / C1~C3）', (tester) async {
    useTallScreen(tester);
    await pumpApp(tester);
    await tester.tap(find.text('周期'));
    await settle(tester);
    expect(find.text('还没有周期'), findsOneWidget);

    await tester.tap(find.text('新建周期'));
    await settle(tester);
    expect(find.text('周期规则'), findsOneWidget);
    expect(find.text('未来 3 轮预览'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField).first, '隔天喝饮品');
    await tester.tap(find.text('每 2 天'));
    await settle(tester);
    await tester.tap(find.text('保存'));
    await settle(tester);

    // 保存后替换路由进入周期详情页：按「第 N 天」分组，上限 = 轮长度 2 天
    expect(find.text('第 1 天'), findsOneWidget);
    expect(find.text('第 2 天'), findsOneWidget);
    expect(find.text('第 3 天'), findsNothing);
    expect(find.textContaining('当前无可生成事项'), findsOneWidget);

    final list = await store.periodics.queryAll();
    expect(list, hasLength(1));
    expect(list.single.name, '隔天喝饮品');
    expect(list.single.intervalType, IntervalType.day);
    expect(list.single.intervalValue, 2);
    expect(list.single.intervalLabel, '每 2 天');
  });

  testWidgets('跨模块闭环（M5 / D4）：加周期项 → 生成实例 → 待办页勾选完成 → 轮次计数 +1', (tester) async {
    useTallScreen(tester);
    final id = await store.periodics.insert(
      Periodic(name: '每天喝水', startDate: DateUtil.today()),
    );
    await pumpApp(tester);

    // 切到周期 Tab
    await tester.tap(find.text('周期').last);
    await settle(tester);
    expect(find.text('每天喝水'), findsOneWidget);
    expect(find.text('尚未生成待办'), findsOneWidget);

    // 进详情页 → 第 1 天添加事项
    await tester.tap(find.text('每天喝水'));
    await settle(tester);
    expect(find.text('第 1 天'), findsOneWidget);
    await tester.tap(find.text('添加'));
    await settle(tester);
    expect(find.text('新增事项'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField).first, '喝水 2000ml');
    await tester.tap(find.text('保存'));
    await settle(tester);

    // 回到详情页：模板项已保存（「第 1 天」分组 + 「近期已生成」区都会出现该标题），
    // 且实例已经落库
    expect(find.text('喝水 2000ml'), findsWidgets);
    expect(find.text('近期已生成'), findsOneWidget);
    final generated = await store.tasks.queryAll();
    expect(generated, isNotEmpty);
    expect(generated.every((t) => t.periodicId == id), isTrue);

    // 退回周期列表 → 卡片显示本轮进度
    await tester.pageBack();
    await settle(tester);
    expect(find.text('第 1 轮 0/1'), findsOneWidget);

    // 切回待办 Tab：周期实例出现在列表中，带「周期·xxx」标签（D1 / D5）
    await tester.tap(find.text('待办').last);
    await settle(tester);
    expect(find.text('喝水 2000ml'), findsWidgets);
    expect(find.text('周期·每天喝水'), findsWidgets);

    // 勾选完成 → 本轮完结 → completed_count +1（FR-15 / TC-08）
    await tester.tap(find.byIcon(CupertinoIcons.circle).first);
    await settle(tester);
    final periodic = (await store.periodics.findById(id))!;
    expect(periodic.completedCount, 1);
  });

  testWidgets('新增入口统一为右下角浮动按钮：三个页面均生效，导航栏不再有 +', (tester) async {
    await pumpApp(tester);

    // 导航栏右上角的 add_circled 已移除
    expect(find.byIcon(CupertinoIcons.add_circled), findsNothing);

    // 待办页：FAB → 新建待办
    expect(find.byType(FloatingAddButton), findsOneWidget);
    await tester.tap(find.byType(FloatingAddButton));
    await settle(tester);
    expect(find.text('新建待办'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    // 周期页：FAB → 新建周期
    await tester.tap(find.text('周期').last);
    await settle(tester);
    await tester.tap(find.byType(FloatingAddButton));
    await settle(tester);
    expect(find.text('新建周期'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    // 日程页：FAB 与「今」按钮共存，FAB 打开新建待办（预填选中日期）
    await tester.tap(find.text('日程').last);
    await settle(tester);
    expect(find.text('今'), findsOneWidget);
    expect(find.byType(FloatingAddButton), findsOneWidget);
    await tester.tap(find.byType(FloatingAddButton));
    await settle(tester);
    expect(find.text('新建待办'), findsOneWidget);
  });
}
