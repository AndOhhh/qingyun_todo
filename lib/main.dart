import 'package:flutter/material.dart';
import 'package:qingyun_todo/RouteUtils.dart';

void main(List<String> args) {
  runApp(MainPage());
}

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: RouteUtils.homePage,
      routes: RouteUtils.routes,
      // onGenerateRoute: (settings) => RouteUtils.onGenerateRoute(settings),
      // onUnknownRoute: (settings) => RouteUtils.onUnknownRoute(settings),
    );
  }
}
