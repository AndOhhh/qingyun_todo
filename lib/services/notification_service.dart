import 'package:qingyun_todo/services/system_settings.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/repositories/task_repository.dart';

/// 本地提醒通知服务（FR-19，Android + iOS + macOS 开发态）。
///
/// 设计要点：
/// - **系统级排期**：用 `zonedSchedule` 把提醒交给 OS（AlarmManager /
///   UNCalendarNotificationTrigger），App 被杀后仍能到点通知；
/// - **幂等同步**（[reconcile]）：每次数据变化 / 启动 / 回前台时，
///   「取消全部排期 → 按当前数据重排」，因此改时间、改完成、删除都无需单独维护；
/// - **补发窗口**：重新打开 App 时，到期不超过 [kCatchUpWindow] 且从未通知过的
///   任务立即补发一条；更老的只静默标记，避免打开 App 被旧提醒轰炸；
/// - **防重复**：`tasks.is_notified` 在「排期成功」或「补发成功」时置 1；
/// - **降级**：时区 / 插件初始化失败（如测试环境、不支持的平台）时整体关闭，
///   不影响其它功能。
class NotificationService {
  NotificationService(this._tasks);

  final TaskRepository _tasks;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String kChannelId = 'todo_reminder';
  static const String kChannelName = '待办提醒';

  /// 补发窗口：到期后多久内重新打开 App 仍会补发通知
  static const Duration kCatchUpWindow = Duration(hours: 24);

  /// iOS / macOS 的待发通知上限：系统只保留最近 64 条，留 4 条余量（N24）
  static const int kIOSMaxScheduled = 60;

  bool _available = false;

  /// 通知能力是否可用（权限/平台/初始化任一失败则为 false）
  bool get isAvailable => _available;

  bool _busy = false;

  /// 点击通知 → 打开对应待办（由路由层注入，见 `routes/index.dart`）
  static void Function(int taskId)? onOpenTask;

  /// 冷启动（进程被杀后点通知）时的待打开待办 id，见 [takeLaunchTaskId]
  int? _launchTaskId;

  /// 取出并清空冷启动待打开的待办 id（由 `bootstrap` 消费，N24）
  int? takeLaunchTaskId() {
    final id = _launchTaskId;
    _launchTaskId = null;
    return id;
  }

  // ------------------------------------------------------------ 初始化

