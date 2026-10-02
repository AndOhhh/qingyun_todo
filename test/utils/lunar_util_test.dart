import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/utils/lunar_util.dart';

/// 农历 / 节日 / 节气 / 法定假日封装的准确性抽验。
///
/// 基准数据来源：参考图（2026-09 月历：9/3 抗战胜利、9/7 白露、9/10 教师节、
/// 9/25 中秋节、9/30 烈士纪念日、9/4 = 农历七月廿三）+ 国务院 2026 年放假安排
/// （中秋 9/25-27、国庆 10/1-7 休、10/10 班）+ 闰月常识（2025 闰六月、2023 闰二月）。
void main() {
  group('农历日期', () {
    test('2026-09-04 = 农历七月廿三（参考图基准）', () {
      final info = LunarUtil.info(DateTime(2026, 9, 4));
      expect(info.subLabel, '廿三');
      expect(info.lunarFull, '农历七月廿三');
      expect(info.isFestival, isFalse);
      expect(info.cornerTag, isNull);
    });

    test('初一显示月名；闰月带「闰」字', () {
      expect(LunarUtil.info(DateTime(2025, 7, 25)).lunarFull, '农历闰六月初一');
      expect(LunarUtil.info(DateTime(2025, 7, 25)).subLabel, '闰六月');
      expect(LunarUtil.info(DateTime(2023, 3, 22)).lunarFull, '农历闰二月初一');
      expect(LunarUtil.info(DateTime(2026, 9, 11)).subLabel, '八月');
    });

    test('2026 中秋 = 9/25 且为农历八月十五', () {
      final info = LunarUtil.info(DateTime(2026, 9, 25));
      expect(info.subLabel, '中秋节');
      expect(info.lunarFull, '农历八月十五');
      expect(info.isFestival, isTrue);
    });
  });

  group('节日 / 节气 / 纪念日', () {
    test('公历节日：教师节 / 国庆节', () {
      expect(LunarUtil.info(DateTime(2026, 9, 10)).subLabel, '教师节');
      expect(LunarUtil.info(DateTime(2026, 10, 1)).subLabel, '国庆节');
    });

    test('节气只在交节当天显示：白露 9/7、秋分 9/23', () {
      expect(LunarUtil.info(DateTime(2026, 9, 7)).subLabel, '白露');
      expect(LunarUtil.info(DateTime(2026, 9, 23)).subLabel, '秋分');
      expect(LunarUtil.info(DateTime(2026, 9, 8)).subLabel, isNot('白露'));
    });

    test('本地补充的纪念日：抗战胜利 / 烈士 / 国家公祭', () {
      expect(LunarUtil.info(DateTime(2026, 9, 3)).subLabel, '抗战胜利纪念日');
      expect(LunarUtil.info(DateTime(2026, 9, 30)).subLabel, '烈士纪念日');
      expect(LunarUtil.info(DateTime(2026, 12, 13)).subLabel, '国家公祭日');
    });

    test('农历节日：2026 春节 = 2/17', () {
      expect(LunarUtil.info(DateTime(2026, 2, 17)).subLabel, '春节');
    });
  });

  group('法定假日与调休', () {
    test('2026 中秋 / 国庆为「休」，10/10 调休为「班」', () {
      expect(LunarUtil.info(DateTime(2026, 9, 25)).cornerTag, '休');
      expect(LunarUtil.info(DateTime(2026, 9, 25)).isRest, isTrue);
      expect(LunarUtil.info(DateTime(2026, 10, 1)).cornerTag, '休');
      expect(LunarUtil.info(DateTime(2026, 10, 10)).cornerTag, '班');
      expect(LunarUtil.info(DateTime(2026, 10, 10)).isWork, isTrue);
      // 普通工作日无角标
      expect(LunarUtil.info(DateTime(2026, 10, 9)).cornerTag, isNull);
    });

    test('尚未公布放假安排的年份优雅降级：有节日、无角标', () {
      final info = LunarUtil.info(DateTime(2027, 1, 1));
      expect(info.subLabel, '元旦');
      expect(info.cornerTag, isNull);
      expect(info.isRest, isFalse);
      expect(info.isWork, isFalse);
    });
  });
}
