import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/components/color_picker.dart';
import 'package:qingyun_todo/components/priority_picker.dart';
import 'package:qingyun_todo/models/todo_priority.dart';

/// 编辑页两个选择器的口径（N18）：优先级分段样式 + 色带去「跟随」选项。
void main() {
  Widget harness(Widget child) => MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      );

  testWidgets('优先级：四段齐全，点击回调对应优先级', (tester) async {
    TodoPriority? picked;
    await tester.pumpWidget(
      harness(
        PriorityPicker(
          value: TodoPriority.none,
          onChanged: (priority) => picked = priority,
        ),
      ),
    );

    for (final label in const <String>['无', '低', '中', '高']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('高'));
    expect(picked, TodoPriority.high);
    await tester.tap(find.text('中'));
    expect(picked, TodoPriority.medium);
  });

  testWidgets('色带：不再有「跟随」选项，默认高亮与优先级同色的色块', (tester) async {
    final handle = tester.ensureSemantics();
    String? picked;
    await tester.pumpWidget(
      harness(
        AccentColorPicker(
          value: null, // 跟随优先级（落库 NULL）
          priority: TodoPriority.high, // 高 = 红
          onChanged: (hex) => picked = hex,
        ),
      ),
    );

    expect(find.text('跟随'), findsNothing);
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
    expect(
      find.descendant(
        of: find.bySemanticsLabel('红'),
        matching: find.byIcon(CupertinoIcons.checkmark_alt),
      ),
      findsOneWidget,
      reason: '默认选中态应与优先级（高=红）同色',
    );

    // 任选一个色块即覆盖为自定义色
    await tester.tap(find.bySemanticsLabel('绿'));
    expect(picked, '#34C759');
    handle.dispose();
  });

  testWidgets('色带：显式选色后高亮该色，而不是优先级色', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      harness(
        AccentColorPicker(
          value: '#34C759',
          priority: TodoPriority.high,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
    expect(
      find.descendant(
        of: find.bySemanticsLabel('绿'),
        matching: find.byIcon(CupertinoIcons.checkmark_alt),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsLabel('红'),
        matching: find.byIcon(CupertinoIcons.checkmark_alt),
      ),
      findsNothing,
    );
    handle.dispose();
  });
}
