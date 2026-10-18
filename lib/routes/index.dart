import 'package:flutter/cupertino.dart';
import 'package:qingyun_todo/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:qingyun_todo/constants/routes.dart';
import 'package:qingyun_todo/pages/main/index.dart';
import 'package:qingyun_todo/pages/notification_guide/index.dart';
import 'package:qingyun_todo/pages/period/detail/index.dart';
import 'package:qingyun_todo/pages/period/edit/index.dart';
import 'package:qingyun_todo/pages/period/item_edit/index.dart';
import 'package:qingyun_todo/pages/todo/edit/index.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 全局导航 key：供通知点击回调等「脱离 Widget 上下文」的场景跳转路由
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 应用根 Widget（`ProviderScope` 在 `main.dart` 中包裹）
Widget getRootWidget() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '青云待办',
    navigatorKey: rootNavigatorKey,
    initialRoute: RouteConstants.mainPath,
    onGenerateRoute: onGenerateRoute,
    // 中文日期选择器：CupertinoDatePicker 的月份（10月）/ 星期文案取自
    // CupertinoLocalizations，不注册代理时会落到框架内置的默认英文（Oct / Sun…）。
    // 应用文案本身全为中文，这里直接固定 zh，不跟随系统语言。
    locale: const Locale('zh'),
    supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  );
}

/// 命名路由解析：统一在此把 query 参数转成强类型入参
/// 绑定「点击通知 → 打开对应待办编辑页」（在 ProviderScope 就绪后调用）
void bindNotificationNavigation() {
  NotificationService.onOpenTask = (taskId) {
    rootNavigatorKey.currentState?.pushNamed(
      RouteConstants.todoEditPath(id: taskId),
    );
  };
}

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final uri = Uri.parse(settings.name ?? RouteConstants.mainPath);
  final query = uri.queryParameters;
  int? idOf(String key) => int.tryParse(query[key] ?? '');

  Widget? page;
  switch (uri.path) {
    case RouteConstants.mainPath:
      page = const MainPage();
    case RouteConstants.todoEdit:
      final dateRaw = query['date'];
      page = TodoEditPage(
        taskId: idOf('id'),
        initialDate: (dateRaw == null || dateRaw.isEmpty)
            ? null
            : DateUtil.parseDate(dateRaw),
      );
    case RouteConstants.periodicEdit:
      page = PeriodicEditPage(periodicId: idOf('id'));
    case RouteConstants.periodicDetail:
      final id = idOf('id');
      page = id == null ? null : PeriodicDetailPage(periodicId: id);
    case RouteConstants.periodicItemEdit:
      page = PeriodicItemEditPage(
        itemId: idOf('id'),
        periodicId: idOf('periodicId'),
        initialDayOffset: idOf('dayOffset') ?? 0,
      );
    case RouteConstants.notificationGuide:
      page = const NotificationGuidePage();
    default:
      page = null;
  }

  if (page == null) return null;
  return CupertinoPageRoute<dynamic>(
    builder: (context) => page!,
    settings: settings,
  );
}
