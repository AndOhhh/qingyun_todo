import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/color_picker.dart';
import 'package:qingyun_todo/components/confirm_dialog.dart';
import 'package:qingyun_todo/components/date_time_picker.dart';
import 'package:qingyun_todo/components/empty_state.dart';
import 'package:qingyun_todo/components/error_state.dart';
import 'package:qingyun_todo/components/form_card.dart';
import 'package:qingyun_todo/components/priority_picker.dart';
import 'package:qingyun_todo/logic/app_actions.dart';
import 'package:qingyun_todo/logic/todo_actions.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/stores/invalidation.dart';
import 'package:qingyun_todo/stores/todo_store.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 待办新增 / 编辑页（详情页与编辑页**合并**为一页，docs/07 B2）。
///
/// - `taskId == null`：新增常规待办；
/// - `taskId != null`：编辑；若该待办是周期实例，额外提示
///   「修改只影响这一次，不回写模板」（B2-7 / docs/07 D1）。
class TodoEditPage extends ConsumerStatefulWidget {
  final int? taskId;

  /// 新增态的默认提醒日期（日程页「+」会带上选中日期）
  final DateTime? initialDate;

  const TodoEditPage({super.key, this.taskId, this.initialDate});

  @override
  ConsumerState<TodoEditPage> createState() => _TodoEditPageState();
}

