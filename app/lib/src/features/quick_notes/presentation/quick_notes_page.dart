import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_ui_primitives.dart';
import '../../auth/data/auth_repository.dart' show AuthException;
import '../data/quick_notes_repository.dart';
import '../domain/entities/quick_note.dart';

class QuickNotesPage extends StatefulWidget {
  const QuickNotesPage({
    super.key,
    required this.repository,
    this.diagnostics,
    this.onDiagnosticsPressed,
    this.onDiagnosticsChanged,
  });

  final QuickNotesRepository repository;
  final QuickNotesDiagnostics? diagnostics;
  final VoidCallback? onDiagnosticsPressed;
  final ValueChanged<QuickNotesDiagnostics>? onDiagnosticsChanged;

  @override
  State<QuickNotesPage> createState() => QuickNotesPageState();
}

class QuickNotesPageState extends State<QuickNotesPage> {
  final _player = AudioPlayer();
  final _recorder = AudioRecorder();
  final _speech = SpeechToText();
  final _uuid = const Uuid();

  List<QuickNote> _notes = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _loadError;
  String? _playingNoteId;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  bool _playbackActionInFlight = false;
  bool _diagnosing = false;
  bool? _microphonePermissionGranted;
  List<String> _inputDeviceLabels = const [];
  QuickNotesSortMode _sortMode = QuickNotesSortMode.newestFirst;
  final Map<String, GlobalKey> _noteMenuKeys = {};

