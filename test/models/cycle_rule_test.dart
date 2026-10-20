import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/models/cycle_rule.dart';
import 'package:qingyun_todo/models/interval_type.dart';
import 'package:qingyun_todo/utils/date_util.dart';

void main() {
  group('CycleRule · cycleStart', () {
    test('DAY/N：按天数等差推进（TC-01 的推算基础）', () {
      final rule = CycleRule(
        type: IntervalType.day,
        value: 2,
        startDate: DateTime(2026, 9, 25),
      );
      expect(DateUtil.formatDate(rule.cycleStart(0)), '2026-09-25');
      expect(DateUtil.formatDate(rule.cycleStart(1)), '2026-09-27');
      expect(DateUtil.formatDate(rule.cycleStart(2)), '2026-09-29');
      expect(rule.cycleLength(0), 2);
      expect(rule.cycleLength(5), 2);
    });

    test('WEEK/N：按 7 天倍数推进', () {
      final rule = CycleRule(
        type: IntervalType.week,
        value: 2,
        startDate: DateTime(2026, 9, 25),
      );
      expect(DateUtil.formatDate(rule.cycleStart(1)), '2026-10-09');
      expect(rule.cycleLength(0), 14);
      expect(rule.minCycleLength, 14);
    });

    test('MONTH/1：日号锚定，不是 +30 天（TC-02）', () {
      final rule = CycleRule(
        type: IntervalType.month,
        value: 1,
        startDate: DateTime(2026, 9, 1),
      );
      expect(DateUtil.formatDate(rule.cycleStart(1)), '2026-10-01');
      expect(DateUtil.formatDate(rule.cycleStart(2)), '2026-11-01');
      expect(DateUtil.formatDate(rule.cycleStart(3)), '2026-12-01');
    });

    test('MONTH：月末收敛，1/31 的下一轮是 2/28 而不是 3/3（TC-03）', () {
      final rule = CycleRule(
        type: IntervalType.month,
        value: 1,
        startDate: DateTime(2026, 1, 31),
      );
      expect(DateUtil.formatDate(rule.cycleStart(1)), '2026-02-28');
      // 收敛后再下一轮仍锚定原始日号 31，而不是从 28 继续漂
      expect(DateUtil.formatDate(rule.cycleStart(2)), '2026-03-31');
    });

    test('YEAR：闰日 2/29 的下一轮是 2/28', () {
      final rule = CycleRule(
        type: IntervalType.year,
        value: 1,
        startDate: DateTime(2024, 2, 29),
      );
      expect(DateUtil.formatDate(rule.cycleStart(1)), '2025-02-28');
      expect(DateUtil.formatDate(rule.cycleStart(4)), '2028-02-29');
    });
  });

  group('CycleRule · cycleLength / minCycleLength', () {
    test('MONTH 随月份变化 28~31，minCycleLength 恒取 28', () {
      final rule = CycleRule(
        type: IntervalType.month,
        value: 1,
        startDate: DateTime(2026, 1, 1),
      );
      expect(rule.cycleLength(0), 31); // 1 月
      expect(rule.cycleLength(1), 28); // 2 月
      expect(rule.cycleLength(3), 30); // 4 月
      expect(rule.minCycleLength, 28);
    });

    test('YEAR 随闰年变化 365/366，minCycleLength 恒取 365', () {
      final rule = CycleRule(
        type: IntervalType.year,
        value: 1,
        startDate: DateTime(2024, 1, 1),
      );
      expect(rule.cycleLength(0), 366); // 2024 闰年
      expect(rule.cycleLength(1), 365); // 2025 平年
      expect(rule.minCycleLength, 365);
    });
  });

  group('CycleRule · label', () {
    test('周期文案符合 docs/07 C1', () {
      String label(IntervalType t, int v) =>
          CycleRule(type: t, value: v, startDate: DateTime(2026)).label;
      expect(label(IntervalType.day, 1), '每天');
      expect(label(IntervalType.day, 3), '每 3 天');
      expect(label(IntervalType.week, 1), '每周');
      expect(label(IntervalType.week, 2), '每 2 周');
      expect(label(IntervalType.month, 1), '每月');
      expect(label(IntervalType.month, 3), '每 3 个月');
      expect(label(IntervalType.year, 1), '每年');
      expect(label(IntervalType.year, 2), '每 2 年');
    });
  });

  group('CycleRule · 轮次定位', () {
    test('firstCycleIndexOnOrAfter / cycleIndexOf 在月末收敛下仍准确', () {
      final rule = CycleRule(
        type: IntervalType.month,
        value: 1,
        startDate: DateTime(2026, 1, 31),
      );
      expect(rule.firstCycleIndexOnOrAfter(DateTime(2026, 1, 1)), 0);
      expect(rule.firstCycleIndexOnOrAfter(DateTime(2026, 2, 28)), 1);
      expect(rule.firstCycleIndexOnOrAfter(DateTime(2026, 3, 1)), 2);
      // 月末收敛的副作用：第 2 轮被拉长（02-28 ~ 03-30），故 03-15 属于第 2 轮（index 1）
      expect(rule.cycleIndexOf(DateTime(2026, 3, 15)), 1);
      expect(rule.cycleIndexOf(DateTime(2026, 3, 31)), 2);
      expect(rule.cycleIndexOf(DateTime(2025, 12, 31)), -1);
    });

    test('DAY/N 的轮次定位', () {
      final rule = CycleRule(
        type: IntervalType.day,
        value: 2,
        startDate: DateTime(2026, 9, 25),
      );
      expect(rule.cycleIndexOf(DateTime(2026, 9, 26)), 0);
      expect(rule.cycleIndexOf(DateTime(2026, 9, 27)), 1);
      expect(rule.firstCycleIndexOnOrAfter(DateTime(2026, 9, 26)), 1);
    });
  });

  group('CycleRule · 预览与跳过', () {
    test('preview 返回连续 3 轮及其起止日', () {
      final rule = CycleRule(
        type: IntervalType.day,
        value: 2,
        startDate: DateTime(2026, 9, 25),
      );
      final previews = rule.preview(cycles: 3, from: DateTime(2026, 9, 25));
      expect(previews.map((p) => p.cycleIndex), <int>[0, 1, 2]);
      expect(DateUtil.formatDate(previews[0].endDate), '2026-09-26');
      expect(previews[1].length, 2);
    });

    test('datesForDayOffset：每月周期的 day_offset=28 在 2 月被跳过（TC-04）', () {
      final rule = CycleRule(
        type: IntervalType.month,
        value: 1,
        startDate: DateTime(2026, 12, 1),
      );
      // 2026-12 / 2027-01 / 2027-02：2 月只有 28 天，day_offset=28 不存在
      final dates = rule.datesForDayOffset(28, cycles: 3, from: DateTime(2026, 12, 1));
      expect(
        dates.map(DateUtil.formatDate).toList(),
        <String>['2026-12-29', '2027-01-29'],
      );
      // day_offset=0 三轮都在
      expect(
        rule
            .datesForDayOffset(0, cycles: 3, from: DateTime(2026, 12, 1))
            .map(DateUtil.formatDate)
            .toList(),
        <String>['2026-12-01', '2027-01-01', '2027-02-01'],
      );
    });
  });

  group('DateUtil', () {
    test('formatDate / parseDate 往返一致', () {
      final d = DateTime(2026, 9, 5);
      expect(DateUtil.parseDate(DateUtil.formatDate(d)), d);
      expect(DateUtil.formatDate(d), '2026-09-05');
    });

    test('normalizeTime 容忍 HH:mm:ss 并拒绝非法值', () {
      expect(DateUtil.normalizeTime('09:30'), '09:30');
      expect(DateUtil.normalizeTime('09:30:00'), '09:30');
      expect(DateUtil.normalizeTime('24:00'), isNull);
      expect(DateUtil.normalizeTime(''), isNull);
      expect(DateUtil.normalizeTime(null), isNull);
    });

    test('dateLabel：今天/明天/昨天/N 天后/M-D', () {
      final today = DateUtil.today();
      expect(DateUtil.dateLabel(today), '今天');
      expect(DateUtil.dateLabel(DateUtil.addDays(today, 1)), '明天');
      expect(DateUtil.dateLabel(DateUtil.addDays(today, -1)), '昨天');
      expect(DateUtil.dateLabel(DateUtil.addDays(today, 3)), '3 天后');
      expect(
        DateUtil.dateLabel(DateUtil.addDays(today, 30)),
        '${DateUtil.addDays(today, 30).month}-${DateUtil.addDays(today, 30).day}',
      );
    });
  });
}
