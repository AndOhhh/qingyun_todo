import 'package:tyme/tyme.dart';

import 'package:qingyun_todo/utils/date_util.dart';

/// 某一天的农历 / 节日 / 节气 / 法定假日信息（日程页月历小字与「班/休」角标）。
class DayLunarInfo {
  /// 日期下方小字，优先级：
  /// 公历节日 > 农历节日 > 节气当天 > 纪念日 > 农历月名（初一）> 农历日名
  final String subLabel;

  /// 小字是否属于「节日 / 节气 / 纪念日」（UI 上加重显示）
  final bool isFestival;

  /// 法定假日角标：`休` / `班`；非调休日或该年数据缺失时为 null
  final String? cornerTag;

  /// 是否法定休假日
  final bool isRest;

  /// 是否调休上班日
  final bool isWork;

  /// 完整农历文案：`农历八月廿三`（当日安排头部用）
  final String lunarFull;

  const DayLunarInfo({
    required this.subLabel,
    required this.isFestival,
    required this.lunarFull,
    this.cornerTag,
    this.isRest = false,
    this.isWork = false,
  });
}

/// 农历 / 节日 / 节气 / 法定假日的统一封装，基于 `tyme` 包（选型见 docs/07 §J）。
///
/// - 农历与闰月、节气、公历 / 农历节日均由 tyme 计算；
/// - 法定假日与调休（`班` / `休`）来自 tyme 内置数据，**覆盖到 2026-10-10**；
///   国务院尚未公布年份（如 2027）返回 null，UI 不显示角标，属预期降级；
/// - tyme 未收录的 3 个纪念日由 [kMemorialDays] 本地补充（固定不变，无维护成本）。
class LunarUtil {
  const LunarUtil._();

  /// tyme 未收录的纪念日（公历固定日期）
  static const Map<String, String> kMemorialDays = <String, String>{
    '09-03': '抗战胜利纪念日',
    '09-30': '烈士纪念日',
    '12-13': '国家公祭日',
  };

  /// 结果缓存：月历一次渲染要算 42 个格子，避免重复计算
  static final Map<String, DayLunarInfo> _cache = <String, DayLunarInfo>{};

  static DayLunarInfo info(DateTime date) {
    final key = DateUtil.formatDate(date);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length > 4000) _cache.clear();

    final solar = SolarDay.fromYmd(date.year, date.month, date.day);
    final lunarDay = solar.getLunarDay();
    final lunarMonth = lunarDay.getLunarMonth();
    final dayName = lunarDay.getName();

    // 节气：仅「交节当天」显示节气名（如 白露 / 秋分）
    String? jieqi;
    final termDay = solar.getTermDay();
    if (termDay.getDayIndex() == 0) {
      jieqi = termDay.getSolarTerm().getName();
    }

    final solarFestival = solar.getFestival()?.getName();
    final lunarFestival = lunarDay.getFestival()?.getName();
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final memorial = kMemorialDays['$mm-$dd'];

    final isFestival =
        solarFestival != null || lunarFestival != null || jieqi != null || memorial != null;
    final subLabel = solarFestival ??
        lunarFestival ??
        jieqi ??
        memorial ??
        (dayName == '初一' ? lunarMonth.getName() : dayName);

    final holiday = solar.getLegalHoliday();
    final info = DayLunarInfo(
      subLabel: subLabel,
      isFestival: isFestival,
      lunarFull: '农历${lunarMonth.getName()}$dayName',
      cornerTag: holiday == null ? null : (holiday.isWork() ? '班' : '休'),
      isRest: holiday != null && !holiday.isWork(),
      isWork: holiday != null && holiday.isWork(),
    );
    _cache[key] = info;
    return info;
  }
}
