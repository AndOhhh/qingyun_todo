/// 命名路由常量（修 R2：原类名 `RouteContants` 拼写错误）。
///
/// 带参路由统一用 query 传递，如 `/todo/edit?id=3`（docs/07 B2-2）。
class RouteConstants {
  const RouteConstants._();

  /// 根页面（底部 4 Tab）
  static const String mainPath = '/';

  /// 待办新增 / 编辑：`?id=` 为空表示新增
  static const String todoEdit = '/todo/edit';

  /// 周期新增 / 编辑：`?id=` 为空表示新增
  static const String periodicEdit = '/periodic/edit';

  /// 周期详情（周期项管理）：`?id=`
  static const String periodicDetail = '/periodic/detail';

  /// 周期项新增 / 编辑：`?id=` 编辑，`?periodicId=&dayOffset=` 新增
  static const String periodicItemEdit = '/periodic/item/edit';

  static String _withId(String path, int? id) =>
      id == null ? path : '$path?id=$id';

  static String todoEditPath({int? id}) => _withId(todoEdit, id);

  static String periodicEditPath({int? id}) => _withId(periodicEdit, id);

  static String periodicDetailPath(int id) => _withId(periodicDetail, id);

  static String periodicItemEditPath({int? id, int? periodicId, int dayOffset = 0}) {
    if (id != null) return _withId(periodicItemEdit, id);
    return '$periodicItemEdit?periodicId=$periodicId&dayOffset=$dayOffset';
  }
}
