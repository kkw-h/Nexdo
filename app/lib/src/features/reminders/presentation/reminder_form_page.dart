import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_ui_primitives.dart';
import '../domain/entities/reminder_models.dart';

enum ReminderFormAction { save, delete }

class ReminderFormResult {
  const ReminderFormResult.save(this.reminder)
    : action = ReminderFormAction.save;

  const ReminderFormResult.delete(this.reminder)
    : action = ReminderFormAction.delete;

  final ReminderFormAction action;
  final ReminderItem reminder;
}

class ReminderFormPage extends StatefulWidget {
  const ReminderFormPage({
    super.key,
    required this.availableLists,
    required this.availableGroups,
    required this.availableTags,
    required this.existingReminders,
    this.loadCompletionLogs,
    this.initialReminder,
  });

  final List<ReminderList> availableLists;
  final List<ReminderGroup> availableGroups;
  final List<ReminderTag> availableTags;
  final List<ReminderItem> existingReminders;
  final Future<List<ReminderCompletionLog>> Function(String reminderId)?
  loadCompletionLogs;
  final ReminderItem? initialReminder;

  @override
  State<ReminderFormPage> createState() => _ReminderFormPageState();
}

class _ReminderFormPageState extends State<ReminderFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late final TextEditingController _hourController;
  late final TextEditingController _minuteController;
  late final FocusNode _hourFocusNode;
  late final FocusNode _minuteFocusNode;
  late DateTime _selectedDateTime;
  late String _selectedListId;
  late String _selectedGroupId;
  late Set<String> _selectedTagIds;
  late bool _notificationEnabled;
  late bool _hasSpecificTime;
  late bool _noteEnabled;
  late ReminderRepeatRule _repeatRule;
  late DateTime? _repeatEndAt;
  late int? _remindBeforeMinutes;
  bool get _isEditing => widget.initialReminder != null;

  @override
  void initState() {
    super.initState();
    final reminder = widget.initialReminder;
    final initialLists = _sortedLists();
    final initialGroups = _sortedGroups();
    _titleController = TextEditingController(text: reminder?.title ?? '');
    _noteController = TextEditingController(text: reminder?.note ?? '');
    _hourController = TextEditingController();
    _minuteController = TextEditingController();
    _hourFocusNode = FocusNode();
    _minuteFocusNode = FocusNode();
    _hourFocusNode.addListener(_handleHourFocusChange);
    _minuteFocusNode.addListener(_handleMinuteFocusChange);
    _selectedDateTime =
        reminder?.dueAt ?? DateTime.now().add(const Duration(hours: 2));
    _hasSpecificTime = reminder?.hasSpecificTime ?? true;
    _noteEnabled = reminder?.note?.trim().isNotEmpty ?? false;
    _selectedListId =
        reminder?.listId ??
        (initialLists.isNotEmpty ? initialLists.first.id : '');
    _selectedGroupId =
        reminder?.groupId ??
        (initialGroups.isNotEmpty ? initialGroups.first.id : '');
    _selectedTagIds = {...?reminder?.tagIds};
    _notificationEnabled =
        _hasSpecificTime && (reminder?.notificationEnabled ?? true);
    _repeatRule = reminder?.repeatRule ?? ReminderRepeatRule.none;
    _repeatEndAt = reminder?.repeatEndAt;
    _remindBeforeMinutes = reminder?.remindBeforeMinutes;
    _syncTimeControllers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    _hourFocusNode.dispose();
    _minuteFocusNode.dispose();
    super.dispose();
  }

  void _handleHourFocusChange() {
    if (_hourFocusNode.hasFocus) {
      _selectAllTimeField(_hourController);
      return;
    }
    _normalizeHourInput();
  }

  void _handleMinuteFocusChange() {
    if (_minuteFocusNode.hasFocus) {
      _selectAllTimeField(_minuteController);
      return;
    }
    _normalizeMinuteInput();
  }

  void _selectAllTimeField(TextEditingController controller) {
    if (!_hasSpecificTime || controller.text.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    });
  }

  void _dismissKeyboard() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus) {
      currentFocus.unfocus();
    }
  }

  void _focusMinuteField() {
    if (!_hasSpecificTime) {
      return;
    }
    _minuteFocusNode.requestFocus();
    _selectAllTimeField(_minuteController);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final lists = _sortedLists();
    final groups = _sortedGroups();
    final formBody = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _dismissKeyboard,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 132),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _FormNavBar(
                isEditing: _isEditing,
                onClose: () => Navigator.of(context).pop(),
                onDelete: _isEditing ? _deleteReminder : null,
                onSave: _submit,
              ),
              const SizedBox(height: 18),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionTitle(label: '标题', required: true),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _titleController,
                      maxLength: 60,
                      decoration: InputDecoration(
                        hintText: '请输入提醒标题',
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintStyle: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: palette.textMuted.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: palette.onSurface,
                            height: 1.3,
                          ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入提醒标题';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: palette.outlineSoft),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_titleController.text.characters.length}/60',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionTitle(label: '日期与时间', required: true),
                    const SizedBox(height: 14),
                    AppSelectionRow(
                      icon: Icons.calendar_today_outlined,
                      value: _formattedDateLabel(),
                      onTap: _pickDateOnly,
                    ),
                    Divider(height: 28, color: palette.outlineSoft),
                    AppSelectionRow(
                      icon: Icons.access_time_rounded,
                      value: _hasSpecificTime ? _formattedTimeText() : '全天',
                      onTap: _pickTimeOnly,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSectionHeaderRow(
                      title: '循环规则',
                      trailing: _repeatRule.label,
                    ),
                    if (_repeatRule != ReminderRepeatRule.none) ...[
                      const SizedBox(height: 12),
                      _RepeatSummaryBanner(label: _repeatRuleDescription()),
                      const SizedBox(height: 14),
                      AppDisclosureRow(
                        label: '循环截止',
                        value: _formatRepeatEndLabel(),
                        onTap: _pickRepeatEndDate,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final item in _visibleRepeatRules())
                          AppChoiceChip(
                            label: item.label,
                            selected: _repeatRule == item,
                            onTap: () {
                              setState(() {
                                _repeatRule = item;
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionTitle(label: '清单'),
                    const SizedBox(height: 14),
                    if (lists.isEmpty)
                      const _EmptyChoiceState(label: '暂无清单')
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final item in lists)
                            AppChoiceChip(
                              label: item.name,
                              selected: _selectedListId == item.id,
                              onTap: () {
                                setState(() {
                                  _selectedListId = item.id;
                                });
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionTitle(label: '分组'),
                    const SizedBox(height: 14),
                    if (groups.isEmpty)
                      const _EmptyChoiceState(label: '暂无分组')
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final item in groups)
                            AppChoiceChip(
                              label: item.name,
                              selected: _selectedGroupId == item.id,
                              onTap: () {
                                setState(() {
                                  _selectedGroupId = item.id;
                                });
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppSurfaceCard(
                onTap: widget.availableTags.isEmpty ? null : _openTagSelector,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionTitle(label: '标签'),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedTagIds.isEmpty
                          ? [
                              AppTagPill(
                                label: '未选择',
                                textColor: palette.textMuted,
                                backgroundColor: palette.surfaceContainerLow,
                              ),
                            ]
                          : _selectedTags().map((tag) {
                              return AppTagPill(
                                label: tag.name,
                                textColor: _tagColor(tag),
                                backgroundColor: _tagColor(
                                  tag,
                                ).withValues(alpha: 0.12),
                              );
                            }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSectionHeaderRow(
                      title: '提醒设置',
                      icon: Icons.notifications_none_rounded,
                      trailing: _notificationEnabled ? '准时提醒' : '提醒关闭',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '通知提醒',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: palette.onSurface,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '开启后，将在到达时间时提醒',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: palette.textMuted),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _notificationEnabled,
                          onChanged: _hasSpecificTime
                              ? (value) {
                                  setState(() {
                                    _notificationEnabled = value;
                                  });
                                }
                              : null,
                        ),
                      ],
                    ),
                    Divider(height: 28, color: palette.outlineSoft),
                    AppDisclosureRow(
                      label: '提前提醒',
                      value: _formatRemindBeforeLabel(),
                      onTap: _notificationEnabled
                          ? _pickRemindBeforeMinutes
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionTitle(label: '备注'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _noteController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 200,
                      decoration: InputDecoration(
                        hintText: '可选，填写备注信息...',
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintStyle: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(
                              color: palette.textMuted.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                      ),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.5,
                        color: palette.onSurface,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_noteController.text.characters.length}/200',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 16),
                AppSurfaceCard(
                  child: _CreateInfoSection(
                    createdAt: widget.initialReminder!.createdAt,
                    updatedAt: widget.initialReminder!.updatedAt,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final showKeyboardToolbar =
        Theme.of(context).platform == TargetPlatform.iOS &&
        MediaQuery.of(context).viewInsets.bottom > 0 &&
        (_hourFocusNode.hasFocus || _minuteFocusNode.hasFocus);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(color: palette.background),
        child: SafeArea(
          child: Stack(
            children: [
              formBody,
              if (showKeyboardToolbar)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _KeyboardAccessoryBar(
                    onNext: _hourFocusNode.hasFocus
                        ? () {
                            _normalizeHourInput();
                            _focusMinuteField();
                          }
                        : null,
                    onDone: () {
                      if (_minuteFocusNode.hasFocus) {
                        _normalizeMinuteInput();
                      } else if (_hourFocusNode.hasFocus) {
                        _normalizeHourInput();
                      }
                      _dismissKeyboard();
                    },
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 20,
                child: AppPrimaryBottomButton(label: '保存', onPressed: _submit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setSelectedDateTime(DateTime value, {required bool hasSpecificTime}) {
    _selectedDateTime = value;
    _hasSpecificTime = hasSpecificTime;
    _syncTimeControllers();
  }

  List<ReminderRepeatRule> _visibleRepeatRules() {
    return [
      ReminderRepeatRule.none,
      ReminderRepeatRule.daily,
      ReminderRepeatRule.weekly,
      ReminderRepeatRule.monthly,
      ReminderRepeatRule.yearly,
      ReminderRepeatRule.workday,
      ReminderRepeatRule.restday,
    ];
  }

  String _formattedDateLabel() {
    return DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(_selectedDateTime);
  }

  Future<void> _pickTimeOnly() async {
    final result = await showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TimePickerSheet(
        initialTime:
            _parseTime() ??
            TimeOfDay(
              hour: _selectedDateTime.hour,
              minute: _selectedDateTime.minute,
            ),
      ),
    );
    if (result == null) {
      return;
    }
    setState(() {
      _setSelectedDateTime(
        DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          result.hour,
          result.minute,
        ),
        hasSpecificTime: true,
      );
    });
  }

  Future<void> _openTagSelector() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TagSelectionSheet(
        tags: widget.availableTags,
        initialSelection: _selectedTagIds,
      ),
    );
    if (selected == null) {
      return;
    }
    setState(() {
      _selectedTagIds = selected;
    });
  }

  List<ReminderTag> _selectedTags() {
    return widget.availableTags
        .where((tag) => _selectedTagIds.contains(tag.id))
        .toList();
  }

  Color _tagColor(ReminderTag tag) => Color(tag.colorValue);

  String _repeatRuleDescription() {
    if (_repeatRule == ReminderRepeatRule.none) {
      return '不设置循环提醒';
    }
    final until = _repeatEndAt == null
        ? '长期有效'
        : DateFormat('yyyy年M月d日', 'zh_CN').format(_repeatEndAt!);
    return '${_repeatRule.label}，直到 $until 结束';
  }

  String _formatRepeatEndLabel() {
    if (_repeatEndAt == null) {
      return '不设置';
    }
    return DateFormat('yyyy年M月d日', 'zh_CN').format(_repeatEndAt!);
  }

  String _formatRemindBeforeLabel() {
    final value = _remindBeforeMinutes;
    if (!_notificationEnabled) {
      return '提醒关闭';
    }
    if (value == null || value <= 0) {
      return '准时提醒';
    }
    if (value % (24 * 60) == 0) {
      return '提前${value ~/ (24 * 60)}天';
    }
    if (value % 60 == 0) {
      return '提前${value ~/ 60}小时';
    }
    return '提前$value分钟';
  }

  Future<void> _pickRepeatEndDate() async {
    if (_repeatRule == ReminderRepeatRule.none) {
      return;
    }
    final selection = await showModalBottomSheet<_RepeatEndSelection>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _RepeatEndPickerSheet(
        initialDate: _repeatEndAt,
        minDate: DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
        ),
      ),
    );
    if (!mounted || selection == null) {
      return;
    }
    setState(() {
      _repeatEndAt = selection.value;
    });
  }

  Future<void> _pickRemindBeforeMinutes() async {
    final selected = await showModalBottomSheet<int?>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _ReminderAdvanceSheet(currentValue: _remindBeforeMinutes ?? 0),
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _remindBeforeMinutes = selected;
    });
  }

  void _syncTimeControllers() {
    if (_hasSpecificTime) {
      _hourController.text = _selectedDateTime.hour.toString().padLeft(2, '0');
      _minuteController.text = _selectedDateTime.minute.toString().padLeft(
        2,
        '0',
      );
    } else {
      _hourController.clear();
      _minuteController.clear();
    }
  }

  void _normalizeHourInput() {
    if (!_hasSpecificTime) {
      return;
    }
    final text = _hourController.text.trim();
    if (text.isEmpty) {
      return;
    }
    final value = int.tryParse(text);
    if (value == null || value < 0 || value > 23) {
      return;
    }
    final normalized = value.toString().padLeft(2, '0');
    if (_hourController.text != normalized) {
      _hourController.value = _hourController.value.copyWith(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _normalizeMinuteInput() {
    if (!_hasSpecificTime) {
      return;
    }
    final text = _minuteController.text.trim();
    if (text.isEmpty) {
      return;
    }
    final value = int.tryParse(text);
    if (value == null || value < 0 || value > 59) {
      return;
    }
    final normalized = value.toString().padLeft(2, '0');
    if (_minuteController.text != normalized) {
      _minuteController.value = _minuteController.value.copyWith(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      if (mounted) {
        setState(() {});
      }
    }
  }

  String _formattedTimeText() {
    final hour = _hourController.text.padLeft(2, '0');
    final minute = _minuteController.text.padLeft(2, '0');
    return '$hour:$minute';
  }

  TimeOfDay? _parseTime() {
    final hour = int.tryParse(_hourController.text.trim());
    final minute = int.tryParse(_minuteController.text.trim());
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _pickDateOnly() async {
    final selectedDate = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _DatePickerSheet(
        initialDate: _selectedDateTime,
        markedDateKeys: _buildMarkedDateKeys(),
      ),
    );
    if (selectedDate == null) {
      return;
    }

    setState(() {
      _setSelectedDateTime(
        DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          _hasSpecificTime ? _selectedDateTime.hour : 0,
          _hasSpecificTime ? _selectedDateTime.minute : 0,
        ),
        hasSpecificTime: _hasSpecificTime,
      );
    });
  }

  Set<String> _buildMarkedDateKeys() {
    final result = <String>{};
    for (final item in widget.existingReminders) {
      if (_isEditing && item.id == widget.initialReminder?.id) {
        continue;
      }
      result.add(_dateKey(item.dueAt.toLocal()));
    }
    result.add(_dateKey(_selectedDateTime));
    return result;
  }

  String _dateKey(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final selectedTime = _hasSpecificTime ? _parseTime() : null;
    if (_hasSpecificTime && selectedTime == null) {
      return;
    }

    final dueAt = _hasSpecificTime
        ? DateTime(
            _selectedDateTime.year,
            _selectedDateTime.month,
            _selectedDateTime.day,
            selectedTime!.hour,
            selectedTime.minute,
          )
        : DateTime(
            _selectedDateTime.year,
            _selectedDateTime.month,
            _selectedDateTime.day,
          );

    final now = DateTime.now();
    final initial = widget.initialReminder;
    final reminder = ReminderItem(
      id: initial?.id ?? 'reminder-${now.microsecondsSinceEpoch}',
      title: _titleController.text.trim(),
      note: !_noteEnabled || _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      dueAt: dueAt,
      isCompleted: initial?.isCompleted ?? false,
      createdAt: initial?.createdAt ?? now,
      updatedAt: now,
      listId: _selectedListId,
      groupId: _selectedGroupId,
      tagIds: _selectedTagIds.toList(),
      notificationEnabled: _hasSpecificTime && _notificationEnabled,
      repeatRule: _repeatRule,
      repeatEndAt: _repeatRule == ReminderRepeatRule.none ? null : _repeatEndAt,
      remindBeforeMinutes: _hasSpecificTime && _notificationEnabled
          ? (_remindBeforeMinutes ?? 0)
          : null,
    );

    Navigator.of(context).pop(ReminderFormResult.save(reminder));
  }

  void _deleteReminder() {
    final reminder = widget.initialReminder;
    if (reminder == null) {
      return;
    }
    Navigator.of(context).pop(ReminderFormResult.delete(reminder));
  }

  List<ReminderList> _sortedLists() {
    final lists = [...widget.availableLists];
    lists.sort((a, b) {
      final compare = a.sortOrder.compareTo(b.sortOrder);
      if (compare != 0) {
        return compare;
      }
      return a.name.compareTo(b.name);
    });
    return lists;
  }

  List<ReminderGroup> _sortedGroups() {
    final groups = [...widget.availableGroups];
    groups.sort((a, b) {
      final compare = a.sortOrder.compareTo(b.sortOrder);
      if (compare != 0) {
        return compare;
      }
      return a.name.compareTo(b.name);
    });
    return groups;
  }
}

class _FormNavBar extends StatelessWidget {
  const _FormNavBar({
    required this.isEditing,
    required this.onClose,
    required this.onSave,
    this.onDelete,
  });

  final bool isEditing;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Row(
      children: [
        IconButton(
          onPressed: onClose,
          icon: Icon(
            isEditing ? Icons.arrow_back_rounded : Icons.close_rounded,
            color: palette.onSurface,
          ),
        ),
        Expanded(
          child: Text(
            isEditing ? '编辑提醒' : '新增提醒',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.onSurface,
            ),
          ),
        ),
        if (onDelete != null)
          TextButton(
            onPressed: onDelete,
            style: TextButton.styleFrom(foregroundColor: palette.error),
            child: const Text(
              '删除',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        else
          const SizedBox(width: 64),
        const SizedBox(width: 8),
        SizedBox(
          height: 36,
          child: FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              backgroundColor: palette.primary,
              foregroundColor: palette.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '保存',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyChoiceState extends StatelessWidget {
  const _EmptyChoiceState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: palette.textMuted,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _RepeatSummaryBanner extends StatelessWidget {
  const _RepeatSummaryBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.successContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.onSurface.withValues(alpha: 0.75),
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.edit_outlined,
            size: 18,
            color: palette.onSurface.withValues(alpha: 0.78),
          ),
        ],
      ),
    );
  }
}

class _RepeatEndSelection {
  const _RepeatEndSelection.none() : value = null;

  const _RepeatEndSelection.date(this.value);

  final DateTime? value;
}

class _RepeatEndPickerSheet extends StatefulWidget {
  const _RepeatEndPickerSheet({required this.minDate, this.initialDate});

  final DateTime? initialDate;
  final DateTime minDate;

  @override
  State<_RepeatEndPickerSheet> createState() => _RepeatEndPickerSheetState();
}

class _RepeatEndPickerSheetState extends State<_RepeatEndPickerSheet> {
  late DateTime _selectedDate;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final fallback = widget.initialDate ?? widget.minDate;
    _selectedDate = _normalize(fallback);
    _enabled = widget.initialDate != null;
  }

  DateTime _normalize(DateTime value) {
    final normalized = DateTime(value.year, value.month, value.day);
    if (normalized.isBefore(widget.minDate)) {
      return widget.minDate;
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final label = DateFormat('yyyy年M月d日', 'zh_CN').format(_selectedDate);
    return AppSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '循环截止',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: palette.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppChoiceChip(
            label: '不设置',
            selected: !_enabled,
            onTap: () {
              setState(() {
                _enabled = false;
              });
            },
          ),
          const SizedBox(height: 12),
          AppDisclosureRow(
            label: '截止日期',
            value: label,
            onTap: () async {
              final picked = await showModalBottomSheet<DateTime>(
                context: context,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (context) => _DatePickerSheet(
                  initialDate: _selectedDate,
                  markedDateKeys: {_dateKey(_selectedDate)},
                ),
              );
              if (!mounted || picked == null) {
                return;
              }
              setState(() {
                _enabled = true;
                _selectedDate = _normalize(picked);
              });
            },
          ),
          const SizedBox(height: 10),
          Text(
            '设置后，循环将在该日期当天结束。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 20),
          AppPrimaryBottomButton(
            label: '确定',
            onPressed: () {
              Navigator.of(context).pop(
                _enabled
                    ? _RepeatEndSelection.date(_selectedDate)
                    : const _RepeatEndSelection.none(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _dateKey(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}

class _ReminderAdvanceSheet extends StatelessWidget {
  const _ReminderAdvanceSheet({required this.currentValue});

  final int currentValue;

  static const List<int> _options = [0, 5, 10, 30, 60, 24 * 60];

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return AppSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '提前提醒',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in _options)
                AppChoiceChip(
                  label: _label(option),
                  selected: currentValue == option,
                  onTap: () => Navigator.of(context).pop(option),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _label(int value) {
    if (value <= 0) {
      return '准时提醒';
    }
    if (value % (24 * 60) == 0) {
      return '提前${value ~/ (24 * 60)}天';
    }
    if (value % 60 == 0) {
      return '提前${value ~/ 60}小时';
    }
    return '提前$value分钟';
  }
}

class _CreateInfoSection extends StatelessWidget {
  const _CreateInfoSection({required this.createdAt, required this.updatedAt});

  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final formatter = DateFormat('yyyy-MM-dd HH:mm', 'zh_CN');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '创建信息',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: 14),
        AppInfoRow(label: '创建时间', value: formatter.format(createdAt.toLocal())),
        const SizedBox(height: 10),
        AppInfoRow(label: '最后更新', value: formatter.format(updatedAt.toLocal())),
      ],
    );
  }
}

class _KeyboardAccessoryBar extends StatelessWidget {
  const _KeyboardAccessoryBar({required this.onDone, this.onNext});

  final VoidCallback onDone;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Material(
      color: palette.surfaceContainerLow,
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.outline)),
          ),
          child: Row(
            children: [
              if (onNext != null)
                TextButton(onPressed: onNext, child: const Text('下一项')),
              const Spacer(),
              TextButton(onPressed: onDone, child: const Text('完成')),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagSelectionSheet extends StatefulWidget {
  const _TagSelectionSheet({
    required this.tags,
    required this.initialSelection,
  });

  final List<ReminderTag> tags;
  final Set<String> initialSelection;

  @override
  State<_TagSelectionSheet> createState() => _TagSelectionSheetState();
}

class _TagSelectionSheetState extends State<_TagSelectionSheet> {
  late final Set<String> _selected = {...widget.initialSelection};

  @override
  Widget build(BuildContext context) {
    return AppSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择标签',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: widget.tags.map((tag) {
              final selected = _selected.contains(tag.id);
              return AppChoiceChip(
                label: tag.name,
                selected: selected,
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selected.remove(tag.id);
                    } else {
                      _selected.add(tag.id);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          AppPrimaryBottomButton(
            label: '完成',
            onPressed: () => Navigator.of(context).pop(_selected),
          ),
        ],
      ),
    );
  }
}

class _DatePickerSheet extends StatefulWidget {
  const _DatePickerSheet({
    required this.initialDate,
    required this.markedDateKeys,
  });

  final DateTime initialDate;
  final Set<String> markedDateKeys;

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _visibleMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  void _changeMonth(int offset) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + offset,
      );
    });
  }

  Future<void> _pickVisibleMonth() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MonthPickerSheet(initialMonth: _visibleMonth),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _visibleMonth = DateTime(picked.year, picked.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final monthText = DateFormat('yyyy年M月', 'zh_CN').format(_visibleMonth);
    final selectedText = DateFormat(
      'yyyy年M月d日 EEEE',
      'zh_CN',
    ).format(_selectedDate);
    final days = _buildCalendarDays(_visibleMonth);
    return AppSheetContainer(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: palette.onSurface),
                ),
                Expanded(
                  child: Text(
                    '选择日期',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: palette.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_selectedDate),
                  style: TextButton.styleFrom(foregroundColor: palette.primary),
                  child: const Text(
                    '确定',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                _MonthArrowButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _changeMonth(-1),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _pickVisibleMonth,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          monthText,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: palette.onSurface,
                              ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: palette.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                _MonthArrowButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _changeMonth(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: const [
                _WeekdayCell(label: '日'),
                _WeekdayCell(label: '一'),
                _WeekdayCell(label: '二'),
                _WeekdayCell(label: '三'),
                _WeekdayCell(label: '四'),
                _WeekdayCell(label: '五'),
                _WeekdayCell(label: '六'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Column(
              children: [
                for (var row = 0; row < 6; row++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        for (var column = 0; column < 7; column++)
                          _DateCell(
                            data: days[(row * 7) + column],
                            isSelected: _isSameDate(
                              days[(row * 7) + column].date,
                              _selectedDate,
                            ),
                            onTap: () {
                              final date = days[(row * 7) + column].date;
                              setState(() {
                                _selectedDate = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  _selectedDate.hour,
                                  _selectedDate.minute,
                                );
                                _visibleMonth = DateTime(
                                  _selectedDate.year,
                                  _selectedDate.month,
                                );
                              });
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: palette.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () {
                      final now = DateTime.now();
                      setState(() {
                        _selectedDate = DateTime(
                          now.year,
                          now.month,
                          now.day,
                          _selectedDate.hour,
                          _selectedDate.minute,
                        );
                        _visibleMonth = DateTime(now.year, now.month);
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: palette.onSurface.withValues(alpha: 0.72),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '今天',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: palette.onSurface.withValues(
                                  alpha: 0.72,
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () async {
                      final time = await showModalBottomSheet<TimeOfDay>(
                        context: context,
                        useSafeArea: true,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (context) => _TimePickerSheet(
                          initialTime: TimeOfDay(
                            hour: _selectedDate.hour,
                            minute: _selectedDate.minute,
                          ),
                        ),
                      );
                      if (time == null) {
                        return;
                      }
                      setState(() {
                        _selectedDate = DateTime(
                          _selectedDate.year,
                          _selectedDate.month,
                          _selectedDate.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Text(
                          '选择时间',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: palette.onSurface.withValues(
                                  alpha: 0.72,
                                ),
                              ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: palette.textMuted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '已选择：$selectedText',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: palette.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<_CalendarDayData> _buildCalendarDays(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final offset = firstDay.weekday % 7;
    final start = firstDay.subtract(Duration(days: offset));
    return List<_CalendarDayData>.generate(42, (index) {
      final date = start.add(Duration(days: index));
      return _CalendarDayData(
        date: date,
        inCurrentMonth: date.month == month.month,
        hasMarker: widget.markedDateKeys.contains(_dateKey(date)),
      );
    });
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _dateKey(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}

class _TimePickerSheet extends StatefulWidget {
  const _TimePickerSheet({required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hour;
    _minute = widget.initialTime.minute;
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(TimeOfDay(hour: _hour, minute: _minute));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final selectedText =
        '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';
    return AppSheetContainer(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: palette.onSurface,
                  ),
                ),
                Expanded(
                  child: Text(
                    '选择时间',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: palette.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _save,
                  style: TextButton.styleFrom(foregroundColor: palette.primary),
                  child: const Text(
                    '确定',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 290,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            palette.surface,
                            palette.surface.withValues(alpha: 0.92),
                            palette.surface.withValues(alpha: 0.0),
                            palette.surface.withValues(alpha: 0.0),
                            palette.surface.withValues(alpha: 0.92),
                            palette.surface,
                          ],
                          stops: const [0.0, 0.14, 0.28, 0.72, 0.86, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 74,
                  right: 74,
                  child: Container(
                    height: 68,
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: palette.outline),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x050F172A),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 82,
                  right: 82,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: palette.outlineSoft),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 82,
                  right: 82,
                  bottom: (290 - 68) / 2,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: palette.outlineSoft),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Spacer(),
                    SizedBox(
                      width: 88,
                      child: CupertinoPicker.builder(
                        scrollController: _hourController,
                        itemExtent: 56,
                        selectionOverlay: const SizedBox.shrink(),
                        useMagnifier: false,
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _hour = index;
                          });
                        },
                        childCount: 24,
                        itemBuilder: (context, index) => _PickerValue(
                          label: index.toString().padLeft(2, '0'),
                          selected: index == _hour,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        ':',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: palette.primary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    SizedBox(
                      width: 88,
                      child: CupertinoPicker.builder(
                        scrollController: _minuteController,
                        itemExtent: 56,
                        selectionOverlay: const SizedBox.shrink(),
                        useMagnifier: false,
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _minute = index;
                          });
                        },
                        childCount: 60,
                        itemBuilder: (context, index) => _PickerValue(
                          label: index.toString().padLeft(2, '0'),
                          selected: index == _minute,
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _QuickTimeButton(
                    label: '现在',
                    onTap: () {
                      final now = DateTime.now();
                      setState(() {
                        _hour = now.hour;
                        _minute = now.minute;
                        _hourController.jumpToItem(_hour);
                        _minuteController.jumpToItem(_minute);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickTimeButton(
                    label: '+10分钟',
                    onTap: () => _shiftMinutes(10),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickTimeButton(
                    label: '+30分钟',
                    onTap: () => _shiftMinutes(30),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickTimeButton(
                    label: '+1小时',
                    onTap: () => _shiftMinutes(60),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '已选择：$selectedText',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: palette.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _shiftMinutes(int minutes) {
    final now = DateTime.now().add(Duration(minutes: minutes));
    setState(() {
      _hour = now.hour;
      _minute = now.minute;
      _hourController.jumpToItem(_hour);
      _minuteController.jumpToItem(_minute);
    });
  }
}

class _CalendarDayData {
  const _CalendarDayData({
    required this.date,
    required this.inCurrentMonth,
    required this.hasMarker,
  });

  final DateTime date;
  final bool inCurrentMonth;
  final bool hasMarker;
}

class _WeekdayCell extends StatelessWidget {
  const _WeekdayCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MonthArrowButton extends StatelessWidget {
  const _MonthArrowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: palette.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: palette.textMuted, size: 20),
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.data,
    required this.isSelected,
    required this.onTap,
  });

  final _CalendarDayData data;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final textColor = isSelected
        ? palette.onPrimary
        : data.inCurrentMonth
        ? palette.onSurface
        : palette.outline;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 56,
          child: Center(
            child: Container(
              width: 40,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? palette.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${data.date.day}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: textColor,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 6,
                    height: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? palette.onPrimary
                            : data.hasMarker && data.inCurrentMonth
                            ? palette.primary
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthPickerSheet extends StatefulWidget {
  const _MonthPickerSheet({required this.initialMonth});

  final DateTime initialMonth;

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late int _year;
  late int _month;
  late final FixedExtentScrollController _yearController;
  late final FixedExtentScrollController _monthController;

  static const _startYear = 2020;
  static const _endYear = 2035;

  @override
  void initState() {
    super.initState();
    _year = widget.initialMonth.year;
    _month = widget.initialMonth.month;
    _yearController = FixedExtentScrollController(
      initialItem: _year - _startYear,
    );
    _monthController = FixedExtentScrollController(initialItem: _month - 1);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return AppSheetContainer(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: palette.onSurface),
                ),
                Expanded(
                  child: Text(
                    '选择月份',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: palette.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(DateTime(_year, _month)),
                  style: TextButton.styleFrom(foregroundColor: palette.primary),
                  child: const Text(
                    '确定',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 56,
                  right: 56,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: palette.outline),
                        bottom: BorderSide(color: palette.outline),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker.builder(
                        scrollController: _yearController,
                        itemExtent: 52,
                        selectionOverlay: const SizedBox.shrink(),
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _year = _startYear + index;
                          });
                        },
                        childCount: _endYear - _startYear + 1,
                        itemBuilder: (context, index) => _PickerValue(
                          label: '${_startYear + index}年',
                          selected: (_startYear + index) == _year,
                        ),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker.builder(
                        scrollController: _monthController,
                        itemExtent: 52,
                        selectionOverlay: const SizedBox.shrink(),
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _month = index + 1;
                          });
                        },
                        childCount: 12,
                        itemBuilder: (context, index) => _PickerValue(
                          label: '${index + 1}月',
                          selected: (index + 1) == _month,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerValue extends StatelessWidget {
  const _PickerValue({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Center(
      child: Text(
        label,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: selected
              ? palette.primary
              : palette.textMuted.withValues(alpha: 0.75),
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _QuickTimeButton extends StatelessWidget {
  const _QuickTimeButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: palette.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
