import 'package:flutter/material.dart';
import 'package:qingyun_todo/contants/routes.dart';
import 'package:qingyun_todo/pages/main/index.dart';

Widget getRootWidget() {
  return MaterialApp(
    initialRoute: RouteContants.mainPath,
    routes: getRootRoutes(),
  );
}

Map<String, Widget Function(BuildContext)> getRootRoutes() {
  return {
    RouteContants.mainPath : (context) => MainPage(),
  };
}