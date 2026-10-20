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
import 'package:qingyun_todo/components/wide_button.dart';
import 'package:qingyun_todo/logic/app_actions.dart';
import 'package:qingyun_todo/logic/periodic_actions.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/stores/invalidation.dart';
import 'package:qingyun_todo/stores/periodic_store.dart';

/// 周期项新增 / 编辑页（FR-12 / C3-2 ~ C3-5）。
///
/// - `day_offset` 上限 = 一轮最短天数（C3-3），越界由 Repository 抛校验异常；
/// - 编辑已生成过实例的模板项时提示「不影响已生成待办」（C3-5 / Q8）；
/// - MONTH / YEAR 且天序 >= 28 时提示短月份可能跳过（C2-6）。
class PeriodicItemEditPage extends ConsumerStatefulWidget {
  /// 编辑态：周期项 id
  final int? itemId;

  /// 新增态：所属周期 id
  final int? periodicId;

  /// 新增态：默认天序（从哪一天的「添加」按钮进来）
  final int initialDayOffset;

  const PeriodicItemEditPage({
    super.key,
    this.itemId,
    this.periodicId,
    this.initialDayOffset = 0,
  });

  @override
  ConsumerState<PeriodicItemEditPage> createState() =>
      _PeriodicItemEditPageState();
}

