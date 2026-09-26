import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/routes/index.dart';

/// 入口（修 R7：去掉无用的 `List<String> args` 参数）。
///
/// [ProviderScope] 是 Riverpod 的根容器（Q7 决策），必须包在 `MaterialApp` 外层；
/// 建库与周期实例生成在 `MainPage.initState` 中触发（docs/07 C4-2 触发时机①）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(child: getRootWidget()));
}
