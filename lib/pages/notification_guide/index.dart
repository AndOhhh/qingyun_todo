import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/form_card.dart';
import 'package:qingyun_todo/components/wide_button.dart';
import 'package:qingyun_todo/services/device_brand.dart';
import 'package:qingyun_todo/services/notification_service.dart';
import 'package:qingyun_todo/services/system_settings.dart';
import 'package:qingyun_todo/stores/db_providers.dart';

/// 引导页单条步骤：`action` = 要做什么，`path` = 在系统设置的哪一层做。
class GuideStep {
  final String action;
  final String path;

  const GuideStep(this.action, this.path);
}

/// 按品牌给出系统设置路径（**纯函数**，单测覆盖「每个品牌都非空」）。
///
/// 文案口径：优先保证「路径可照抄」——国产 ROM 的设置层级各版本略有差异，
/// 因此每步只写到关键开关名，用户即使层级不同也能按名称搜到。
List<GuideStep> buildGuideSteps(DeviceBrand brand) => switch (brand) {
      DeviceBrand.coloros => const <GuideStep>[
          GuideStep('允许自启动', '设置 → 应用 → 应用管理 → 青云待办 → 打开「允许自启动」'),
          GuideStep('允许完全后台行为', '同页「耗电管理」→ 选择「允许完全后台行为」'),
          GuideStep('锁定后台卡片', '多任务界面下拉卡片（或点卡片右上 ⋮）→ 锁定，避免划掉时被系统强停'),
        ],
      DeviceBrand.miui => const <GuideStep>[
          GuideStep('打开自启动', '设置 → 应用设置 → 应用管理 → 青云待办 → 打开「自启动」'),
          GuideStep('省电策略改为「无限制」', '同页 → 省电策略 → 无限制'),
          GuideStep('锁定后台卡片', '多任务界面下拉卡片 → 锁定'),
        ],
      DeviceBrand.harmony => const <GuideStep>[
          GuideStep('关闭「自动管理」', '设置 → 应用 → 应用启动管理 → 青云待办 → 关闭「自动管理」'),
          GuideStep('三项全部手动允许', '弹出的面板中勾选「自启动」「关联启动」「后台活动」'),
          GuideStep('锁定后台卡片', '多任务界面下拉卡片 → 锁定'),
        ],
      DeviceBrand.vivo => const <GuideStep>[
          GuideStep('允许后台高耗电', '设置 → 电池 → 后台耗电管理 → 青云待办 → 允许后台高耗电'),
          GuideStep('允许自启动', 'i 管家 → 应用管理 → 自启动管理 → 青云待办 → 打开'),
          GuideStep('锁定后台卡片', '多任务界面下拉卡片 → 锁定'),
        ],
      DeviceBrand.samsung => const <GuideStep>[
          GuideStep('电池改为「不受限制」', '设置 → 应用 → 青云待办 → 电池 → 不受限制'),
          GuideStep('移出「自动关闭的应用」', '设置 → 电池 → 后台使用限制 → 从列表中移除青云待办'),
        ],
      DeviceBrand.meizu => const <GuideStep>[
          GuideStep('允许后台运行', '手机管家 → 权限管理 → 后台管理 → 青云待办 → 允许后台运行'),
          GuideStep('允许自启动', '手机管家 → 权限管理 → 自启动管理 → 青云待办 → 打开'),
          GuideStep('锁定后台卡片', '多任务界面下拉卡片 → 锁定'),
        ],
      DeviceBrand.stock => const <GuideStep>[
          GuideStep('关闭电池优化', '设置 → 应用 → 青云待办 → 电池 → 不受限制（关闭电池优化）'),
          GuideStep('允许后台运行', '若系统提供「自启动 / 后台限制」开关，一并允许'),
        ],
      DeviceBrand.ios => const <GuideStep>[
          GuideStep('允许通知', '设置 → 通知 → 青云待办 → 打开「允许通知」'),
          GuideStep('打开横幅与声音', '同页打开「横幅」「声音」，建议一并开启「时效性通知」'),
          GuideStep('检查专注模式', '专注模式（勿扰）会静默提醒，请把青云待办加入允许列表'),
        ],
    };

/// 「通知收不到？」诊断 + 厂商权限引导页（N11 后续）。
///
/// 定位：系统权限自检全部正常、到点却收不到提醒时的自救入口。页面先给客观自检结果，
/// 再按设备品牌给出可照抄的设置路径，并提供跳转系统设置 / 重新检测的快捷动作。
class NotificationGuidePage extends ConsumerStatefulWidget {
  const NotificationGuidePage({super.key});

  @override
  ConsumerState<NotificationGuidePage> createState() =>
      _NotificationGuidePageState();
}

class _NotificationGuidePageState extends ConsumerState<NotificationGuidePage> {
  static const Color _green = Color(0xFF34C759);
  static const Color _red = Color(0xFFFF3B30);
  static const Color _orange = Color(0xFFFF9500);
  static const Color _grey = Color(0xFF8E8E93);

