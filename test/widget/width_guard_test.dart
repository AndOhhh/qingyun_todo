import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/components/width_guard.dart';

/// WidthGuard：预热帧（父级宽度为 0）跳过子树，规避分段控件的负宽度断言。
///
/// 背景：`CupertinoSlidingSegmentedControl` 在 `maxWidth = 0` 时按
/// `(maxWidth - 分隔线总宽) / 段数` 算段宽，得到负值并构造 tight 约束
/// （debug 下 `BoxConstraints has a negative minimum width`）。
void main() {
  Widget harness({required double width, required Widget child}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    );
  }

  Widget control() => CupertinoSlidingSegmentedControl<int>(
        groupValue: 0,
        onValueChanged: (_) {},
        children: const <int, Widget>{
          0: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('周')),
          1: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('月')),
        },
      );

  testWidgets('宽度为 0（引擎预热帧）→ 跳过子树，不抛负宽度断言', (tester) async {
    await tester.pumpWidget(
      harness(width: 0, child: WidthGuard(child: control())),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsNothing);
  });

  testWidgets('宽度正常 → 正常构建子树，行为与未包裹时一致', (tester) async {
    await tester.pumpWidget(
      harness(width: 320, child: WidthGuard(child: control())),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    expect(find.text('周'), findsOneWidget);
  });

  testWidgets('宽度从 0 恢复 → 下一帧补建子树（预热帧只影响一帧）', (tester) async {
    await tester.pumpWidget(
      harness(width: 0, child: WidthGuard(child: control())),
    );
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsNothing);

    await tester.pumpWidget(
      harness(width: 320, child: WidthGuard(child: control())),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
  });
}
