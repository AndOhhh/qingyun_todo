import 'package:flutter/material.dart';
import 'package:qingyun_todo/constants/routes.dart';
import 'package:qingyun_todo/pages/main/index.dart';

Widget getRootWidget() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    initialRoute: RouteContants.mainPath,
    routes: getRootRoutes(),
  );
}

Map<String, Widget Function(BuildContext)> getRootRoutes() {
  return {RouteContants.mainPath: (context) => MainPage()};
}
