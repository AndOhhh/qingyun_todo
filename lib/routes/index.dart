import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/constants/routes.dart';
import 'package:qingyun_todo/pages/main/index.dart';
import 'package:qingyun_todo/pages/period/detail/index.dart';
import 'package:qingyun_todo/pages/period/edit/index.dart';
import 'package:qingyun_todo/pages/period/item_edit/index.dart';
import 'package:qingyun_todo/pages/todo/edit/index.dart';

/// 应用根 Widget（`ProviderScope` 在 `main.dart` 中包裹）
Widget getRootWidget() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '青云待办',
    initialRoute: RouteConstants.mainPath,
    onGenerateRoute: onGenerateRoute,
  );
}

/// 命名路由解析：统一在此把 query 参数转成强类型入参
Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final uri = Uri.parse(settings.name ?? RouteConstants.mainPath);
  final query = uri.queryParameters;
  int? idOf(String key) => int.tryParse(query[key] ?? '');

  Widget? page;
  switch (uri.path) {
    case RouteConstants.mainPath:
      page = const MainPage();
    case RouteConstants.todoEdit:
      page = TodoEditPage(taskId: idOf('id'));
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
    default:
      page = null;
  }

  if (page == null) return null;
  return CupertinoPageRoute<dynamic>(
    builder: (context) => page!,
    settings: settings,
  );
}
