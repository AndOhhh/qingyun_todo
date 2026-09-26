/// 日期与时间的格式化 / 解析工具。
///
/// 全局约定（docs/02 §2）：
/// - 日期 `YYYY-MM-DD`（本地时区，date-only）
/// - 时间 `HH:mm`（24 小时制）
/// - 时间戳 `YYYY-MM-DD HH:mm:ss`
///
/// ⚠️ MONTH / YEAR 的日历算术一律在 Dart 层做「月末收敛」，禁止使用 SQLite 的
/// `date(x, '+N month')` —— 它对月末溢出做的是**进位**而非收敛，实测
/// `date('2026-01-31','+1 month') = 2026-03-03`（docs/02 §7.1）。
class DateUtil {
  const DateUtil._();

  /// 今天（date-only，丢弃时分秒）
  static DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// 归一化为 date-only，避免 DateTime 携带时分秒导致跨天比较出错
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// `YYYY-MM-DD`
  static String formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  /// 解析 `YYYY-MM-DD`；格式非法时抛 [FormatException]（由上层转换为校验错误）
  static DateTime parseDate(String s) {
    final parts = s.split('-');
    if (parts.length != 3) {
      throw FormatException('非法日期格式，应为 YYYY-MM-DD：$s');
    }
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// `HH:mm`
  static String formatTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  /// 解析 `HH:mm`（也容忍 `HH:mm:ss`）；非法返回 null
  static String? normalizeTime(String? s) {
    if (s == null) return null;
    final v = s.trim();
    if (v.isEmpty) return null;
    final parts = v.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return '${_two(h)}:${_two(m)}';
  }

  /// `YYYY-MM-DD HH:mm:ss`
  static String formatTimestamp(DateTime d) =>
      '${formatDate(d)} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

  /// 解析时间戳；非法时回退为「当前时间」，避免读库崩溃
  static DateTime parseTimestamp(String s) {
    final parsed = DateTime.tryParse(s);
    return parsed?.toLocal() ?? DateTime.now();
  }

  /// 解析**可空**时间戳（模型 fromMap 用）
  static DateTime? parseTimestampOrNull(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  /// 某年某月的天数
  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// 加天数（用构造器而非 Duration，规避 DST 造成的日期漂移）
  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// 加月数，**日号锚定 + 月末收敛**：`2026-01-31 + 1 月 = 2026-02-28`
  static DateTime addMonths(DateTime d, int months) {
    final total = d.year * 12 + (d.month - 1) + months;
    final year = total ~/ 12;
    final month = total % 12 + 1;
    final day = d.day > daysInMonth(year, month) ? daysInMonth(year, month) : d.day;
    return DateTime(year, month, day);
  }

  /// 加年数，规则同 [addMonths]：`2024-02-29 + 1 年 = 2025-02-28`
  static DateTime addYears(DateTime d, int years) => addMonths(d, years * 12);

  /// from → to 的**完整月数**（不足一月不计），用于 MONTH/YEAR 轮次估算
  static int monthsBetween(DateTime from, DateTime to) {
    var months = (to.year - from.year) * 12 + (to.month - from.month);
    if (to.day < from.day) months -= 1;
    return months;
  }

  /// 相差天数（date-only 比较）
  static int daysBetween(DateTime from, DateTime to) =>
      dateOnly(to).difference(dateOnly(from)).inDays;

  /// 日期展示文案：今天 / 明天 / 昨天 / N 天后 / M-D（docs/01 §3.1 标签规则）
  static String dateLabel(DateTime d) {
    final diff = daysBetween(today(), dateOnly(d));
    if (diff == 0) return '今天';
    if (diff == 1) return '明天';
    if (diff == -1) return '昨天';
    if (diff > 1 && diff < 7) return '$diff 天后';
    return '${d.month}-${d.day}';
  }

  /// 星期文案：周一 … 周日
  static String weekdayLabel(DateTime d) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[(d.weekday - 1) % 7];
  }

  /// 中文日期：`2026年9月25日`
  static String humanDate(DateTime d) => '${d.year}年${d.month}月${d.day}日';
}
