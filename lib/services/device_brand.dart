import 'package:flutter/foundation.dart';

import 'package:qingyun_todo/services/system_settings.dart';

/// 设备品牌：决定「通知收不到？」引导页展示哪一套系统设置路径。
///
/// 为什么需要它：系统权限自检（通知开关 / 精确闹钟）看起来一切正常，提醒却到点不响，
/// 根因在厂商自有的电源策略层——实测 ColorOS 会把未授权应用的精确闹钟**整体推迟数天**
/// （AlarmManager dump 里 `adjustment=+2d23h`），从多任务划掉后还会强停应用并删除
/// 已排期闹钟。这一层没有可读取的公共 API，也没有可绕过的代码手段，只能按品牌引导
/// 用户到「自启动 / 耗电管理」把应用加白。
enum DeviceBrand {
  coloros('OPPO / 一加 / realme（ColorOS 系）'),
  miui('小米 / Redmi / POCO（HyperOS / MIUI）'),
  harmony('华为 / 荣耀（HarmonyOS / EMUI）'),
  vivo('vivo / iQOO（OriginOS / FuntouchOS）'),
  samsung('三星（One UI）'),
  meizu('魅族（Flyme）'),
  stock('Android 原生 / 其它品牌'),
  ios('iOS');

  const DeviceBrand(this.displayName);

  /// 引导页展示用的品牌名称
  final String displayName;

  /// 按 Android `Build.MANUFACTURER` 归类（**纯函数**，单测覆盖）。
  ///
  /// 厂商字段大小写与写法不稳定（`OnePlus` / `OPPO` / `Redmi` / `HONOR`），
  /// 统一小写后做包含匹配；未命中归入 [stock]。
  static DeviceBrand fromManufacturer(String? manufacturer) {
    final m = (manufacturer ?? '').trim().toLowerCase();
    if (m.isEmpty) return DeviceBrand.stock;
    if (m.contains('oppo') || m.contains('oneplus') || m.contains('realme')) {
      return DeviceBrand.coloros;
    }
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return DeviceBrand.miui;
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return DeviceBrand.harmony;
    }
    if (m.contains('vivo') || m.contains('iqoo')) return DeviceBrand.vivo;
    if (m.contains('samsung')) return DeviceBrand.samsung;
    if (m.contains('meizu')) return DeviceBrand.meizu;
    return DeviceBrand.stock;
  }

  static DeviceBrand? _cached;

  /// 当前设备品牌；进程内只探测一次并缓存（运行期不会变）。
  static Future<DeviceBrand> detect() async {
    final cached = _cached;
    if (cached != null) return cached;

    DeviceBrand result;
    if (kIsWeb) {
      result = DeviceBrand.stock;
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          result = DeviceBrand.ios;
        case TargetPlatform.android:
          result = fromManufacturer(await SystemSettings.getBrand());
        default:
          // macOS / Windows / Linux 桌面端：无厂商 ROM 限制
          result = DeviceBrand.stock;
      }
    }
    return _cached = result;
  }

  /// 仅供测试：清空探测缓存
  @visibleForTesting
  static void resetCacheForTest() => _cached = null;
}