  Future<void> init() async {
    if (_available) return;
    try {
      // 时区数据库 + 设备时区：zonedSchedule 需要 TZDateTime
      tzdata.initializeTimeZones();
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (error) {
      debugPrint('[notify] 时区初始化失败，通知功能关闭：$error');
      return;
    }
    try {
      const settings = InitializationSettings(
        // 必须用纯白单色 drawable：Android 8+ 会把小图标当 alpha 蒙版着色，
        // 传 launcher mipmap 会在通知栏显示成白块（N24）。
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      );
      final ok = await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final id = int.tryParse(response.payload ?? '');
          if (id != null) onOpenTask?.call(id);
        },
      );
      if (ok != true) return;
      _available = true;
      // 冷启动补跳（N24）：进程被系统杀掉后点通知，插件不会回调
      // `onDidReceiveNotificationResponse`，必须主动读一次启动详情；
      // 读到后由 bootstrap / 路由层消费（takeLaunchTaskId）。
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) {
          _launchTaskId =
              int.tryParse(launch?.notificationResponse?.payload ?? '');
        }
      } catch (error) {
        debugPrint('[notify] 读取冷启动通知失败：$error');
      }
      await _requestPermissions();
    } catch (error) {
      // 测试环境 / 未注册插件的平台会走到这里
      debugPrint('[notify] 插件初始化失败，通知功能关闭：$error');
      _available = false;
    }
  }

  Future<void> _requestPermissions() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      // Android 13+ 通知权限；低版本为 no-op
      await android?.requestNotificationsPermission();
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
      final macos = _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>();
      await macos?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (error) {
      debugPrint('[notify] 权限请求失败（用户可稍后在系统设置中开启）：$error');
    }
  }

  // ------------------------------------------------------------ 同步

  /// 按当前数据库状态重排系统通知（幂等，可反复调用）。
  Future<void> reconcile() async {
    if (!_available || _busy) return;
    _busy = true;
    try {
      final tasks = await _tasks.queryRemindable();
      final plan = computePlan(dueTasks: tasks, now: DateTime.now());

      // 取消全部旧排期后重排：改时间 / 删除 / 完成都由此收敛，无需逐处维护
      await _plugin.cancelAll();
      // 逐条隔离失败：单条异常（如精确闹钟被拒）不能中断其余任务的排期
      // iOS/macOS 系统最多保留 64 条待发通知，超出的会被静默丢弃：
      // 这里只排最近 [kIOSMaxScheduled] 条（queryRemindable 已按时间升序）。
      for (final task in _cappedForPlatform(plan.toSchedule)) {
        try {
          await _schedule(task);
        } catch (error) {
          _lastError = '$error';
          debugPrint('[notify] 排期失败 id=${task.id}：$error');
        }
      }
      for (final task in plan.toFireNow) {
        try {
          await _showNow(task);
          await _tasks.markNotified(task.id!);
        } catch (error) {
          _lastError = '$error';
          debugPrint('[notify] 补发失败 id=${task.id}：$error');
        }
      }
      for (final id in plan.toMarkSilent) {
        await _tasks.markNotified(id);
      }
    } catch (error) {
      _lastError = '$error';
      debugPrint('[notify] 同步通知失败（下次触发时重试）：$error');
    } finally {
      _busy = false;
    }
  }

  String? _lastError;

  /// iOS / macOS 只排最近的 [kIOSMaxScheduled] 条（系统上限 64 条）；
  /// 其它平台不限制。[tasks] 需已按提醒时间升序（`queryRemindable` 保证）。
  static List<Todo> _cappedForPlatform(List<Todo> tasks) {
    final limited = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (!limited || tasks.length <= kIOSMaxScheduled) return tasks;
    return tasks.take(kIOSMaxScheduled).toList(growable: false);
  }

  /// 排期时捕获到 exact_alarms_not_permitted 的硬证据。
  /// 部分机型 `canScheduleExactNotifications()` 返回 null/true 不可信，
  /// 以实际排期异常为准（一加 13 实测横幅不出现的根因）
  bool _exactAlarmDenied = false;

  /// 最近一次排期 / 补发失败原因（自检横幅展示用）
  String? get lastError => _lastError;

  // ---------------------------------------------------------- 前台兜底

  /// 前台兜底巡检间隔。部分国产 ROM（ColorOS/MIUI/HarmonyOS 等）会延迟甚至
  /// 丢弃非精确闹钟，导致「App 还活着也不响」；App 存活期间改由本计时器到点发通知。
  static const Duration kNetInterval = Duration(seconds: 15);

  /// 到期后等待 OS 闹钟的宽限期：超过仍未触发（且排期仍在）才判定为被 ROM 丢弃
  static const Duration kDropGrace = Duration(seconds: 60);

  /// 已到期但尚未发出的任务，超过该时长不再补（视为过期噪音）
  static const Duration kLateWindow = Duration(minutes: 5);

  Timer? _netTimer;
  final Set<int> _shownThisSession = <int>{};

  /// 本进程内排期成功的任务 id：到期后若排期消失 = OS 已送达（不再补发）；
  /// 若从未排期成功（排期异常）= 必须由前台补发
  final Set<int> _armedIds = <int>{};

  /// 开始前台兜底（resume / 启动时调用）
  Future<void> startForegroundWatch() async {
    if (!_available || _netTimer != null) return;
    await _seedShown();
    _netTimer = Timer.periodic(kNetInterval, (_) => _foregroundTick());
  }

  /// 停止前台兜底（pause 时调用），并把提醒交还给 OS 排期
  void stopForegroundWatch() {
    _netTimer?.cancel();
    _netTimer = null;
  }

  bool get isForegroundWatchRunning => _netTimer != null;

  /// 启动/回前台时，把「已到期且 OS 排期已消失」的任务记为已送达：
  /// 它们大概率在后台由 OS 发过了，避免兜底逻辑再补一条造成双发
  Future<void> _seedShown() async {
    try {
      final now = DateTime.now();
      final tasks = await _tasks.queryRemindable();
      final pending = await _plugin.pendingNotificationRequests();
      final pendingIds = pending.map((p) => p.id).toSet();
      final plan = computeForegroundPlan(
        tasks: tasks,
        pendingIds: pendingIds,
        shownIds: _shownThisSession,
        armedIds: _armedIds,
        now: now,
        seeding: true,
      );
      _shownThisSession.addAll(plan.assumeDelivered);
    } catch (error) {
      debugPrint('[notify] 前台兜底初始化失败：$error');
    }
  }

  Future<void> _foregroundTick() async {
    if (_busy || !_available) return;
    try {
      final now = DateTime.now();
      final tasks = await _tasks.queryRemindable();
      final pending = await _plugin.pendingNotificationRequests();
      final pendingIds = pending.map((p) => p.id).toSet();
      final plan = computeForegroundPlan(
        tasks: tasks,
        pendingIds: pendingIds,
        shownIds: _shownThisSession,
        armedIds: _armedIds,
        now: now,
      );
      for (final id in plan.toCancel) {
        await _plugin.cancel(id: id);
      }
      // OS 已送达的静默去重，不补发
      _shownThisSession.addAll(plan.toMarkShown);
      for (final task in plan.toShow) {
        await _showNow(task);
        _shownThisSession.add(task.id!);
        await _tasks.markNotified(task.id!);
      }
    } catch (error) {
      _lastError = '$error';
      debugPrint('[notify] 前台兜底巡检失败：$error');
    }
  }

  /// 同步计划（**纯函数**，单测覆盖）：
  /// - 到期在未来 → 排期；
  /// - 已到期且未通知、在补发窗口内 → 立即补发；
  /// - 已到期且未通知、超出窗口 → 静默标记，不再打扰。
  static NotificationPlan computePlan({
    required List<Todo> dueTasks,
    required DateTime now,
    Duration catchUpWindow = kCatchUpWindow,
  }) {
    final toSchedule = <Todo>[];
    final toFireNow = <Todo>[];
    final toMarkSilent = <int>[];
    for (final task in dueTasks) {
      final due = task.remindAt;
      final id = task.id;
      if (due == null || id == null) continue;
      if (due.isAfter(now)) {
        toSchedule.add(task);
      } else if (!task.isNotified) {
        if (now.difference(due) <= catchUpWindow) {
          toFireNow.add(task);
        } else {
          toMarkSilent.add(id);
        }
      }
    }
    return NotificationPlan(
      toSchedule: toSchedule,
      toFireNow: toFireNow,
      toMarkSilent: toMarkSilent,
    );
  }

  /// 前台兜底决策（**纯函数**，单测覆盖）。
  ///
  /// 原则（吸取一加 13 回归教训）：**OS 排期是主通道，巡检只修丢单，
  /// 绝不提前收回排期**——收回会把「系统准时发」降级成「轮询补发」，
  /// 屏幕熄灭 / ROM 冻结计时器时反而更不准。
  ///
  /// - 到期前：一律不动（交给 OS）；
  /// - 到期后 [kDropGrace] 内：等待 OS 触发，不补发；
  /// - 到期后超宽限且排期仍在：判定被 ROM 丢弃 → 补发并收回；
  /// - 到期后排期已消失：若本进程排期成功过 = OS 已送达（静默记为已发）；
  ///   若从未排期成功 = 排期异常遗漏 → 补发；
  /// - 播种趟（[seeding]）：只把「到期 + 排期消失 + 未发过」记为已送达，
  ///   防止后台由 OS 发过的提醒在回前台时被补发成双条。
  static ForegroundPlan computeForegroundPlan({
    required List<Todo> tasks,
    required Set<int> pendingIds,
    required Set<int> shownIds,
    required Set<int> armedIds,
    required DateTime now,
    bool seeding = false,
    Duration dropGrace = kDropGrace,
    Duration lateWindow = kLateWindow,
  }) {
    final toShow = <Todo>[];
    final toCancel = <int>[];
    final toMarkShown = <int>[];
    final assumeDelivered = <int>[];
    for (final task in tasks) {
      final due = task.remindAt;
      final id = task.id;
      if (due == null || id == null) continue;
      final overdue = now.difference(due);
      if (overdue.isNegative) continue; // 未到期：OS 主通道，巡检不插手
      if (overdue > lateWindow) continue; // 过期噪音：不补
      if (shownIds.contains(id)) continue;
      final isPending = pendingIds.contains(id);

      if (seeding) {
        if (!isPending) assumeDelivered.add(id);
        continue;
      }
      if (isPending) {
        // 排期还在：宽限期内等 OS；超宽限 = 被 ROM 丢弃 → 补发并收回
        if (overdue > dropGrace) {
          toShow.add(task);
          toCancel.add(id);
        }
      } else if (armedIds.contains(id)) {
        // 排期消失且本进程排期成功过 = OS 已送达，静默去重
        toMarkShown.add(id);
      } else {
        // 从未排期成功（精确被拒且降级也失败等）→ 前台补发
        toShow.add(task);
      }
    }
    return ForegroundPlan(
      toShow: toShow,
      toCancel: toCancel,
      toMarkShown: toMarkShown,
      assumeDelivered: assumeDelivered,
    );
  }

  Future<void> _schedule(Todo task) async {
    final due = task.remindAt!;
    final scheduledDate = tz.TZDateTime.from(due, tz.local);
    try {
      await _plugin.zonedSchedule(
        id: task.id!,
        title: '待办提醒',
        body: _body(task),
        payload: '${task.id}',
        scheduledDate: scheduledDate,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        notificationDetails: _details,
      );
    } catch (error) {
      // Android 12+ 未授予「精确闹钟」时 exact 模式会抛异常 →
      // 降级为非精确（Doze 下仍会触发，可能延迟几分钟），保证提醒不丢
      debugPrint('[notify] 精确排期失败，降级为非精确：$error');
      _lastError = '$error';
      if ('$error'.contains('exact_alarms_not_permitted')) {
        _exactAlarmDenied = true;
      }
      await _plugin.zonedSchedule(
        id: task.id!,
        title: '待办提醒',
        body: _body(task),
        payload: '${task.id}',
        scheduledDate: scheduledDate,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: _details,
      );
    }
    _armedIds.add(task.id!);
    // 排期成功即视为「已交给系统」，防止补发逻辑重复提醒
    await _tasks.markNotified(task.id!);
  }

  Future<void> _showNow(Todo task) async {
    await _plugin.show(
      id: task.id!,
      title: '待办提醒',
      body: _body(task),
      notificationDetails: _details,
      payload: '${task.id}',
    );
  }

  String _body(Todo task) {
    final periodic = task.periodicTagLabel;
    return '${task.remindTime}　${task.title}'
        '${periodic == null ? '' : '（$periodic）'}';
  }

  /// 自检：系统通知开关 / Android 精确闹钟 / 当前排期数量
  Future<NotificationHealth> checkHealth() async {
    if (!_available) {
      return NotificationHealth(
        available: false,
        notificationsEnabled: false,
        exactAlarmsAllowed: false,
        pendingCount: 0,
        lastError: _lastError,
      );
    }
    var enabled = true;
    var exact = true;
    var pending = 0;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        enabled = await android.areNotificationsEnabled() ?? true;
        exact = (await android.canScheduleExactNotifications() ?? true) &&
            !_exactAlarmDenied;
      } else {
        // iOS / macOS 分别解析，避免 ?? 合并后丢失 checkPermissions 签名
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        final macos = _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>();
        final options = ios != null
            ? await ios.checkPermissions()
            : (macos != null ? await macos.checkPermissions() : null);
        enabled = options?.isEnabled ?? true;
      }
      pending = (await _plugin.pendingNotificationRequests()).length;
    } catch (error) {
      _lastError = '$error';
      debugPrint('[notify] 自检失败：$error');
    }
    return NotificationHealth(
      available: true,
      notificationsEnabled: enabled,
      exactAlarmsAllowed: exact,
      pendingCount: pending,
      lastError: _lastError,
    );
  }

  /// 请求 Android 精确闹钟权限（会跳转系统设置页）
  Future<bool> requestExactAlarms() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestExactAlarmsPermission() ?? false;
    } catch (error) {
      debugPrint('[notify] 请求精确闹钟权限失败：$error');
      return false;
    }
  }

  /// 打开系统通知设置（权限被拒时的修复入口）
  Future<void> openNotificationSettings() =>
      SystemSettings.openNotificationSettings();

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          kChannelId,
          kChannelName,
          channelDescription: '待办到点提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      );
}