class _TodoEditPageState extends ConsumerState<TodoEditPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();

  // `late`：字段初始化时 widget 尚未挂载，首次访问（initState 之后）才取值
  late DateTime _remindDate =
      DateUtil.dateOnly(widget.initialDate ?? DateUtil.today());
  String? _remindTime;
  TodoPriority _priority = TodoPriority.none;
  String? _accentColorHex;

  String? _titleError;
  bool _saving = false;

  /// 已同步进表单的任务 id：避免每次 provider 刷新都覆盖用户正在编辑的内容
  int? _syncedId;

  /// 有未保存改动时，返回前需要确认
  bool _dirty = false;

  bool get _isNew => widget.taskId == null;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onTitleChanged);
    _remarkController.addListener(() => _dirty = true);
  }

  void _onTitleChanged() {
    _dirty = true;
    if (_titleError != null && _titleController.text.trim().isNotEmpty) {
      setState(() => _titleError = null);
    }
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_onTitleChanged)
      ..dispose();
    _remarkController.dispose();
    super.dispose();
  }

  /// 把库里的值填进表单（仅首次）；在 build 中调用，故不能 setState
  void _syncFrom(Todo task) {
    if (_syncedId == task.id) return;
    _syncedId = task.id;
    _titleController.text = task.title;
    _remarkController.text = task.remark ?? '';
    _remindDate = DateUtil.dateOnly(task.remindDate);
    _remindTime = task.remindTime;
    _priority = task.priority;
    _accentColorHex = task.accentColorHex;
    _titleError = null;
    _dirty = false;
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.taskId;
    if (id == null) return _buildForm(null);
    final async = ref.watch(todoDetailProvider(id));
    return async.when(
      loading: () => _shell(
        body: const Center(child: CupertinoActivityIndicator(radius: 13)),
        showSave: false,
      ),
      error: (error, _) => _shell(
        body: ErrorState(
          error: error,
          onRetry: () => ref.invalidate(todoDetailProvider(id)),
        ),
        showSave: false,
      ),
      data: (task) {
        if (task == null) {
          return _shell(
            body: EmptyState(
              icon: CupertinoIcons.question_circle,
              iconColor: const Color(0xFF8E8E93),
              title: '待办不存在',
              subtitle: '它可能已被删除',
              action: CupertinoButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ),
            showSave: false,
          );
        }
        _syncFrom(task);
        return _buildForm(task);
      },
    );
  }

  /// 页面骨架：用 Material [Scaffold] 承载，撤销删除的 SnackBar 才会在本页可见
  Widget _shell({
    required Widget body,
    required bool showSave,
    Todo? task,
  }) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await showConfirmDialog(
          context,
          title: '放弃编辑？',
          content: '当前修改尚未保存，放弃后将丢失。',
          confirmText: '放弃',
          isDestructive: true,
        );
        if (!discard || !mounted) return;
        _dirty = false;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        appBar: CupertinoNavigationBar(
          middle: Text(_isNew ? '新建待办' : '编辑待办'),
          trailing: showSave
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _saving ? null : () => _save(task),
                  child: Text(
                    _saving ? '保存中…' : '保存',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _saving
                          ? const Color(0xFF8E8E93)
                          : const Color(0xFF007AFF),
                    ),
                  ),
                )
              : null,
        ),
        body: body,
      ),
    );
  }

  Widget _buildForm(Todo? task) {
    return _shell(
      showSave: true,
      task: task,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          children: <Widget>[
            if (task != null && task.isPeriodic) ...<Widget>[
              InfoBanner(
                text: '来自周期·${task.periodicNameSnapshot ?? '未知'}'
                    '${task.cycleLabel == null ? '' : '（${task.cycleLabel}）'}，'
                    '修改只影响这一次，不会回写周期模板。',
              ),
              const SizedBox(height: 14),
            ],
            FormCard(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      CupertinoTextField.borderless(
                        controller: _titleController,
                        placeholder: '要做什么？',
                        autofocus: _isNew,
                        textInputAction: TextInputAction.next,
                        maxLines: 2,
                        minLines: 1,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: Color(0xFF1C1C1E),
                        ),
                        placeholderStyle: const TextStyle(
                          fontSize: 17,
                          color: Color(0xFFC7C7CC),
                        ),
                      ),
                      if (_titleError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _titleError!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFF3B30),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: CupertinoTextField.borderless(
                    controller: _remarkController,
                    placeholder: '备注',
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: Color(0xFF636366),
                    ),
                    placeholderStyle: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFFC7C7CC),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FormCard(
              header: '提醒',
              footer: '日期允许选择过去，方便补记已经发生的事。',
              children: <Widget>[
                FormRow(
                  label: '日期',
                  valueText:
                      '${DateUtil.humanDate(_remindDate)} ${DateUtil.weekdayLabel(_remindDate)}',
                  valueColor: const Color(0xFF1C1C1E),
                  showChevron: true,
                  onTap: _pickDate,
                ),
                FormRow(
                  label: '时间',
                  valueText: _remindTime ?? '不设置',
                  valueColor: _remindTime == null
                      ? const Color(0xFF8E8E93)
                      : const Color(0xFF1C1C1E),
                  showChevron: true,
                  onTap: _pickTime,
                ),
              ],
            ),
            const SizedBox(height: 18),
            FormCard(
              children: <Widget>[
                FormBlock(
                  label: '优先级',
                  child: PriorityPicker(
                    value: _priority,
                    onChanged: (value) => setState(() {
                      _priority = value;
                      _dirty = true;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FormCard(
              children: <Widget>[
                FormBlock(
                  label: '色带颜色',
                  hint: '默认按优先级取色（改优先级会跟着变）；点选色块可单独指定。',
                  child: AccentColorPicker(
                    value: _accentColorHex,
                    priority: _priority,
                    onChanged: (hex) => setState(() {
                      _accentColorHex = hex;
                      _dirty = true;
                    }),
                  ),
                ),
              ],
            ),
            if (task != null) ...<Widget>[
              const SizedBox(height: 18),
              // 完成与删除收进同一张动作卡（与页面其它 FormCard 同构）：
              // 完成 = 绿色即时动作；删除 = 红色危险动作（二次确认 / 周期实例走三级
              // 动作表 + 5 秒撤销）。颜色、位置、确认强度三者仍完全分离（Q5）。
              FormCard(
                footer: task.isPeriodic
                    ? '周期实例可选择「只删这一次 / 删该事项的未来待办 / 删整个周期」'
                    : null,
                children: <Widget>[
                  FormRow(
                    label: task.isCompleted ? '取消完成' : '标记完成',
                    labelColor: task.isCompleted
                        ? const Color(0xFF8E8E93)
                        : const Color(0xFF34C759),
                    minHeight: 54,
                    leading: Icon(
                      task.isCompleted
                          ? CupertinoIcons.arrow_counterclockwise
                          : CupertinoIcons.checkmark_circle_fill,
                      size: 20,
                      color: task.isCompleted
                          ? const Color(0xFF8E8E93)
                          : const Color(0xFF34C759),
                    ),
                    onTap: _saving ? null : () => _toggleComplete(task),
                  ),
                  FormRow(
                    label: '删除待办',
                    labelColor: const Color(0xFFFF3B30),
                    minHeight: 54,
                    leading: const Icon(
                      CupertinoIcons.trash,
                      size: 20,
                      color: Color(0xFFFF3B30),
                    ),
                    onTap: _saving ? null : () => _delete(task),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initial: _remindDate);
    if (picked == null || !mounted) return;
    setState(() {
      _remindDate = DateUtil.dateOnly(picked);
      _dirty = true;
    });
  }

  Future<void> _pickTime() async {
    final result = await pickTime(
      context,
      initial: _remindTime ?? _pickerSeedTime,
    );
    if (result == null || !mounted) return;
    setState(() {
      _remindTime = result.cleared ? null : result.time;
      _dirty = true;
    });
  }

  /// 新增态尚未设置提醒时间时，时间选择器的起始值（`HH:mm`）：
  /// - **待办页新增**（未带 `initialDate`）→ 当前时刻：当日事务通常就选「现在附近」，
  ///   从 09:00 起步要滚很多格；
  /// - **日程页新增**（带了选中日期）→ null：沿用控件默认 09:00，
  ///   按天规划的场景固定上午 9 点更符合语义；
  /// - 编辑已有待办时 [_remindTime] 有值，不会走到这里。
  ///
  /// 用 `initialDate` 区分入口是既有约定：目前只有日程页「+」会传它。
  String? get _pickerSeedTime =>
      _isNew && widget.initialDate == null
          ? DateUtil.formatTime(DateTime.now())
          : null;

  /// 标记完成 / 取消完成：状态即时落库，成功后**直接返回上一页**（N20）。
  ///
  /// 完成状态本身就是一次写操作，不需要用户再点「保存」；若此前还改过其它字段，
  /// 先按最新库值把编辑落盘再退出，避免静默丢弃（`_save` 成功后自行 pop）。
  Future<void> _toggleComplete(Todo task) async {
    final ok = await toggleTodoComplete(context, ref, task);
    if (!ok || !mounted) return;
    if (_dirty) {
      final latest = await ref.read(todoDetailProvider(task.id!).future);
      if (!mounted) return;
      if (latest != null) {
        await _save(latest);
        return;
      }
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _save(Todo? existing) async {
    final title = _titleController.text.trim();
    // B2-4：标题非空校验；日期允许过去（支持补记）
    if (title.isEmpty) {
      setState(() => _titleError = '请填写标题');
      return;
    }
    final remark = _remarkController.text.trim();
    final draft = (existing ?? Todo(title: title, remindDate: _remindDate))
        .copyWith(
      title: title,
      remark: remark.isEmpty ? null : remark,
      clearRemark: remark.isEmpty,
      remindDate: DateUtil.dateOnly(_remindDate),
      remindTime: _remindTime,
      clearRemindTime: _remindTime == null,
      priority: _priority,
      accentColorHex: _accentColorHex,
      clearAccentColor: _accentColorHex == null,
    );

    setState(() => _saving = true);
    try {
      final repository = ref.read(taskRepositoryProvider);
      if (existing == null) {
        await repository.insert(draft);
      } else {
        await repository.update(draft);
      }
      invalidateAfterTaskWrite(ref.invalidate, periodicId: draft.periodicId);
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showActionError(context, error);
    }
  }

  Future<void> _delete(Todo task) async {
    await requestDeleteTodo(
      context,
      ref,
      task,
      onDeleted: () {
        if (mounted) {
          _dirty = false;
          Navigator.of(context).pop(true);
        }
      },
    );
  }
}
