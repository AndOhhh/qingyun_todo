import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/constants/routes.dart';
import 'package:qingyun_todo/pages/notification_guide/index.dart';
import 'package:qingyun_todo/routes/index.dart';
import 'package:qingyun_todo/services/device_brand.dart';
import 'package:qingyun_todo/stores/db_providers.dart';

import '../repositories/test_support.dart';

/// 「通知收不到？」引导页：自检结果 + 品牌步骤 + 快捷动作，以及路由接入。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const systemChannel = MethodChannel('qingyun_todo/system');
  late TestStore store;

  /// 原生通道必须 mock：未 mock 的通道在 widget 测试里 Future 永不完成，
  /// 会让页面停在 loading 态（pumpAndSettle 超时）。
  void mockSystemChannel(String? brand) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, (call) async {
      if (call.method == 'getBrand') return brand;
      return null;
    });
  }

  setUp(() async {
    DeviceBrand.resetCacheForTest();
    mockSystemChannel('OnePlus');
    store = await TestStore.create(noIsolate: true);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, null);
    await store.dispose();
  });

  /// 页面是 ListView，按钮在默认 800×600 视口之外不会被构建；
  /// 与 app_smoke_test 一致，统一用高屏跑 Widget 测试。
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpGuide(WidgetTester tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dbHelperProvider.overrideWithValue(store.db),
        ],
        child: const MaterialApp(home: NotificationGuidePage()),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  test('引导页已在命名路由中注册（入口不会 404）', () {
    final route = onGenerateRoute(
      const RouteSettings(name: RouteConstants.notificationGuide),
    );
    expect(route, isNotNull);
  });

  testWidgets('页面渲染：自检结果 + 品牌步骤 + 快捷动作', (tester) async {
    await pumpGuide(tester);

    expect(find.text('通知收不到？'), findsOneWidget);
    expect(find.text('自检结果'), findsOneWidget);
    // 厂商读取（原生通道）→ 品牌归类 → 步骤卡片标题，全链路生效
    expect(find.textContaining('ColorOS'), findsWidgets);
    expect(find.textContaining('设置步骤'), findsOneWidget);
    expect(find.text('打开系统通知设置'), findsOneWidget);
    expect(find.text('重新检测'), findsOneWidget);
  });

  testWidgets('测试环境无插件 → 明确告知通知能力不可用，而不是空白页', (tester) async {
    await pumpGuide(tester);

    expect(find.text('通知能力'), findsOneWidget);
    expect(find.textContaining('不可用'), findsWidgets);
  });

  testWidgets('未知厂商 → 回落原生 Android 步骤，不出现空白品牌名', (tester) async {
    DeviceBrand.resetCacheForTest();
    mockSystemChannel('Google');
    await pumpGuide(tester);

    expect(find.textContaining('Android 原生'), findsWidgets);
  });

  test('每个品牌都有可照抄的引导步骤，ColorOS 覆盖自启动 + 耗电管理 + 锁定卡片', () {
    for (final brand in DeviceBrand.values) {
      final steps = buildGuideSteps(brand);
      expect(steps, isNotEmpty, reason: '${brand.name} 缺少引导步骤');
      for (final step in steps) {
        expect(step.action.trim(), isNotEmpty, reason: brand.name);
        expect(step.path.trim(), isNotEmpty, reason: brand.name);
      }
    }
    final coloros = buildGuideSteps(DeviceBrand.coloros);
    expect(coloros.map((s) => s.action).join('|'), contains('自启动'));
    expect(coloros.map((s) => s.path).join('|'), contains('耗电管理'));
    expect(coloros.last.path, contains('锁定'));
  });
}