class _PeriodicItemEditPageState extends ConsumerState<PeriodicItemEditPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();

  late int _dayOffset = widget.initialDayOffset;
  String? _remindTime;
  TodoPriority _priority = TodoPriority.none;
  String? _accentColorHex;

  String? _titleError;
  bool _saving = false;
  bool _dirty = false;
  int? _syncedId;

  bool get _isNew => widget.itemId == null;

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
    _titleController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  void _syncFrom(PeriodicItem item) {
    if (_syncedId == item.id) return;
    _syncedId = item.id;
    _titleController.text = item.title;
    _remarkController.text = item.remark ?? '';
    _dayOffset = item.dayOffset;
    _remindTime = item.remindTime;
    _priority = item.priority;
    _accentColorHex = item.accentColorHex;
    _titleError = null;
    _dirty = false;
  }

  @override
  Widget build(BuildContext context) {
    final itemId = widget.itemId;
    if (itemId != null) {
      final async = ref.watch(periodicItemProvider(itemId));
      return async.when(
        loading: () => _shell(showSave: false, body: _loading()),
        error: (error, _) => _shell(
          showSave: false,
          body: ErrorState(
            error: error,
            onRetry: () => ref.invalidate(periodicItemProvider(itemId)),
          ),
        ),
        data: (item) {
          if (item == null || item.periodicId == null) {
            return _shell(showSave: false, body: _missing('事项不存在'));
          }
          _syncFrom(item);
          return _buildForPeriodic(item.periodicId!, item);
        },
      );
    }
    final periodicId = widget.periodicId;
    if (periodicId == null) {
      return _shell(showSave: false, body: _missing('缺少周期信息'));
    }
    return _buildForPeriodic(periodicId, null);
  }

  Widget _buildForPeriodic(int periodicId, PeriodicItem? item) {
    final async = ref.watch(periodicDetailProvider(periodicId));
    return async.when(
      loading: () => _shell(showSave: false, body: _loading()),
      error: (error, _) => _shell(
        showSave: false,
        body: ErrorState(
          error: error,
          onRetry: () => ref.invalidate(periodicDetailProvider(periodicId)),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return _shell(showSave: false, body: _missing('周期不存在'));
        }
        return _buildForm(detail, item);
      },
    );
  }

  Widget _loading() =>
      const Center(child: CupertinoActivityIndicator(radius: 13));

  Widget _missing(String message) => EmptyState(
        icon: CupertinoIcons.question_circle,
        iconColor: const Color(0xFF8E8E93),
        title: message,
        subtitle: '它可能已被删除',
        action: CupertinoButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('返回'),
        ),
      );

  Widget _shell({
    required Widget body,
    required bool showSave,
    PeriodicDetail? detail,
    PeriodicItem? item,
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
          middle: Text(_isNew ? '新增事项' : '编辑事项'),
          trailing: showSave
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _saving ? null : () => _save(detail, item),
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

  Widget _buildForm(PeriodicDetail detail, PeriodicItem? item) {
    final dayCount = detail.dayCount;
    final dayOffset = _dayOffset.clamp(0, dayCount < 1 ? 0 : dayCount - 1);
    final rule = detail.periodic.rule;
    final dates = rule.datesForDayOffset(dayOffset, cycles: 3);
    final generatedCount = item?.id == null
        ? 0
        : (ref.watch(periodicItemInstanceCountProvider(item!.id!)).valueOrNull ??
            0);

    return _shell(
      showSave: true,
      detail: detail,
      item: item,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          children: <Widget>[
            FormCard(
              header: '周期·${detail.periodic.name}（${detail.periodic.intervalLabel}）',
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      CupertinoTextField.borderless(
                        controller: _titleController,
                        placeholder: '这一天要做什么？',
                        autofocus: _isNew,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1C1C1E),
                        ),
                        placeholderStyle: const TextStyle(
                          fontSize: 16,
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
                    placeholder: '备注（可选）',
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
              header: '安排',
              footer: dates.isEmpty
                  ? '按当前规则，未来 3 轮都不会生成这一天的待办。'
                  : '接下来 3 次：'
                      '${dates.map((d) => '${d.month}月${d.day}日').join('、')}',
              children: <Widget>[
                FormRow(
                  label: '第几天',
                  valueText: '第 ${dayOffset + 1} 天',
                  valueColor: const Color(0xFF1C1C1E),
                  showChevron: true,
                  onTap: () => _pickDayOffset(dayCount),
                ),
                FormRow(
                  label: '提醒时间',
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
                    onChanged: (value) {
                      if (value == _priority) return;
                      setState(() {
                        _priority = value;
                        _dirty = true;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FormCard(
              children: <Widget>[
                FormBlock(
                  label: '色带颜色',
                  hint: '生成的待办会沿用这个色带；默认按优先级取色。',
                  child: AccentColorPicker(
                    value: _accentColorHex,
                    priority: _priority,
                    onChanged: (hex) {
                      if (hex == _accentColorHex) return;
                      setState(() {
                        _accentColorHex = hex;
                        _dirty = true;
                      });
                    },
                  ),
                ),
              ],
            ),
            if (generatedCount > 0) ...<Widget>[
              const SizedBox(height: 16),
              InfoBanner(
                text: '该事项已生成过 $generatedCount 条待办。修改标题 / 备注 / 优先级 / '
                    '色带只影响之后生成的待办；修改「第几天 / 提醒时间」会按新值重排'
                    '该事项的未完成待办（已完成的不变）。',
                color: const Color(0xFF007AFF),
              ),
            ],
            if (item != null) ...<Widget>[
              const SizedBox(height: 28),
              WideButton(
                label: '删除该事项',
                icon: CupertinoIcons.trash,
                color: const Color(0xFFFF3B30),
                onTap: _saving
                    ? null
                    : () => requestDeletePeriodicItem(
                          context,
                          ref,
                          item,
                          onDeleted: () {
                            if (mounted) {
                              _dirty = false;
                              Navigator.of(context).pop(true);
                            }
                          },
                        ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '未完成的待办会被删除，已完成的保留为历史记录',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF8E8E93)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDayOffset(int dayCount) async {
    if (dayCount < 1) return;
    final picked = await showCupertinoModalPopup<int>(
      context: context,
      builder: (ctx) => _DayOffsetSheet(
        dayCount: dayCount,
        initial: _dayOffset.clamp(0, dayCount - 1),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == _dayOffset) return;
    setState(() {
      _dayOffset = picked;
      _dirty = true;
    });
  }

  Future<void> _pickTime() async {
    final result = await pickTime(context, initial: _remindTime);
    if (result == null || !mounted) return;
    final next = result.cleared ? null : result.time;
    if (next == _remindTime) return;
    setState(() {
      _remindTime = next;
      _dirty = true;
    });
  }

  Future<void> _save(PeriodicDetail? detail, PeriodicItem? existing) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '请填写事项标题');
      return;
    }
    if (detail == null) return;
    final periodicId = detail.periodic.id!;
    final remark = _remarkController.text.trim();
    final draft = (existing ??
            PeriodicItem(
              title: title,
              dayOffset: _dayOffset,
              periodicId: periodicId,
            ))
        .copyWith(
      periodicId: periodicId,
      title: title,
      dayOffset: _dayOffset,
      remark: remark.isEmpty ? null : remark,
      clearRemark: remark.isEmpty,
      remindTime: _remindTime,
      clearRemindTime: _remindTime == null,
      priority: _priority,
      accentColorHex: _accentColorHex,
      clearAccentColor: _accentColorHex == null,
    );

    setState(() => _saving = true);
    try {
      final repository = ref.read(periodicItemRepositoryProvider);
      if (existing == null) {
        await repository.insert(draft);
      } else {
        await repository.update(draft);
      }
      invalidateAfterPeriodicWrite(ref.invalidate);
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showActionError(context, error);
    }
  }
}

/// 「第 N 天」滚轮选择器（天序上限 = 一轮最短天数，C3-3）
class _DayOffsetSheet extends StatefulWidget {
  final int dayCount;
  final int initial;

  const _DayOffsetSheet({required this.dayCount, required this.initial});

  @override
  State<_DayOffsetSheet> createState() => _DayOffsetSheetState();
}

class _DayOffsetSheetState extends State<_DayOffsetSheet> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: widget.initial);
  late int _selected = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: <Widget>[
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(fontSize: 16, color: Color(0xFF8E8E93)),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '安排在第几天（共 ${widget.dayCount} 天）',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: const Text(
                      '确定',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.6, color: Color(0xFFE5E5EA)),
            Expanded(
              child: CupertinoPicker(
                scrollController: _controller,
                itemExtent: 38,
                onSelectedItemChanged: (index) => _selected = index,
                children: <Widget>[
                  for (var i = 0; i < widget.dayCount; i++)
                    Center(
                      child: Text(
                        '第 ${i + 1} 天',
                        style: const TextStyle(
                          fontSize: 17,
                          color: Color(0xFF1C1C1E),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