  NotificationHealth? _health;
  DeviceBrand _brand = DeviceBrand.stock;
  bool _loading = true;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _refresh(reconcile: true);
  }

  /// 重新自检（可选先重排通知，让「待发提醒」条数是当前值）
  Future<void> _refresh({bool reconcile = false}) async {
    final service = ref.read(notificationServiceProvider);
    if (reconcile) await service.reconcile();
    final health = await service.checkHealth();
    final brand = await DeviceBrand.detect();
    if (!mounted) return;
    setState(() {
      _health = health;
      _brand = brand;
      _loading = false;
    });
  }

  Future<void> _requestExactAlarms() async {
    await ref.read(notificationServiceProvider).requestExactAlarms();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: const CupertinoNavigationBar(
        middle: Text(
          '通知收不到？',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator(radius: 13))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: <Widget>[
                const InfoBanner(
                  text: '系统里通知开关都开着，到点却没反应？多半是厂商的「自启动 / '
                      '耗电管理」把系统闹钟截住了——实测 ColorOS 会把后台应用的提醒'
                      '整体推迟数天。按下面的步骤给应用加白即可。',
                ),
                const SizedBox(height: 18),
                _statusCard(),
                const SizedBox(height: 22),
                _stepsCard(),
                const SizedBox(height: 22),
                ..._actions(),
                const SizedBox(height: 16),
                const Text(
                  '说明：应用在前台时，到点提醒由 App 自身的兜底巡检保证；'
                  '退到后台或被划掉后，提醒完全依赖系统闹钟，受厂商电源策略影响，'
                  '可能延迟数十秒到数分钟。',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: _grey,
                  ),
                ),
              ],
            ),
    );
  }

  /// 客观自检结果（对应 NotificationService.checkHealth）
  Widget _statusCard() {
    final health = _health;
    if (health == null || !health.available) {
      final detail = health?.lastError;
      return FormCard(
        header: '自检结果',
        footer: '通知能力不可用：插件或时区初始化失败，提醒功能已整体关闭。',
        children: <Widget>[
          _StatusRow(
            icon: CupertinoIcons.xmark_circle_fill,
            color: _red,
            label: '通知能力',
            value: detail == null || detail.isEmpty ? '不可用' : '不可用（$detail）',
          ),
        ],
      );
    }

    final notifications = health.notificationsEnabled;
    final exact = health.exactAlarmsAllowed;
    return FormCard(
      header: '自检结果',
      footer: '若以上全部正常却仍收不到提醒，问题就在下面的厂商限制。',
      children: <Widget>[
        _StatusRow(
          icon: notifications
              ? CupertinoIcons.checkmark_circle_fill
              : CupertinoIcons.xmark_circle_fill,
          color: notifications ? _green : _red,
          label: '系统通知',
          value: notifications ? '已开启' : '未开启',
        ),
        if (_isAndroid)
          _StatusRow(
            icon: exact
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.exclamationmark_circle_fill,
            color: exact ? _green : _orange,
            label: '精确闹钟',
            value: exact ? '已允许' : '未允许（提醒可能延迟）',
          ),
        _StatusRow(
          icon: CupertinoIcons.time,
          color: _grey,
          label: '待发提醒',
          value: '${health.pendingCount} 条',
        ),
        if (health.lastError != null)
          _StatusRow(
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            color: _orange,
            label: '最近错误',
            value: health.lastError!,
          ),
      ],
    );
  }

  /// 品牌设置步骤
  Widget _stepsCard() {
    final steps = buildGuideSteps(_brand);
    return FormCard(
      header: '${_brand.displayName} · 设置步骤',
      children: <Widget>[
        for (var i = 0; i < steps.length; i++)
          _StepRow(index: i + 1, step: steps[i]),
      ],
    );
  }

  List<Widget> _actions() {
    final health = _health;
    final widgets = <Widget>[
      WideButton(
        label: '打开系统通知设置',
        icon: CupertinoIcons.bell,
        color: const Color(0xFF007AFF),
        onTap: () => SystemSettings.openNotificationSettings(),
      ),
    ];
    if (_isAndroid) {
      widgets
        ..add(const SizedBox(height: 10))
        ..add(
          WideButton(
            label: '打开应用信息（自启动 / 耗电管理）',
            icon: CupertinoIcons.settings,
            color: const Color(0xFF5856D6),
            onTap: () => SystemSettings.openAppSettings(),
          ),
        );
    }
    if (_isAndroid && health != null && !health.exactAlarmsAllowed) {
      widgets
        ..add(const SizedBox(height: 10))
        ..add(
          WideButton(
            label: '授予「精确闹钟」权限',
            icon: CupertinoIcons.alarm,
            color: _orange,
            onTap: () => _requestExactAlarms(),
          ),
        );
    }
    widgets
      ..add(const SizedBox(height: 10))
      ..add(
        WideButton(
          label: '重新检测',
          icon: CupertinoIcons.refresh,
          color: _green,
          onTap: () => _refresh(reconcile: true),
        ),
      );
    return widgets;
  }
}

/// 自检结果行：状态图标 + 标签 + 右侧结论
class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatusRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, height: 1.35, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 步骤行：序号圆标 + 动作 + 路径
class _StepRow extends StatelessWidget {
  final int index;
  final GuideStep step;

  const _StepRow({required this.index, required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF007AFF),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  step.action,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.path,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
