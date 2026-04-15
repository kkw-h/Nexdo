import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../domain/entities/reminder_models.dart';

class ReminderFormResult {
  const ReminderFormResult(this.reminder);

  final ReminderItem reminder;
}

class ReminderFormPage extends StatefulWidget {
  const ReminderFormPage({
    super.key,
    required this.availableLists,
    required this.availableGroups,
    required this.availableTags,
    this.initialReminder,
  });

  final List<ReminderList> availableLists;
  final List<ReminderGroup> availableGroups;
  final List<ReminderTag> availableTags;
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
    _hourFocusNode.addListener(() {
      if (!_hourFocusNode.hasFocus) {
        _normalizeHourInput();
      }
    });
    _minuteFocusNode.addListener(() {
      if (!_minuteFocusNode.hasFocus) {
        _normalizeMinuteInput();
      }
    });
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

  @override
  Widget build(BuildContext context) {
    final lists = _sortedLists();
    final groups = _sortedGroups();
    final dateFormatter = DateFormat('M月d日 EEEE', 'zh_CN');
    final dateOnlyFormatter = DateFormat('M月d日', 'zh_CN');
    final weekdayFormatter = DateFormat('EEEE', 'zh_CN');
    final timeErrorText = _hasSpecificTime ? _validateTimeInput() : null;
    final summaryLabel = _hasSpecificTime
        ? '${dateFormatter.format(_selectedDateTime)} ${_formattedTimeText()}'
        : '${dateFormatter.format(_selectedDateTime)} · 全天';

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '编辑提醒' : '新建提醒')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: '提醒标题',
                        hintText: '比如：下午 3 点提交周报',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入提醒标题';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.schedule_rounded),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('提醒时间'),
                                      const SizedBox(height: 4),
                                      Text(
                                        summaryLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: const Color(0xFF60716B),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _DateTimeEditorCard(
                                    label: '日期',
                                    icon: Icons.calendar_month_rounded,
                                    onTap: _pickDateOnly,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          dateOnlyFormatter.format(
                                            _selectedDateTime,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          weekdayFormatter.format(
                                            _selectedDateTime,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF60716B),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _DateTimeEditorCard(
                                    label: '时间',
                                    icon: Icons.access_time_rounded,
                                    actionLabel: _hasSpecificTime ? '清除' : '设置',
                                    onActionPressed: _toggleTimeEditing,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: _hourController,
                                                focusNode: _hourFocusNode,
                                                enabled: _hasSpecificTime,
                                                keyboardType:
                                                    TextInputType.number,
                                                textInputAction:
                                                    TextInputAction.next,
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .digitsOnly,
                                                  LengthLimitingTextInputFormatter(
                                                    2,
                                                  ),
                                                ],
                                                onChanged: (value) {
                                                  if (!_hasSpecificTime) {
                                                    return;
                                                  }
                                                  if (value.length == 2) {
                                                    _minuteFocusNode
                                                        .requestFocus();
                                                  }
                                                  setState(() {});
                                                },
                                                onEditingComplete: () {
                                                  _normalizeHourInput();
                                                  _minuteFocusNode
                                                      .requestFocus();
                                                },
                                                decoration: InputDecoration(
                                                  isDense: true,
                                                  border: InputBorder.none,
                                                  hintText: _hasSpecificTime
                                                      ? '09'
                                                      : '--',
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                ),
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                validator: (_) =>
                                                    _validateTimeInput(),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              ':',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Focus(
                                                focusNode: _minuteFocusNode,
                                                onKeyEvent: (node, event) {
                                                  if (event is KeyDownEvent &&
                                                      event.logicalKey ==
                                                          LogicalKeyboardKey
                                                              .backspace &&
                                                      _minuteController
                                                          .text
                                                          .isEmpty) {
                                                    _hourFocusNode
                                                        .requestFocus();
                                                    return KeyEventResult
                                                        .handled;
                                                  }
                                                  return KeyEventResult.ignored;
                                                },
                                                child: TextFormField(
                                                  controller: _minuteController,
                                                  enabled: _hasSpecificTime,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  textInputAction:
                                                      TextInputAction.done,
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .digitsOnly,
                                                    LengthLimitingTextInputFormatter(
                                                      2,
                                                    ),
                                                  ],
                                                  onChanged: (_) {
                                                    if (_hasSpecificTime) {
                                                      setState(() {});
                                                    }
                                                  },
                                                  onEditingComplete: () {
                                                    _normalizeMinuteInput();
                                                    FocusScope.of(
                                                      context,
                                                    ).unfocus();
                                                  },
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    border: InputBorder.none,
                                                    hintText: _hasSpecificTime
                                                        ? '00'
                                                        : '--',
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headlineSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                  validator: (_) =>
                                                      _validateTimeInput(),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _hasSpecificTime
                                              ? '左侧输入小时，右侧输入分钟'
                                              : '留空表示仅日期，无具体时间',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF60716B),
                                              ),
                                        ),
                                        if (timeErrorText != null) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            timeErrorText,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ..._quickOptions().map(
                                  (option) => _QuickActionChip(
                                    label: option.label,
                                    onTap: () {
                                      setState(() {
                                        _setSelectedDateTime(
                                          option.value,
                                          hasSpecificTime: true,
                                        );
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_noteEnabled)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _noteEnabled = true;
                            });
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F7F5),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFCAD7D1),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.note_add_outlined),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '添加备注',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '补充说明、上下文或执行步骤',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: const Color(0xFF60716B),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_noteEnabled) ...[
                      Row(
                        children: [
                          Text(
                            '备注',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _noteEnabled = false;
                              });
                            },
                            child: const Text('收起'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _noteController,
                        decoration: const InputDecoration(
                          hintText: '补充说明、上下文或执行步骤',
                        ),
                        minLines: 3,
                        maxLines: 5,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _OptionSection(
                      title: '任务清单',
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: lists.map((item) {
                          return _SelectableChip(
                            label: item.name,
                            selected: _selectedListId == item.id,
                            onTap: () {
                              setState(() {
                                _selectedListId = item.id;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _OptionSection(
                      title: '分组',
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: groups.map((item) {
                          return _SelectableChip(
                            label: item.name,
                            selected: _selectedGroupId == item.id,
                            onTap: () {
                              setState(() {
                                _selectedGroupId = item.id;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _OptionSection(
                      title: '循环提醒',
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: ReminderRepeatRule.values.map((item) {
                          return _SelectableChip(
                            label: item.label,
                            selected: _repeatRule == item,
                            onTap: () {
                              setState(() {
                                _repeatRule = item;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '标签',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: widget.availableTags.map((tag) {
                        final selected = _selectedTagIds.contains(tag.id);
                        return FilterChip(
                          label: Text(tag.name),
                          selected: selected,
                          onSelected: (value) {
                            setState(() {
                              if (value) {
                                _selectedTagIds.add(tag.id);
                              } else {
                                _selectedTagIds.remove(tag.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile.adaptive(
                      value: _notificationEnabled,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开启本地通知'),
                      subtitle: Text(
                        _hasSpecificTime ? '到点后通过系统通知提醒' : '仅日期提醒不设置到点通知',
                      ),
                      onChanged: _hasSpecificTime
                          ? (value) {
                              setState(() {
                                _notificationEnabled = value;
                              });
                            }
                          : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submit,
                      child: Text(_isEditing ? '保存修改' : '创建提醒'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _setSelectedDateTime(DateTime value, {required bool hasSpecificTime}) {
    _selectedDateTime = value;
    _hasSpecificTime = hasSpecificTime;
    _syncTimeControllers();
  }

  void _toggleTimeEditing() {
    if (_hasSpecificTime) {
      setState(() {
        _notificationEnabled = false;
        _setSelectedDateTime(
          DateTime(
            _selectedDateTime.year,
            _selectedDateTime.month,
            _selectedDateTime.day,
          ),
          hasSpecificTime: false,
        );
      });
      return;
    }

    setState(() {
      final parsed = _parseTime();
      final nextTime = parsed ?? const TimeOfDay(hour: 9, minute: 0);
      _setSelectedDateTime(
        DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          nextTime.hour,
          nextTime.minute,
        ),
        hasSpecificTime: true,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _hourFocusNode.requestFocus();
      }
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

  String? _validateTimeInput() {
    if (!_hasSpecificTime) {
      return null;
    }
    if (_hourController.text.trim().isEmpty ||
        _minuteController.text.trim().isEmpty) {
      return '请输入小时和分钟';
    }
    if (_parseTime() == null) {
      return '请输入有效时间';
    }
    return null;
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
    final selectedDate = await showDatePicker(
      context: context,
      locale: const Locale('zh', 'CN'),
      initialDate: _selectedDateTime,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
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

  List<_QuickDateTimeOption> _quickOptions() {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    return [
      _QuickDateTimeOption(
        label: '稍后 30 分钟',
        value: now.add(const Duration(minutes: 30)),
      ),
      _QuickDateTimeOption(
        label: '今天下班前',
        value: DateTime(now.year, now.month, now.day, 18, 0),
      ),
      _QuickDateTimeOption(
        label: '今晚 20:00',
        value: DateTime(now.year, now.month, now.day, 20, 0),
      ),
      _QuickDateTimeOption(
        label: '明天上午 9:00',
        value: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0),
      ),
    ];
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
    );

    Navigator.of(context).pop(ReminderFormResult(reminder));
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

class _QuickDateTimeOption {
  const _QuickDateTimeOption({required this.label, required this.value});

  final String label;
  final DateTime value;
}

class _DateTimeEditorCard extends StatelessWidget {
  const _DateTimeEditorCard({
    required this.label,
    required this.icon,
    required this.child,
    this.actionLabel,
    this.onActionPressed,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onActionPressed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFFF6FAF7),
      borderRadius: BorderRadius.circular(3),
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: onTap,
        mouseCursor: onTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        splashColor: colorScheme.primary.withValues(alpha: 0.10),
        highlightColor: colorScheme.primary.withValues(alpha: 0.06),
        hoverColor: colorScheme.primary.withValues(alpha: 0.04),
        child: Container(
          height: 138,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFFD9E4DE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF60716B),
                      ),
                    ),
                  ),
                  if (actionLabel != null && onActionPressed != null)
                    TextButton(
                      onPressed: onActionPressed,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(52, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(actionLabel!),
                    )
                  else if (onTap != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: const Color(0xFF60716B),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: const Color(0xFFEAF2EE),
      side: BorderSide.none,
      labelStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

class _OptionSection extends StatelessWidget {
  const _OptionSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer : const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withAlpha(70)
                  : const Color(0xFFD9E4DE),
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: selected ? colorScheme.primary : const Color(0xFF4F6059),
            ),
          ),
        ),
      ),
    );
  }
}
