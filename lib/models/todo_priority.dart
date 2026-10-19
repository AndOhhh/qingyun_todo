import 'package:flutter/material.dart';

/// 待办优先级（`tasks.priority` / `periodic_items.priority`）。
///
/// DB 存**小写枚举名**（docs/02 §2）：`none` / `low` / `medium` / `high`。
/// 色值取自 docs/03 §4.1 实测规范色，按「灰 → 蓝 → 橙 → 红」的强度递进排列
/// （N19：无与低的配色互换，避免「无优先级」用主色蓝显得比「低」更醒目）。
enum TodoPriority {
  none('none', '无', Color(0xFF8E8E93)),
  low('low', '低', Color(0xFF007AFF)),
  medium('medium', '中', Color(0xFFFF9500)),
  high('high', '高', Color(0xFFFF3B30));

  /// DB 中存储的值
  final String dbName;

  /// UI 文案
  final String label;

  /// 规范色：既用于优先级色点，也用于 `accent_color` 为空时的色带兜底
  final Color color;

  const TodoPriority(this.dbName, this.label, this.color);

  static TodoPriority fromDbName(String? name) => TodoPriority.values.firstWhere(
        (e) => e.dbName == name,
        orElse: () => TodoPriority.none,
      );
}
