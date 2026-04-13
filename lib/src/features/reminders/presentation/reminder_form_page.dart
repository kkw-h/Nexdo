import 'package:flutter/material.dart';
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
  late DateTime _selectedDateTime;
  late String _selectedListId;
  late String _selectedGroupId;
  late Set<String> _selectedTagIds;
  late bool _notificationEnabled;
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
    _selectedDateTime =
        reminder?.dueAt ?? DateTime.now().add(const Duration(hours: 2));
    _selectedListId =
        reminder?.listId ?? (initialLists.isNotEmpty ? initialLists.first.id : '');
    _selectedGroupId =
        reminder?.groupId ?? (initialGroups.isNotEmpty ? initialGroups.first.id : '');
    _selectedTagIds = {...?reminder?.tagIds};
    _notificationEnabled = reminder?.notificationEnabled ?? true;
    _repeatRule = reminder?.repeatRule ?? ReminderRepeatRule.none;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lists = _sortedLists();
    final groups = _sortedGroups();
    final formatter = DateFormat('M月d日 EEEE HH:mm', 'zh_CN');
    final timeFormatter = DateFormat('HH:mm', 'zh_CN');
    final dayHint = _relativeDayLabel(_selectedDateTime);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '编辑提醒' : '新建提醒')),
      body: SafeArea(
        child: Padding(
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
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    hintText: '补充说明、上下文或执行步骤',
                  ),
                  minLines: 3,
                  maxLines: 5,
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('提醒时间'),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatter.format(_selectedDateTime),
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
                            FilledButton.tonalIcon(
                              onPressed: _pickDateTime,
                              icon: const Icon(Icons.edit_calendar_rounded),
                              label: const Text('调整'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _QuickActionChip(
                              label: dayHint,
                              onTap: _pickDateOnly,
                            ),
                            _QuickActionChip(
                              label: timeFormatter.format(_selectedDateTime),
                              onTap: _pickTimeOnly,
                            ),
                            ..._quickOptions().map(
                              (option) => _QuickActionChip(
                                label: option.label,
                                onTap: () {
                                  setState(() {
                                    _selectedDateTime = option.value;
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
                  subtitle: const Text('到点后通过系统通知提醒'),
                  onChanged: (value) {
                    setState(() {
                      _notificationEnabled = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submit,
                  child: Text(_isEditing ? '保存修改' : '创建提醒'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final selectedDate = await _showChineseDatePicker();
    if (selectedDate == null || !mounted) {
      return;
    }

    final selectedTime = await _showChineseTimePicker(
      TimeOfDay.fromDateTime(_selectedDateTime),
    );

    if (selectedTime == null) {
      return;
    }

    setState(() {
      _selectedDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  Future<void> _pickDateOnly() async {
    final selectedDate = await _showChineseDatePicker();
    if (selectedDate == null) {
      return;
    }

    setState(() {
      _selectedDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        _selectedDateTime.hour,
        _selectedDateTime.minute,
      );
    });
  }

  Future<void> _pickTimeOnly() async {
    final selectedTime = await _showChineseTimePicker(
      TimeOfDay.fromDateTime(_selectedDateTime),
    );

    if (selectedTime == null) {
      return;
    }

    setState(() {
      _selectedDateTime = DateTime(
        _selectedDateTime.year,
        _selectedDateTime.month,
        _selectedDateTime.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  Future<DateTime?> _showChineseDatePicker() async {
    final selectedDate = await showDatePicker(
      context: context,
      locale: const Locale('zh', 'CN'),
      initialDate: _selectedDateTime,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    return selectedDate;
  }

  Future<TimeOfDay?> _showChineseTimePicker(TimeOfDay initialTime) async {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: Localizations.override(
            context: context,
            locale: const Locale('zh', 'CN'),
            child: child,
          ),
        );
      },
    );
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

  String _relativeDayLabel(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final days = target.difference(today).inDays;

    if (days == 0) {
      return '今天';
    }
    if (days == 1) {
      return '明天';
    }
    if (days == 2) {
      return '后天';
    }
    return DateFormat('M月d日 EEE', 'zh_CN').format(dateTime);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final now = DateTime.now();
    final initial = widget.initialReminder;
    final reminder = ReminderItem(
      id: initial?.id ?? 'reminder-${now.microsecondsSinceEpoch}',
      title: _titleController.text.trim(),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      dueAt: _selectedDateTime,
      isCompleted: initial?.isCompleted ?? false,
      createdAt: initial?.createdAt ?? now,
      updatedAt: now,
      listId: _selectedListId,
      groupId: _selectedGroupId,
      tagIds: _selectedTagIds.toList(),
      notificationEnabled: _notificationEnabled,
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