/// [NotificationService.computePlan] 的结果
class NotificationPlan {
  /// 需要交给系统排期的任务（到期在未来）
  final List<Todo> toSchedule;

  /// 需要立即补发的任务（到期不久、从未通知）
  final List<Todo> toFireNow;

  /// 静默标记 is_notified 的任务 id（到期过久、从未通知）
  final List<int> toMarkSilent;

  const NotificationPlan({
    required this.toSchedule,
    required this.toFireNow,
    required this.toMarkSilent,
  });

  bool get isEmpty =>
      toSchedule.isEmpty && toFireNow.isEmpty && toMarkSilent.isEmpty;
}

/// 通知能力自检结果（用于「收不到通知」时的可见诊断与一键修复）
enum NotificationBlocker {
  /// 一切正常
  none,

  /// 插件 / 时区初始化失败（测试环境、不支持的平台）
  unavailable,

  /// 系统通知开关关闭（Android 13+ 权限被拒 / iOS 未授权）
  permissionDenied,

  /// Android 精确闹钟未授权：提醒会降级为非精确，可能延迟几分钟
  exactAlarmDenied,
}

class NotificationHealth {
  final bool available;
  final bool notificationsEnabled;
  final bool exactAlarmsAllowed;
  final int pendingCount;
  final String? lastError;

  const NotificationHealth({
    required this.available,
    required this.notificationsEnabled,
    required this.exactAlarmsAllowed,
    required this.pendingCount,
    this.lastError,
  });

  NotificationBlocker get blocker {
    if (!available) return NotificationBlocker.unavailable;
    if (!notificationsEnabled) return NotificationBlocker.permissionDenied;
    if (!exactAlarmsAllowed) return NotificationBlocker.exactAlarmDenied;
    return NotificationBlocker.none;
  }
}

/// [NotificationService.computeForegroundPlan] 的结果
class ForegroundPlan {
  /// 需要立即补发的任务（OS 丢单 / 从未排期成功）
  final List<Todo> toShow;

  /// 需要收回的 OS 排期 id（仅丢单补发时）
  final List<int> toCancel;

  /// OS 已送达、只需静默去重的任务 id
  final List<int> toMarkShown;

  /// 播种趟：视为「后台已送达」的任务 id
  final List<int> assumeDelivered;

  const ForegroundPlan({
    required this.toShow,
    required this.toCancel,
    required this.toMarkShown,
    required this.assumeDelivered,
  });
}
