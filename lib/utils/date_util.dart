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

  /// 月份键 `YYYY-MM`（日程页按月查询标记用）
  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}';

  /// 当月第一天（date-only）
  static DateTime firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  /// 当月最后一天（date-only）
  static DateTime lastDayOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

  /// 加减月份（仅取月份粒度，用于日历翻页）
  static DateTime addMonthsCalendar(DateTime d, int months) =>
      DateTime(d.year, d.month + months, 1);

  /// ISO 8601 周序号（参考图头部的「第 N 周」）：第 1 周包含当年第一个周四
  static int isoWeek(DateTime d) {
    final date = dateOnly(d);
    final thursday = addDays(date, 4 - date.weekday);
    final jan1 = DateTime(thursday.year, 1, 1);
    return (thursday.difference(jan1).inDays / 7).floor() + 1;
  }

  /// 月历网格（**周日开头**，与参考图一致）：
  /// 返回若干完整周，月首/月末之外的位置为 null（热力图等只需当月格子）。
  static List<DateTime?> monthGrid(DateTime month) {
    final first = firstDayOfMonth(month);
    final last = lastDayOfMonth(month);
    final leading = first.weekday % 7; // 周日=0 … 周六=6
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = first; !d.isAfter(last); d = addDays(d, 1)) d,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  /// 月历网格（**含相邻月日期**，周日开头）：首尾用上/下月的真实日期补齐。
  ///
  /// 与 [monthGrid] 的差别：不返回 null，而是给出真实的相邻月日期，
  /// 供日程页把「本月 1 号之前 / 月末之后」的格子灰色展示，并支持点击跳月。
  static List<DateTime> monthGridWithAdjacent(DateTime month) {
    final first = firstDayOfMonth(month);
    final last = lastDayOfMonth(month);
    final leading = first.weekday % 7; // 周日=0 … 周六=6
    final cells = <DateTime>[
      for (var i = leading; i > 0; i--) addDays(first, -i),
      for (var d = first; !d.isAfter(last); d = addDays(d, 1)) d,
    ];
    var next = addDays(last, 1);
    while (cells.length % 7 != 0) {
      cells.add(next);
      next = addDays(next, 1);
    }
    return cells;
  }

  /// 选中日所在周（周日开头，**跨月补全**，参考图折叠态用）
  static List<DateTime> weekOf(DateTime day) {
    final d = dateOnly(day);
    final start = addDays(d, -(d.weekday % 7));
    return List<DateTime>.generate(7, (i) => addDays(start, i));
  }

  /// 中文日期：`2026年9月25日`
  static String humanDate(DateTime d) => '${d.year}年${d.month}月${d.day}日';
}
