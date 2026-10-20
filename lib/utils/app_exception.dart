/// 业务校验异常：由 Repository 抛出、store / UI 层转换为可展示文案。
///
/// Repository **不吞异常**（docs/04 §3.2）：数据库错误原样上抛
/// `DatabaseException`，业务规则错误抛本类。
class ValidationException implements Exception {
  /// 面向用户的中文提示
  final String message;

  /// 触发校验失败的对象描述（如越界的周期项标题）
  final List<String> details;

  const ValidationException(this.message, {this.details = const <String>[]});

  /// 多行文案：主提示 + 明细清单
  String get fullMessage =>
      details.isEmpty ? message : '$message\n${details.join('\n')}';

  @override
  String toString() => 'ValidationException: $fullMessage';
}
