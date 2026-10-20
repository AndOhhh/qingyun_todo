import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/confirm_dialog.dart';
import 'package:qingyun_todo/components/date_time_picker.dart';
import 'package:qingyun_todo/components/empty_state.dart';
import 'package:qingyun_todo/components/error_state.dart';
import 'package:qingyun_todo/components/form_card.dart';
import 'package:qingyun_todo/components/wide_button.dart';
import 'package:qingyun_todo/constants/routes.dart';
import 'package:qingyun_todo/logic/app_actions.dart';
import 'package:qingyun_todo/logic/periodic_actions.dart';
import 'package:qingyun_todo/pages/period/edit/widgets/cycle_preview.dart';
import 'package:qingyun_todo/models/cycle_rule.dart';
import 'package:qingyun_todo/models/interval_type.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/stores/invalidation.dart';
import 'package:qingyun_todo/stores/periodic_store.dart';
import 'package:qingyun_todo/utils/app_exception.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 周期类型预设（docs/01 §4.1，Q14 决策）
class _Preset {
  final String label;
  final IntervalType type;
  final int value;

  /// 「自定义天数」：选中后展开天数输入框
  final bool customDays;

  const _Preset(this.label, this.type, this.value, {this.customDays = false});
}

const List<_Preset> _kPresets = <_Preset>[
  _Preset('每天', IntervalType.day, 1),
  _Preset('每 2 天', IntervalType.day, 2),
  _Preset('自定义天数', IntervalType.day, 3, customDays: true),
  _Preset('每周', IntervalType.week, 1),
  _Preset('每 2 周', IntervalType.week, 2),
  _Preset('每月', IntervalType.month, 1),
  _Preset('每年', IntervalType.year, 1),
];

/// 周期新增 / 编辑页（FR-11 / C2）。
///
/// - 提供周期类型预设芯片（Q14）；
/// - 编辑既有周期时明示「已生成的待办日期不会改变」（Q8 / C2-4）；
/// - 缩短周期导致周期项越界时**阻止保存**并列出冲突项（Q12 / C2-3，由
///   `PeriodicRepository.update` 抛 [ValidationException]）；
/// - 未来 3 轮预览与生成引擎共用 [CycleRule]（C2-5）。
class PeriodicEditPage extends ConsumerStatefulWidget {
  final int? periodicId;

  const PeriodicEditPage({super.key, this.periodicId});

  @override
  ConsumerState<PeriodicEditPage> createState() => _PeriodicEditPageState();
}