  @override
  void initState() {
    super.initState();
    _loadNotes();
    unawaited(_refreshDiagnostics());
    _player.playerStateStream.listen((state) {
      if (!mounted || _playingNoteId == null) {
        return;
      }
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _playingNoteId = null;
          _playbackPosition = Duration.zero;
          _playbackDuration = Duration.zero;
        });
      }
    });
    _player.durationStream.listen((duration) {
      if (!mounted || _playingNoteId == null) {
        return;
      }
      if (duration == null || duration <= Duration.zero) {
        return;
      }
      setState(() {
        _playbackDuration = duration;
      });
    });
    _player.positionStream.listen((position) {
      if (!mounted || _playingNoteId == null) {
        return;
      }
      setState(() {
        _playbackPosition = position;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    unawaited(_recorder.dispose());
    unawaited(_speech.cancel());
    super.dispose();
  }

  Future<void> openTextComposer() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _QuickNoteTextSheet(),
    );
    if (text == null || text.trim().isEmpty) {
      return;
    }
    await _saveNote(
      QuickNote(
        id: _uuid.v4(),
        text: text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> openVoiceComposer() async {
    final draft = await showModalBottomSheet<_VoiceDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _QuickNoteVoiceSheet(repository: widget.repository),
    );
    if (draft == null) {
      return;
    }
    await _saveNote(
      QuickNote(
        id: _uuid.v4(),
        text: draft.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        audioPath: draft.audioPath,
        audioDurationMillis: draft.audioDurationMillis,
        waveformSamples: draft.waveformSamples,
      ),
    );
  }

  Future<void> refreshDiagnostics() {
    return _refreshDiagnostics();
  }

  Future<void> refreshNotes() {
    return _refreshNotes();
  }

  Future<void> _saveNote(QuickNote note) async {
    try {
      final updated = await widget.repository.createNote(
        content: note.text,
        audioPath: note.audioPath,
        audioDurationMillis: note.audioDurationMillis,
        waveformSamples: note.waveformSamples,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = updated;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('闪念已同步到云端')));
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _loadNotes() async {
    try {
      final notes = await widget.repository.fetchNotes(forceRefresh: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = notes;
        _loading = false;
        _loadError = null;
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error.message;
      });
    }
  }

  Future<void> _refreshNotes() async {
    if (_refreshing) {
      return;
    }
    setState(() {
      _refreshing = true;
    });
    try {
      final notes = await widget.repository.refreshNotes();
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = notes;
        _loading = false;
        _loadError = null;
      });
      await _refreshDiagnostics();
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _refreshDiagnostics() async {
    if (_diagnosing) {
      return;
    }
    setState(() {
      _diagnosing = true;
    });
    try {
      final microphoneGranted = await _recorder.hasPermission(request: false);
      final devices = microphoneGranted
          ? await _recorder.listInputDevices()
          : const <InputDevice>[];
      final speechReady = await _speech.initialize();
      if (!mounted) {
        return;
      }
      setState(() {
        _microphonePermissionGranted = microphoneGranted;
        _inputDeviceLabels = devices
            .map((device) => device.label.trim())
            .where((label) => label.isNotEmpty)
            .toList();
      });
      widget.onDiagnosticsChanged?.call(
        QuickNotesDiagnostics(
          microphonePermissionGranted: microphoneGranted,
          speechAvailable: speechReady,
          inputDeviceLabels: _inputDeviceLabels,
          diagnosing: false,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      widget.onDiagnosticsChanged?.call(
        QuickNotesDiagnostics(
          microphonePermissionGranted: _microphonePermissionGranted,
          speechAvailable: false,
          inputDeviceLabels: _inputDeviceLabels,
          diagnosing: false,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _diagnosing = false;
        });
      }
    }
  }

  Future<void> _deleteNote(QuickNote note) async {
    try {
      final updated = await widget.repository.deleteNote(note.id);
      if (_playingNoteId == note.id) {
        await _stopPlayback(resetState: false);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = updated;
        _playingNoteId = null;
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _editNote(QuickNote note) async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _QuickNoteTextSheet(
        title: note.text.trim().isEmpty ? '编辑语音闪念文案' : '编辑闪念',
        initialText: note.text,
        actionLabel: '保存',
      ),
    );
    if (text == null) {
      return;
    }
    final trimmed = text.trim();
    if (trimmed == note.text.trim()) {
      return;
    }
    try {
      final updated = await widget.repository.updateNote(
        id: note.id,
        content: trimmed,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = updated;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('闪念已更新')));
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _showSortMenu(BuildContext context) async {
    final palette = AppThemeScope.of(context).palette;
    final textTheme = Theme.of(context).textTheme;
    final selected = await showMenu<QuickNotesSortMode>(
      context: context,
      position: const RelativeRect.fromLTRB(0, 220, 16, 0),
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      constraints: const BoxConstraints(minWidth: 196),
      items: QuickNotesSortMode.values
          .map(
            (item) => PopupMenuItem<QuickNotesSortMode>(
              value: item,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: item == _sortMode
                      ? palette.primary.withValues(alpha: 0.07)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      item.icon,
                      size: 18,
                      color: item == _sortMode
                          ? palette.primary
                          : palette.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.label,
                        style: textTheme.bodyMedium?.copyWith(
                          color: item == _sortMode
                              ? palette.primary
                              : palette.onSurface,
                          fontWeight: item == _sortMode
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                    if (item == _sortMode)
                      Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: palette.primary,
                      ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
    if (!mounted || selected == null || selected == _sortMode) {
      return;
    }
    setState(() {
      _sortMode = selected;
    });
  }

  Future<void> _showNoteActionMenu(BuildContext context, QuickNote note) async {
    final anchorKey = _noteMenuKeys.putIfAbsent(note.id, GlobalKey.new);
    final anchorContext = anchorKey.currentContext;
    if (anchorContext == null) {
      return;
    }
    final palette = AppThemeScope.of(context).palette;
    final textTheme = Theme.of(context).textTheme;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final renderBox = anchorContext.findRenderObject() as RenderBox?;
    if (overlay == null || renderBox == null) {
      return;
    }
    final origin = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = RelativeRect.fromLTRB(
      origin.dx - 136,
      origin.dy + renderBox.size.height + 8,
      overlay.size.width - origin.dx - renderBox.size.width,
      overlay.size.height - origin.dy,
    );

    final selected = await showMenu<String>(
      context: context,
      position: rect,
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      constraints: const BoxConstraints(minWidth: 168),
      items: [
        PopupMenuItem<String>(
          value: 'edit',
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: AppPopupMenuRow(
            icon: Icons.edit_outlined,
            label: '编辑',
            textStyle: textTheme.bodyMedium?.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: AppPopupMenuRow(
            icon: Icons.delete_outline_rounded,
            label: '删除',
            iconColor: const Color(0xFFEF4444),
            textStyle: textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFEF4444),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
    if (!mounted || selected == null) {
      return;
    }
    if (selected == 'edit') {
      await _editNote(note);
      return;
    }
    if (selected == 'delete') {
      await _deleteNote(note);
    }
  }

  Future<void> _togglePlayback(QuickNote note) async {
    if (_playbackActionInFlight) {
      return;
    }
    _playbackActionInFlight = true;
    try {
      if (_playingNoteId == note.id) {
        await _stopPlayback();
        return;
      }
      if (_playingNoteId != null) {
        await _stopPlayback();
      }
      final path = await widget.repository.ensurePlayableAudioPath(note);
      await _player.setFilePath(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _playingNoteId = note.id;
        _playbackPosition = Duration.zero;
        _playbackDuration = note.audioDurationMillis == null
            ? Duration.zero
            : Duration(milliseconds: note.audioDurationMillis!);
      });
      unawaited(_player.play());
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      _playbackActionInFlight = false;
    }
  }

  Future<void> _stopPlayback({bool resetState = true}) async {
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted || !resetState) {
      return;
    }
    setState(() {
      _playingNoteId = null;
      _playbackPosition = Duration.zero;
      _playbackDuration = Duration.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderedNotes = _sortNotes(_notes);
    final noteCount = orderedNotes.length;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month);
    final todayCount = _notes
        .where((note) => note.createdAt.toLocal().isAfter(todayStart))
        .length;
    final weekCount = _notes
        .where((note) => note.createdAt.toLocal().isAfter(weekStart))
        .length;
    final monthCount = _notes
        .where((note) => note.createdAt.toLocal().isAfter(monthStart))
        .length;
    return RefreshIndicator(
      onRefresh: _refreshNotes,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(
            '闪念',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppThemeScope.of(context).palette.onSurface,
            ),
          ),
          const SizedBox(height: 22),
          _QuickNotesStatsCard(
            todayCount: todayCount,
            weekCount: weekCount,
            monthCount: monthCount,
            noteCount: noteCount,
          ),
          const SizedBox(height: 12),
          _QuickNotesDiagnosticsCard(
            diagnostics: widget.diagnostics,
            onDiagnosticsPressed: widget.onDiagnosticsPressed,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                '全部闪念',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppThemeScope.of(context).palette.onSurface,
                ),
              ),
              const Spacer(),
              AppSortTriggerButton(
                leadingIcon: _refreshing
                    ? Icons.sync_rounded
                    : Icons.swap_vert_rounded,
                label: _sortMode.label,
                onTap: () => _showSortMenu(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const _QuickNotesLoadingState()
          else if (_loadError != null)
            _QuickNotesErrorState(message: _loadError!, onRetry: _refreshNotes)
          else if (_notes.isEmpty)
            const _QuickNotesEmptyState()
          else
            ...orderedNotes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _QuickNoteCard(
                  key: ValueKey(note.id),
                  note: note,
                  isPlaying: _playingNoteId == note.id,
                  playbackPosition: _playingNoteId == note.id
                      ? _playbackPosition
                      : Duration.zero,
                  playbackDuration: _playingNoteId == note.id
                      ? _playbackDuration
                      : Duration.zero,
                  onPlay: note.hasAudio ? () => _togglePlayback(note) : null,
                  onEdit: () => _editNote(note),
                  onDelete: () => _deleteNote(note),
                  onOpenMenu: () => _showNoteActionMenu(context, note),
                  menuAnchorKey: _noteMenuKeys.putIfAbsent(
                    note.id,
                    GlobalKey.new,
                  ),
                ),
              ),
            ),
          if (!_loading && _loadError == null && _notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                '没有更多了',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppThemeScope.of(context).palette.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  List<QuickNote> _sortNotes(List<QuickNote> source) {
    final notes = [...source];
    switch (_sortMode) {
      case QuickNotesSortMode.newestFirst:
        notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case QuickNotesSortMode.oldestFirst:
        notes.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case QuickNotesSortMode.updatedRecently:
        notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return notes;
  }
}

enum QuickNotesSortMode {
  newestFirst('最新创建', Icons.schedule_rounded),
  oldestFirst('最早创建', Icons.history_toggle_off_rounded),
  updatedRecently('最近更新', Icons.update_rounded);

  const QuickNotesSortMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _QuickNoteTextSheet extends StatefulWidget {
  const _QuickNoteTextSheet({
    this.title = '新增闪念',
    this.initialText = '',
    this.actionLabel = '保存',
  });

  final String title;
  final String initialText;
  final String actionLabel;

  @override
  State<_QuickNoteTextSheet> createState() => _QuickNoteTextSheetState();
}

class _QuickNoteTextSheetState extends State<_QuickNoteTextSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
      child: AppSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 5,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: '输入你的想法、待办或灵感',
                filled: true,
                fillColor: AppThemeScope.of(context).palette.outlineSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppThemeScope.of(context).palette.primary,
                    width: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_controller.text),
                  child: Text(widget.actionLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickNoteVoiceSheet extends StatefulWidget {
  const _QuickNoteVoiceSheet({required this.repository});

  final QuickNotesRepository repository;

  @override
  State<_QuickNoteVoiceSheet> createState() => _QuickNoteVoiceSheetState();
}

class _QuickNoteVoiceSheetState extends State<_QuickNoteVoiceSheet> {
  final _recorder = AudioRecorder();
  final _speech = SpeechToText();
  final _textController = TextEditingController();

  StreamSubscription<Amplitude>? _amplitudeSubscription;
  final List<double> _waveformSamples = [0.08, 0.12, 0.18, 0.1, 0.06];
  final List<double> _recordedWaveformSamples = [];

  bool _starting = true;
  bool _isRecording = false;
  bool _isPaused = false;
  String? _audioPath;
  int? _audioDurationMillis;
  DateTime? _recordStartedAt;
  Duration _pausedDuration = Duration.zero;
  DateTime? _pausedAt;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    unawaited(_startRecording());
  }

  @override
  void dispose() {
    unawaited(_amplitudeSubscription?.cancel());
    unawaited(_recorder.dispose());
    unawaited(_speech.cancel());
    _textController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        throw const _QuickNoteException('未获得麦克风权限，请在系统设置中允许 Nexdo 访问麦克风和语音识别。');
      }

      final inputDevices = await _recorder.listInputDevices();
      if (inputDevices.isEmpty) {
        throw const _QuickNoteException(
          '未检测到可用麦克风输入设备，请先在“系统设置 -> 声音 -> 输入”中连接并选择可用麦克风。',
        );
      }

      final speechAvailable = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );

      final directory = await widget.repository.ensureAudioDirectory();
      final fileName =
          'quick-note-${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${directory.path}/$fileName';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((amplitude) {
            final normalized = _normalizeAmplitude(amplitude.current);
            if (!mounted || _isPaused) {
              return;
            }
            setState(() {
              _waveformSamples.add(normalized);
              if (_waveformSamples.length > 32) {
                _waveformSamples.removeAt(0);
              }
            });
            _recordedWaveformSamples.add(normalized);
          });

      if (speechAvailable) {
        await _speech.listen(
          onResult: _handleSpeechResult,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 5),
          localeId: 'zh_CN',
          listenOptions: SpeechListenOptions(
            partialResults: true,
            cancelOnError: false,
            listenMode: ListenMode.dictation,
          ),
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _starting = false;
        _isRecording = true;
        _audioPath = path;
        _recordStartedAt = DateTime.now();
        _statusText = speechAvailable ? '正在录音并识别语音' : '正在录音，当前设备不支持语音转写';
      });
    } on _QuickNoteException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _starting = false;
        _statusText = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _starting = false;
        _statusText = '开始录音失败，请检查权限和默认输入设备。';
      });
    }
  }

  Future<void> _pauseOrResume() async {
    if (_starting || !_isRecording) {
      return;
    }
    if (_isPaused) {
      await _recorder.resume();
      if (_pausedAt != null) {
        _pausedDuration += DateTime.now().difference(_pausedAt!);
      }
      _pausedAt = null;
      if (_speech.isAvailable && !_speech.isListening) {
        await _speech.listen(
          onResult: _handleSpeechResult,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 5),
          localeId: 'zh_CN',
          listenOptions: SpeechListenOptions(
            partialResults: true,
            cancelOnError: false,
            listenMode: ListenMode.dictation,
          ),
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isPaused = false;
        _statusText = '已继续录音';
      });
      return;
    }

    await _recorder.pause();
    if (_speech.isListening) {
      await _speech.stop();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isPaused = true;
      _pausedAt = DateTime.now();
      _statusText = '录音已暂停';
    });
  }

  Future<void> _cancelRecording() async {
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    try {
      await _recorder.cancel();
    } catch (_) {
      final path = _audioPath;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
    if (_speech.isListening) {
      await _speech.cancel();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _finishAndSave() async {
    if (_starting || !_isRecording) {
      return;
    }
    final stoppedPath = await _recorder.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    if (_speech.isListening) {
      await _speech.stop();
    }
    final effectiveDuration = _calculateDurationMillis();
    final text = _textController.text.trim();
    final audioPath = stoppedPath ?? _audioPath;
    if (audioPath != null && audioPath.isNotEmpty) {
      final normalizedPath = audioPath.startsWith('file://')
          ? Uri.parse(audioPath).toFilePath()
          : audioPath;
      final file = File(normalizedPath);
      if (!file.existsSync()) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('录音文件生成失败，请重新录制')));
        return;
      }
    }
    if ((text.isEmpty) && (audioPath == null || audioPath.isEmpty)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先录音或等待识别文字')));
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(
      _VoiceDraft(
        text: text,
        audioPath: audioPath,
        audioDurationMillis: effectiveDuration,
        waveformSamples: _compressWaveformSamples(_recordedWaveformSamples),
      ),
    );
  }

  int? _calculateDurationMillis() {
    final startedAt = _recordStartedAt;
    if (startedAt == null) {
      return _audioDurationMillis;
    }
    final end = _isPaused && _pausedAt != null ? _pausedAt! : DateTime.now();
    return end.difference(startedAt).inMilliseconds -
        _pausedDuration.inMilliseconds;
  }

  void _handleSpeechStatus(String status) {
    if (!mounted || !_isRecording) {
      return;
    }
    setState(() {
      if (status == 'listening') {
        _statusText = '正在识别语音';
      } else if (status == 'notListening' && !_isPaused) {
        _statusText = '录音仍在继续';
      }
    });
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _statusText = '语音识别暂不可用，仍会保留录音文件';
    });
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    _textController.value = _textController.value.copyWith(
      text: result.recognizedWords,
      selection: TextSelection.collapsed(offset: result.recognizedWords.length),
      composing: TextRange.empty,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _statusText = result.finalResult ? '识别完成，可直接保存' : '正在转写语音';
    });
  }

  double _normalizeAmplitude(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.08;
    }
    final clamped = value.clamp(-45.0, 0.0);
    final normalized = (clamped + 45.0) / 45.0;
    return math.max(0.08, normalized.toDouble());
  }

  List<double> _compressWaveformSamples(List<double> input) {
    if (input.isEmpty) {
      return const [];
    }
    const targetCount = 48;
    if (input.length <= targetCount) {
      return input
          .map((value) => double.parse(value.toStringAsFixed(3)))
          .toList();
    }

    final result = <double>[];
    final bucketSize = input.length / targetCount;
    for (var index = 0; index < targetCount; index++) {
      final start = (index * bucketSize).floor();
      final end = math.min(input.length, ((index + 1) * bucketSize).ceil());
      final segment = input.sublist(start, math.max(start + 1, end));
      final average =
          segment.reduce((sum, value) => sum + value) / segment.length;
      result.add(double.parse(average.toStringAsFixed(3)));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final durationLabel = _formatDuration(
      Duration(milliseconds: _calculateDurationMillis() ?? 0),
    );
    final pauseLabel = _isPaused ? '继续' : '暂停';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: _cancelRecording,
                      child: Text(
                        '取消',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '语音输入',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: palette.onSurface,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _starting ? null : _finishAndSave,
                      child: Text(
                        '完成',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: palette.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(minHeight: 108),
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: palette.outlineSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _textController,
                    maxLines: 4,
                    minLines: 4,
                    decoration: const InputDecoration.collapsed(
                      hintText: '识别文字将显示在这里...',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  height: 148,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: _WaveformView(
                            samples: _waveformSamples,
                            color: const Color(0xFF5B8DFF),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          durationLabel,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: palette.textMuted,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _statusText ?? (_starting ? '正在准备录音...' : '按住按钮开始说话'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _VoiceSheetAction(
                        label: '取消',
                        onTap: _cancelRecording,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF3F4F6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: palette.textMuted,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _VoiceSheetAction(
                        label: pauseLabel,
                        onTap: _starting ? null : _pauseOrResume,
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            color: palette.primary,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x3310B981),
                                blurRadius: 20,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isPaused ? Icons.mic_rounded : Icons.pause_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _VoiceSheetAction(
                        label: '完成',
                        onTap: _starting ? null : _finishAndSave,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF3F4F6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            color: palette.primary,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _WaveformView extends StatelessWidget {
  const _WaveformView({
    required this.samples,
    this.color = const Color(0xFF6DF7C1),
  });

  final List<double> samples;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bars = _compressToBars(samples.isEmpty ? [0.1] : samples);
        return Align(
          alignment: Alignment.center,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < bars.length; i++) ...[
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 3,
                      height: math.max(
                        6.0,
                        (bars[i] * (constraints.maxHeight * 0.72)) + 6,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                if (i != bars.length - 1) const SizedBox(width: 2),
              ],
            ],
          ),
        );
      },
    );
  }

  List<double> _compressToBars(List<double> input) {
    const targetCount = 42;
    if (input.length == targetCount) {
      return input;
    }
    if (input.length < targetCount) {
      return List<double>.generate(targetCount, (index) {
        final mappedIndex = (index * input.length / targetCount).floor();
        return input[mappedIndex.clamp(0, input.length - 1)];
      });
    }
    final result = <double>[];
    final bucketSize = input.length / targetCount;
    for (var index = 0; index < targetCount; index++) {
      final start = (index * bucketSize).floor();
      final end = math.min(input.length, ((index + 1) * bucketSize).ceil());
      final segment = input.sublist(start, math.max(start + 1, end));
      final average =
          segment.reduce((sum, value) => sum + value) / segment.length;
      result.add(average.clamp(0.08, 1.0).toDouble());
    }
    return result;
  }
}

class _VoiceSheetAction extends StatelessWidget {
  const _VoiceSheetAction({
    required this.label,
    required this.child,
    this.onTap,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(opacity: onTap == null ? 0.45 : 1, child: child),
            const SizedBox(height: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickNotesStatsCard extends StatelessWidget {
  const _QuickNotesStatsCard({
    required this.todayCount,
    required this.weekCount,
    required this.monthCount,
    required this.noteCount,
  });

  final int todayCount;
  final int weekCount;
  final int monthCount;
  final int noteCount;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.successContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: AppSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: _QuickNotesStatItem(label: '今日记录', value: todayCount),
            ),
            Expanded(
              child: _QuickNotesStatItem(label: '本周记录', value: weekCount),
            ),
            Expanded(
              child: _QuickNotesStatItem(label: '本月记录', value: monthCount),
            ),
            Expanded(
              child: _QuickNotesStatItem(label: '累计记录', value: noteCount),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickNotesStatItem extends StatelessWidget {
  const _QuickNotesStatItem({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w900,
            ),
            children: [
              TextSpan(text: '$value'),
              TextSpan(
                text: ' 条',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickNotesDiagnosticsCard extends StatelessWidget {
  const _QuickNotesDiagnosticsCard({
    required this.diagnostics,
    required this.onDiagnosticsPressed,
  });

  final QuickNotesDiagnostics? diagnostics;
  final VoidCallback? onDiagnosticsPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final data = diagnostics;
    final isDiagnosing = data?.diagnosing ?? false;
    final hasMic = data?.microphonePermissionGranted == true;
    final hasSpeech = data?.speechAvailable == true;
    final allHealthy = hasMic && hasSpeech;
    final iconColor = allHealthy
        ? const Color(0xFF22C07B)
        : const Color(0xFFF59E0B);
    final subtitle = switch (data) {
      null => '检查麦克风权限及识别服务状态',
      _ when isDiagnosing => '正在检测麦克风权限及识别服务状态',
      _ when allHealthy => '检查麦克风权限及识别服务状态',
      _ => '检测到录音或识别服务异常，点击查看详情',
    };

    return AppSurfaceCard(
      onTap: onDiagnosticsPressed,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.successContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              isDiagnosing
                  ? Icons.graphic_eq_rounded
                  : Icons.multitrack_audio_rounded,
              color: iconColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '录音权限与诊断',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.chevron_right_rounded, color: palette.textMuted, size: 24),
        ],
      ),
    );
  }
}

class _QuickNoteCard extends StatelessWidget {
  const _QuickNoteCard({
    super.key,
    required this.note,
    required this.isPlaying,
    required this.playbackPosition,
    required this.playbackDuration,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenMenu,
    required this.menuAnchorKey,
    this.onPlay,
  });

  final QuickNote note;
  final bool isPlaying;
  final Duration playbackPosition;
  final Duration playbackDuration;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onOpenMenu;
  final GlobalKey menuAnchorKey;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final createdAt = note.createdAt.toLocal();
    final timeText = DateFormat('HH:mm', 'zh_CN').format(createdAt);
    final dateText = _buildDateText(createdAt);
    final totalDuration = playbackDuration > Duration.zero
        ? playbackDuration
        : Duration(milliseconds: note.audioDurationMillis ?? 0);
    final progress = totalDuration.inMilliseconds <= 0
        ? 0.0
        : (playbackPosition.inMilliseconds / totalDuration.inMilliseconds)
              .clamp(0, 1)
              .toDouble();
    final hasAudio = note.hasAudio;

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: hasAudio
                    ? GestureDetector(
                        onTap: onPlay,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: palette.successContainer.withValues(
                              alpha: 0.45,
                            ),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: palette.primary,
                            size: 24,
                          ),
                        ),
                      )
                    : Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(left: 4, top: 12),
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C07B),
                          shape: BoxShape.circle,
                        ),
                      ),
              ),
              SizedBox(width: hasAudio ? 12 : 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _buildTitle(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: palette.onSurface,
                              fontWeight: FontWeight.w900,
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            timeText,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: palette.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            dateText,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: palette.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          _QuickNoteTypeChip(hasAudio: hasAudio),
                          if (hasAudio)
                            _QuickNoteDurationChip(duration: totalDuration),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Icon(
                    Icons.star_border_rounded,
                    size: 22,
                    color: palette.textMuted,
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    key: menuAnchorKey,
                    onTap: onOpenMenu,
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 22,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: hasAudio && isPlaying
                ? Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    decoration: BoxDecoration(
                      color: palette.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: onPlay,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: palette.successContainer.withValues(
                                    alpha: 0.45,
                                  ),
                                  borderRadius: BorderRadius.circular(17),
                                ),
                                child: Icon(
                                  Icons.pause_rounded,
                                  color: palette.primary,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _AudioWaveformStrip(
                                samples: note.waveformSamples,
                                progress: progress,
                                active: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              _formatDuration(playbackPosition),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: palette.textMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              _formatDuration(totalDuration),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: palette.textMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _buildTitle() {
    final text = note.text.trim();
    if (text.isNotEmpty) {
      return text;
    }
    return '仅保存了语音记录';
  }

  String _buildDateText(DateTime createdAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final days = target.difference(today).inDays;
    if (days == 0) {
      return '今天';
    }
    if (days == -1) {
      return '昨天';
    }
    return DateFormat('M月d日', 'zh_CN').format(createdAt);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _QuickNoteTypeChip extends StatelessWidget {
  const _QuickNoteTypeChip({required this.hasAudio});

  final bool hasAudio;

  @override
  Widget build(BuildContext context) {
    return AppInlineChip(
      label: hasAudio ? '语音' : '文本',
      textColor: Color(0xFF22A466),
      backgroundColor: Color(0xFFE8F8EF),
    );
  }
}

class _QuickNoteDurationChip extends StatelessWidget {
  const _QuickNoteDurationChip({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final text = '$minutes:${seconds.toString().padLeft(2, '0')}';
    return AppInlineChip(
      label: text,
      textColor: const Color(0xFF8A97A7),
      backgroundColor: const Color(0xFFF0F4F7),
    );
  }
}

class _AudioWaveformStrip extends StatelessWidget {
  const _AudioWaveformStrip({
    required this.samples,
    required this.progress,
    required this.active,
  });

  final List<double>? samples;
  final double progress;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bars = _normalizedBars(samples);
    return SizedBox(
      height: 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < bars.length; index++) ...[
            if (index > 0) const SizedBox(width: 2),
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  height: 4 + (bars[index] * 14),
                  decoration: BoxDecoration(
                    color: _barColor(context, (index + 1) / bars.length),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<double> _normalizedBars(List<double>? rawSamples) {
    if (rawSamples == null || rawSamples.isEmpty) {
      return List<double>.filled(36, 0.2);
    }
    const targetCount = 36;
    final samples = rawSamples
        .map(
          (value) => value.isFinite ? value.clamp(0.08, 1.0).toDouble() : 0.08,
        )
        .toList();
    if (samples.length == targetCount) {
      return samples;
    }
    if (samples.length < targetCount) {
      return List<double>.generate(targetCount, (index) {
        final mappedIndex = (index * samples.length / targetCount).floor();
        return samples[mappedIndex.clamp(0, samples.length - 1)];
      });
    }
    final result = <double>[];
    final bucketSize = samples.length / targetCount;
    for (var index = 0; index < targetCount; index++) {
      final start = (index * bucketSize).floor();
      final end = math.min(samples.length, ((index + 1) * bucketSize).ceil());
      final segment = samples.sublist(start, math.max(start + 1, end));
      result.add(segment.reduce(math.max));
    }
    return result;
  }

  Color _barColor(BuildContext context, double ratio) {
    final played = ratio <= progress.clamp(0.0, 1.0);
    if (played) {
      return const Color(0xFF79A7FF);
    }
    return active ? const Color(0xFFC8D8FF) : const Color(0xFFDCE7FF);
  }
}

class _QuickNotesEmptyState extends StatelessWidget {
  const _QuickNotesEmptyState();

  @override
  Widget build(BuildContext context) {
    return const AppStateEmptyCard(
      icon: Icons.bolt_rounded,
      title: '还没有闪念',
      subtitle: '点击右下角按钮输入文字，或长按按钮直接开始语音记录。',
    );
  }
}

class _QuickNotesErrorState extends StatelessWidget {
  const _QuickNotesErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return AppStateErrorCard(
      title: '闪念加载失败',
      message: message,
      actionLabel: '重新加载',
      onPressed: onRetry,
    );
  }
}

class _QuickNotesLoadingState extends StatelessWidget {
  const _QuickNotesLoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: const [
          _QuickNoteSkeletonCard(),
          SizedBox(height: 12),
          _QuickNoteSkeletonCard(),
          SizedBox(height: 12),
          _QuickNoteSkeletonCard(),
        ],
      ),
    );
  }
}

class _QuickNoteSkeletonCard extends StatelessWidget {
  const _QuickNoteSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QuickNoteSkeletonBar(widthFactor: 0.24, height: 14),
          SizedBox(height: 16),
          _QuickNoteSkeletonBar(widthFactor: 0.78, height: 18),
          SizedBox(height: 10),
          _QuickNoteSkeletonBar(widthFactor: 0.56, height: 18),
          SizedBox(height: 14),
          _QuickNoteSkeletonAudioBlock(),
        ],
      ),
    );
  }
}

class _QuickNoteSkeletonAudioBlock extends StatelessWidget {
  const _QuickNoteSkeletonAudioBlock();

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: palette.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.outline),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Expanded(child: _QuickNoteSkeletonBar(widthFactor: 1, height: 18)),
            SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _QuickNoteSkeletonBar(widthFactor: 0.26, height: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickNoteSkeletonBar extends StatelessWidget {
  const _QuickNoteSkeletonBar({
    required this.widthFactor,
    required this.height,
  });

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonBar(widthFactor: widthFactor, height: height);
  }
}

class QuickNotesDiagnostics {
  const QuickNotesDiagnostics({
    required this.microphonePermissionGranted,
    required this.speechAvailable,
    required this.inputDeviceLabels,
    required this.diagnosing,
  });

  final bool? microphonePermissionGranted;
  final bool? speechAvailable;
  final List<String> inputDeviceLabels;
  final bool diagnosing;
}

class _VoiceDraft {
  const _VoiceDraft({
    required this.text,
    required this.audioPath,
    required this.audioDurationMillis,
    required this.waveformSamples,
  });

  final String text;
  final String? audioPath;
  final int? audioDurationMillis;
  final List<double> waveformSamples;
}

class _QuickNoteException implements Exception {
  const _QuickNoteException(this.message);

  final String message;
}
