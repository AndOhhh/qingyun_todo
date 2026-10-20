import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/pages/notification_guide/index.dart';
import 'package:qingyun_todo/services/device_brand.dart';

/// 设备品牌归类 + 引导页文案的口径测试（N11 后续：国产 ROM 后台限制自救入口）。
void main() {
  group('DeviceBrand.fromManufacturer 按厂商字段归类', () {
    test('ColorOS 系（OPPO / 一加 / realme）', () {
      expect(DeviceBrand.fromManufacturer('OPPO'), DeviceBrand.coloros);
      expect(DeviceBrand.fromManufacturer('OnePlus'), DeviceBrand.coloros);
      expect(DeviceBrand.fromManufacturer('realme'), DeviceBrand.coloros);
    });

    test('小米系（Xiaomi / Redmi / POCO）', () {
      expect(DeviceBrand.fromManufacturer('Xiaomi'), DeviceBrand.miui);
      expect(DeviceBrand.fromManufacturer('Redmi'), DeviceBrand.miui);
      expect(DeviceBrand.fromManufacturer('POCO'), DeviceBrand.miui);
    });

    test('华为 / 荣耀', () {
      expect(DeviceBrand.fromManufacturer('HUAWEI'), DeviceBrand.harmony);
      expect(DeviceBrand.fromManufacturer('HONOR'), DeviceBrand.harmony);
    });

    test('vivo / 三星 / 魅族', () {
      expect(DeviceBrand.fromManufacturer('vivo'), DeviceBrand.vivo);
      expect(DeviceBrand.fromManufacturer('iQOO'), DeviceBrand.vivo);
      expect(DeviceBrand.fromManufacturer('samsung'), DeviceBrand.samsung);
      expect(DeviceBrand.fromManufacturer('Meizu'), DeviceBrand.meizu);
    });

    test('大小写与首尾空白容错', () {
      expect(DeviceBrand.fromManufacturer('  oneplus  '), DeviceBrand.coloros);
      expect(DeviceBrand.fromManufacturer('hOnOr'), DeviceBrand.harmony);
    });

    test('未知厂商 / 空值 → stock（原生 Android）', () {
      expect(DeviceBrand.fromManufacturer('Google'), DeviceBrand.stock);
      expect(DeviceBrand.fromManufacturer(null), DeviceBrand.stock);
      expect(DeviceBrand.fromManufacturer(''), DeviceBrand.stock);
      expect(DeviceBrand.fromManufacturer('   '), DeviceBrand.stock);
    });
  });

  test('每个品牌都有可照抄的引导步骤，且不出现空白条目', () {
    for (final brand in DeviceBrand.values) {
      final steps = buildGuideSteps(brand);
      expect(steps, isNotEmpty, reason: '${brand.name} 缺少引导步骤');
      for (final step in steps) {
        expect(step.action.trim(), isNotEmpty, reason: brand.name);
        expect(step.path.trim(), isNotEmpty, reason: brand.name);
      }
    }
  });
}
