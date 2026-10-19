import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/utils/color_util.dart';

/// 优先级配色（N19）：无与低的默认色互换，按「灰 → 蓝 → 橙 → 红」递进。
void main() {
  test('优先级规范色：无=灰、低=蓝、中=橙、高=红', () {
    expect(TodoPriority.none.color, const Color(0xFF8E8E93));
    expect(TodoPriority.low.color, const Color(0xFF007AFF));
    expect(TodoPriority.medium.color, const Color(0xFFFF9500));
    expect(TodoPriority.high.color, const Color(0xFFFF3B30));
  });

  test('色带取值：accent_color 为空时按优先级兜底，显式色优先', () {
    for (final priority in TodoPriority.values) {
      expect(
        ColorUtil.resolveAccent(null, priority),
        priority.color,
        reason: '${priority.label}工作时按优先级取色',
      );
    }
    expect(
      ColorUtil.resolveAccent('#34C759', TodoPriority.high),
      const Color(0xFF34C759),
      reason: '显式色带优先于优先级',
    );
  });
}
