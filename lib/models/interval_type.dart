/// 周期单位（`periodic_configs.interval_type`）。
///
/// DB 存**大写枚举名**（docs/02 §2）：`DAY` / `WEEK` / `MONTH` / `YEAR`。
enum IntervalType {
  day('DAY', '天'),
  week('WEEK', '周'),
  month('MONTH', '个月'),
  year('YEAR', '年');

  /// DB 中存储的值
  final String dbName;

  /// 量词，用于拼「每 N 个月」这类文案
  final String unit;

  const IntervalType(this.dbName, this.unit);

  static IntervalType fromDbName(String? name) => IntervalType.values.firstWhere(
        (e) => e.dbName == name,
        orElse: () => IntervalType.day,
      );
}
