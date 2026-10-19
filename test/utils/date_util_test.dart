import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 月历网格：首尾补齐相邻月日期的算法（N17）。
void main() {
  group('monthGridWithAdjacent', () {
    test('2026-10：周四开月 → 前导补 9 月 27~30，尾部正好收在 10-31', () {
      final cells = DateUtil.monthGridWithAdjacent(DateTime(2026, 10));
      expect(cells.length % 7, 0);
      expect(cells.first, DateTime(2026, 9, 27)); // 周日
      expect(cells.last, DateTime(2026, 10, 31)); // 周六
      expect(
        cells.where((d) => d.month == 9).map((d) => d.day),
        <int>[27, 28, 29, 30],
      );
      expect(cells.where((d) => d.month == 11), isEmpty);
    });

    test('2026-11：周日开月、30 天 → 前导 0 天，尾部补 12 月 1~5', () {
      final cells = DateUtil.monthGridWithAdjacent(DateTime(2026, 11));
      expect(cells.first, DateTime(2026, 11, 1));
      expect(cells.last, DateTime(2026, 12, 5));
      expect(
        cells.where((d) => d.month == 12).map((d) => d.day),
        <int>[1, 2, 3, 4, 5],
      );
    });

    test('相邻日期连续且唯一，覆盖整月每一天', () {
      final cells = DateUtil.monthGridWithAdjacent(DateTime(2026, 2));
      for (var i = 1; i < cells.length; i++) {
        expect(cells[i].difference(cells[i - 1]).inDays, 1);
      }
      expect(cells.length % 7, 0);
      // 2026 年 2 月 28 天，且 2/1 为周日 → 恰好 4 周，无补齐
      expect(cells.where((d) => d.month == 2).length, 28);
      expect(cells.first, DateTime(2026, 2, 1));
    });

    test('monthGrid 仍保留 null 占位（热力图等只用当月格子）', () {
      final withNulls = DateUtil.monthGrid(DateTime(2026, 10));
      final filled = DateUtil.monthGridWithAdjacent(DateTime(2026, 10));
      expect(withNulls.length, filled.length, reason: '格子总数一致，避免布局跳动');
      expect(withNulls.first, isNull);
      expect(withNulls.where((d) => d == null), isNotEmpty);
    });
  });
}