class _PeriodicEditPageState extends ConsumerState<PeriodicEditPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _daysController = TextEditingController(text: '3');
  final TextEditingController _remarkController = TextEditingController();

  IntervalType _type = IntervalType.day;
  int _value = 1;
  bool _customDays = false;
  DateTime _startDate = DateUtil.today();
  DateTime? _endDate;

  String? _nameError;
  String? _daysError;
  bool _saving = false;
  bool _dirty = false;
  int? _syncedId;

  bool get _isNew => widget.periodicId == null;

  CycleRule get _rule {
    final value = _customDays
        ? (int.tryParse(_daysController.text.trim()) ?? 1)
        : _value;
    return CycleRule(
      type: _type,
      value: value < 1 ? 1 : value,
      startDate: _startDate,
    );
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    _daysController.addListener(() {
      _dirty = true;
      if (_daysError != null) setState(() => _daysError = null);
    });
    _remarkController.addListener(() => _dirty = true);
  }

  void _onNameChanged() {
    _dirty = true;
    if (_nameError != null && _nameController.text.trim().isNotEmpty) {
      setState(() => _nameError = null);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _daysController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  void _syncFrom(Periodic periodic) {
    if (_syncedId == periodic.id) return;
    _syncedId = periodic.id;
    _nameController.text = periodic.name;
    _remarkController.text = periodic.remark ?? '';
    _type = periodic.intervalType;
    _value = periodic.intervalValue;
    _startDate = DateUtil.dateOnly(periodic.startDate);
    _endDate = periodic.endDate;
    // 预设里没有的组合 → 归到「自定义天数」
    _customDays = periodic.intervalType == IntervalType.day &&
        !_kPresets.any(
          (p) => !p.customDays &&
              p.type == periodic.intervalType &&
              p.value == periodic.intervalValue,
        );
    if (_customDays) _daysController.text = '${periodic.intervalValue}';
    _nameError = null;
    _dirty = false;
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.periodicId;
    if (id == null) return _buildForm(null, null);
    final async = ref.watch(periodicDetailProvider(id));
    return async.when(
      loading: () => _shell(
        showSave: false,
        body: const Center(child: CupertinoActivityIndicator(radius: 13)),
      ),
      error: (error, _) => _shell(
        showSave: false,
        body: ErrorState(
          error: error,
          onRetry: () => ref.invalidate(periodicDetailProvider(id)),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return _shell(
            showSave: false,
            body: EmptyState(
              icon: CupertinoIcons.question_circle,
              iconColor: const Color(0xFF8E8E93),
              title: '周期不存在',
              subtitle: '它可能已被删除',
              action: CupertinoButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ),
          );
        }
        _syncFrom(detail.periodic);
        return _buildForm(detail.periodic, detail.items);
      },
    );
  }

  Widget _shell({required Widget body, required bool showSave, Periodic? periodic}) {
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
          middle: Text(_isNew ? '新建周期' : '编辑周期'),
          trailing: showSave
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _saving ? null : () => _save(periodic),
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

  Widget _buildForm(Periodic? periodic, List<PeriodicItem>? items) {
    final rule = _rule;
    final previews = ref.watch(cyclePreviewProvider(rule));
    return _shell(
      showSave: true,
      periodic: periodic,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          children: <Widget>[
            FormCard(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      CupertinoTextField.borderless(
                        controller: _nameController,
                        placeholder: '周期名称，如「隔天喝饮品计划」',
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
                      if (_nameError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _nameError!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFF3B30),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FormCard(
              header: '周期规则',
              footer: _daysError ?? _ruleFooter(rule),
              children: <Widget>[
                FormBlock(
                  label: '重复方式',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final preset in _kPresets)
                        _PresetChip(
                          label: preset.label,
                          selected: _isSelected(preset),
                          onTap: () {
                            if (_isSelected(preset)) return;
                            setState(() {
                              _customDays = preset.customDays;
                              _type = preset.type;
                              _value = preset.customDays
                                  ? (int.tryParse(_daysController.text.trim()) ??
                                      3)
                                  : preset.value;
                              _dirty = true;
                            });
                          },
                        ),
                    ],
                  ),
                ),
                if (_customDays)
                  FormRow(
                    label: '每 N 天一轮',
                    trailing: SizedBox(
                      width: 92,
                      child: CupertinoTextField(
                        controller: _daysController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1C1C1E),
                        ),
                      ),
                    ),
                  ),
                FormRow(
                  label: '起始日期',
                  valueText:
                      '${DateUtil.humanDate(_startDate)} ${DateUtil.weekdayLabel(_startDate)}',
                  valueColor: const Color(0xFF1C1C1E),
                  showChevron: true,
                  onTap: _pickStartDate,
                ),
                FormRow(
                  label: '终止日期',
                  showChevron: true,
                  onTap: _pickEndDate,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _endDate == null
                            ? '不设置（无限循环）'
                            : DateUtil.humanDate(_endDate!),
                        style: TextStyle(
                          fontSize: 15,
                          color: _endDate == null
                              ? const Color(0xFF8E8E93)
                              : const Color(0xFF1C1C1E),
                        ),
                      ),
                      if (_endDate != null)
                        CupertinoButton(
                          padding: const EdgeInsets.only(left: 8),
                          onPressed: () => setState(() {
                            _endDate = null;
                            _dirty = true;
                          }),
                          child: const Text(
                            '清除',
                            style: TextStyle(fontSize: 13, color: Color(0xFFFF3B30)),
                          ),
                        ),
                      const SizedBox(width: 6),
                      const Icon(
                        CupertinoIcons.chevron_right,
                        size: 14,
                        color: Color(0xFFC7C7CC),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FormCard(
              header: '未来 3 轮预览',
              footer: items == null || items.isEmpty
                  ? '保存后进入周期详情页，为每一天安排具体事项。'
                  : '预览与生成引擎使用同一套推算规则，所见即所得。',
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: CyclePreviewTimeline(
                    previews: previews,
                    items: items ?? const <PeriodicItem>[],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FormCard(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
            if (periodic != null) ...<Widget>[
              const SizedBox(height: 18),
              // Q8 / C2-4 / N14：日期类规则变更会重建未完成计划
              const InfoBanner(
                text: '已完成的历史记录不会改变；修改起始日或间隔后，未完成的待办会按'
                    '新规则从今天所在轮重新安排。缩短周期时若有事项越界，会阻止保存并列出冲突项。',
                color: Color(0xFF007AFF),
                icon: CupertinoIcons.clock,
              ),
              const SizedBox(height: 24),
              WideButton(
                label: periodic.isActive ? '暂停周期' : '启用周期',
                icon: periodic.isActive
                    ? CupertinoIcons.pause_circle
                    : CupertinoIcons.play_circle,
                color: const Color(0xFF8E8E93),
                onTap: () => togglePeriodicActive(context, ref, periodic),
              ),
              const SizedBox(height: 10),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _saving
                    ? null
                    : () => requestDeletePeriodic(
                          context,
                          periodicId: periodic.id!,
                          periodicName: periodic.name,
                          onDeleted: () {
                            if (mounted) {
                              _dirty = false;
                              Navigator.of(context).pop(true);
                            }
                          },
                        ),
                child: const Text(
                  '删除周期',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFF3B30),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 规则说明：一轮天数与可安排的天序范围
  String _ruleFooter(CycleRule rule) {
    final natural = _type == IntervalType.month || _type == IntervalType.year
        ? '（最短轮次，实际按自然${_type.unit}推算）'
        : '';
    return '一轮 ${rule.minCycleLength} 天$natural，'
        '事项可安排在第 1 ~ 第 ${rule.minCycleLength} 天。';
  }

  bool _isSelected(_Preset preset) {
    if (preset.customDays) return _customDays;
    if (_customDays) return false;
    return preset.type == _type && preset.value == _value;
  }

  Future<void> _pickStartDate() async {
    final picked = await pickDate(context, initial: _startDate);
    if (picked == null || !mounted) return;
    final next = DateUtil.dateOnly(picked);
    if (next == _startDate) return;
    setState(() {
      _startDate = next;
      _dirty = true;
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await pickDate(
      context,
      initial: _endDate ?? _startDate,
      quickDates: const <QuickDate>[],
      title: '终止日期',
    );
    if (picked == null || !mounted) return;
    final next = DateUtil.dateOnly(picked);
    if (next == _endDate) return;
    setState(() {
      _endDate = next;
      _dirty = true;
    });
  }

  Future<void> _save(Periodic? existing) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '请填写周期名称');
      return;
    }
    var value = _value;
    if (_customDays) {
      value = int.tryParse(_daysController.text.trim()) ?? 0;
      if (value < 1) {
        setState(() => _daysError = '请输入大于 0 的天数');
        return;
      }
    }
    final remark = _remarkController.text.trim();
    final draft = (existing ?? Periodic(name: name, startDate: _startDate))
        .copyWith(
      name: name,
      startDate: DateUtil.dateOnly(_startDate),
      intervalType: _type,
      intervalValue: value,
      endDate: _endDate,
      clearEndDate: _endDate == null,
      remark: remark.isEmpty ? null : remark,
      clearRemark: remark.isEmpty,
    );

    setState(() {
      _saving = true;
      _daysError = null;
    });
    try {
      final repository = ref.read(periodicRepositoryProvider);
      if (existing == null) {
        final id = await repository.insert(draft);
        invalidateAfterPeriodicWrite(ref.invalidate);
        if (!mounted) return;
        _dirty = false;
        // 新建后**替换**当前路由进入详情页安排事项，减少一次来回；
        // 用 pushReplacementNamed 而不是「pop 后再 push」，避免使用已失效的 context
        unawaited(
          Navigator.of(context).pushReplacementNamed(
            RouteConstants.periodicDetailPath(id),
          ),
        );
      } else {
        await repository.update(draft);
        invalidateAfterPeriodicWrite(ref.invalidate);
        if (!mounted) return;
        _dirty = false;
        Navigator.of(context).pop(true);
      }
    } on ValidationException catch (error) {
      // Q12：缩短周期越界 / 名称为空 / 日期非法
      if (!mounted) return;
      setState(() => _saving = false);
      await showActionDialog(
        context,
        title: '无法保存',
        content: error.fullMessage,
        actions: const <DialogAction>[DialogAction('知道了', isDefault: true)],
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showActionError(context, error);
    }
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF007AFF).withValues(alpha: 0.12)
              : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF007AFF) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? const Color(0xFF007AFF) : const Color(0xFF636366),
          ),
        ),
      ),
    );
  }
}
