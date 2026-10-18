import 'package:qingyun_todo/utils/date_util.dart';

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

  /// 通知诊断与厂商权限引导（「通知收不到？」）
  static const String notificationGuide = '/notification/guide';

  static String _withId(String path, int? id) =>
      id == null ? path : '$path?id=$id';

  /// 待办编辑页路径；[date] 用于从日程页新增时预填提醒日期
  static String todoEditPath({int? id, DateTime? date}) {
    var path = _withId(todoEdit, id);
    if (date != null) {
      path += '${id == null ? '?' : '&'}date=${DateUtil.formatDate(date)}';
    }
    return path;
  }

  static String periodicEditPath({int? id}) => _withId(periodicEdit, id);

  static String periodicDetailPath(int id) => _withId(periodicDetail, id);

  static String periodicItemEditPath({int? id, int? periodicId, int dayOffset = 0}) {
    if (id != null) return _withId(periodicItemEdit, id);
    return '$periodicItemEdit?periodicId=$periodicId&dayOffset=$dayOffset';
  }
}
