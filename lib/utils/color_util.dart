import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/todo_priority.dart';

/// `Color` ↔ `#RRGGBB` 转换（DB 中颜色一律存 `#RRGGBB`，docs/02 §2）。
class ColorUtil {
  const ColorUtil._();

  /// 规范色板（docs/03 §4.1 实测色值），供色带选择器使用
  static const List<AccentSwatch> palette = <AccentSwatch>[
    AccentSwatch('#007AFF', '蓝'),
    AccentSwatch('#34C759', '绿'),
    AccentSwatch('#FF9500', '橙'),
    AccentSwatch('#FF3B30', '红'),
    AccentSwatch('#FFCC00', '黄'),
    AccentSwatch('#5856D6', '紫'),
    AccentSwatch('#AF52DE', '粉紫'),
    AccentSwatch('#8E8E93', '灰'),
  ];

  /// `#RRGGBB` → [Color]；null / 非法 → null
  static Color? fromHex(String? hex) {
    if (hex == null) return null;
    var s = hex.trim().replaceFirst('#', '');
    if (s.isEmpty) return null;
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(v);
  }

  /// [Color] → `#RRGGBB`（丢弃 alpha，DB 只存 6 位）
  static String toHex(Color color) {
    final argb = color.toARGB32() & 0xFFFFFF;
    return '#${argb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
  }

  /// 色带取值：`accent_color` 为空时按 [priority] 推导（docs/07 B6-5）
  static Color resolveAccent(String? hex, TodoPriority priority) =>
      fromHex(hex) ?? priority.color;
}

/// 色板中的一项
class AccentSwatch {
  final String hex;
  final String label;

  const AccentSwatch(this.hex, this.label);

  Color get color => ColorUtil.fromHex(hex) ?? Colors.transparent;
}
