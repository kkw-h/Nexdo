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

import '../../auth/data/auth_repository.dart' show AuthException;
import '../data/quick_notes_repository.dart';
import '../domain/entities/quick_note.dart';

class QuickNotesPage extends StatefulWidget {
  const QuickNotesPage({
    super.key,
    required this.repository,
    this.onDiagnosticsChanged,
  });

  final QuickNotesRepository repository;
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
    final noteCount = _notes.length;
    final voiceCount = _notes.where((note) => note.hasAudio).length;
    return RefreshIndicator(
      onRefresh: _refreshNotes,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _QuickNotesHeroCard(
            noteCount: noteCount,
            voiceCount: voiceCount,
            isRefreshing: _refreshing,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const _QuickNotesLoadingState()
          else if (_loadError != null)
            _QuickNotesErrorState(message: _loadError!, onRetry: _refreshNotes)
          else if (_notes.isEmpty)
            const _QuickNotesEmptyState()
          else
            ..._notes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _QuickNoteCard(
                  note: note,
                  isPlaying: _playingNoteId == note.id,
                  playbackPosition: _playingNoteId == note.id
                      ? _playbackPosition
                      : Duration.zero,
                  playbackDuration: _playingNoteId == note.id
                      ? _playbackDuration
                      : Duration.zero,
                  onPlay: note.hasAudio ? () => _togglePlayback(note) : null,
                  onDelete: () => _deleteNote(note),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickNoteTextSheet extends StatefulWidget {
  const _QuickNoteTextSheet();

  @override
  State<_QuickNoteTextSheet> createState() => _QuickNoteTextSheetState();
}

class _QuickNoteTextSheetState extends State<_QuickNoteTextSheet> {
  final _controller = TextEditingController();

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
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '新增闪念',
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
                decoration: const InputDecoration(
                  hintText: '输入你的想法、待办或灵感',
                  border: OutlineInputBorder(),
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
                    onPressed: () =>
                        Navigator.of(context).pop(_controller.text),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '语音输入',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _cancelRecording,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(minHeight: 120),
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _textController,
                    maxLines: 5,
                    minLines: 5,
                    decoration: const InputDecoration.collapsed(
                      hintText: '识别后的文字会显示在这里，也可以手动编辑',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1C18),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: _WaveformView(samples: _waveformSamples),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _statusText ?? (_starting ? '正在准备录音...' : '按住按钮开始说话'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _cancelRecording,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _starting ? null : _pauseOrResume,
                        icon: Icon(
                          _isPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                        ),
                        label: Text(_isPaused ? '继续' : '暂停'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _starting ? null : _finishAndSave,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('保存'),
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
}

class _WaveformView extends StatelessWidget {
  const _WaveformView({required this.samples});

  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bars = samples.isEmpty ? [0.1] : samples;
        return Align(
          alignment: Alignment.center,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < bars.length; i++) ...[
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 6,
                      height: math.max(10.0, bars[i] * constraints.maxHeight),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6DF7C1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                if (i != bars.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _QuickNoteCard extends StatelessWidget {
  static const double _actionSlotWidth = 40;
  static const double _actionButtonSize = 32;

  const _QuickNoteCard({
    required this.note,
    required this.isPlaying,
    required this.playbackPosition,
    required this.playbackDuration,
    required this.onDelete,
    this.onPlay,
  });

  final QuickNote note;
  final bool isPlaying;
  final Duration playbackPosition;
  final Duration playbackDuration;
  final VoidCallback onDelete;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final createdAtText = DateFormat(
      'M月d日 HH:mm',
      'zh_CN',
    ).format(note.createdAt.toLocal());
    final totalDuration = playbackDuration > Duration.zero
        ? playbackDuration
        : Duration(milliseconds: note.audioDurationMillis ?? 0);
    final progress = totalDuration.inMilliseconds <= 0
        ? 0.0
        : (playbackPosition.inMilliseconds / totalDuration.inMilliseconds)
              .clamp(0, 1)
              .toDouble();
    return Card(
      color: const Color(0xFFFFFCF7),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    createdAtText,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF60716B),
                    ),
                  ),
                ),
                SizedBox(
                  width: _actionSlotWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      tooltip: '删除闪念',
                      visualDensity: VisualDensity.compact,
                      splashRadius: 20,
                      color: const Color(0xFF60716B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (note.text.isNotEmpty)
              Text(
                note.text,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(height: 1.5),
              )
            else
              Text(
                '仅保存了录音',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF60716B),
                ),
              ),
            if (note.hasAudio) ...[
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onPlay,
                child: Container(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Spacer(),
                          SizedBox(
                            width: _actionSlotWidth,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                width: _actionButtonSize,
                                height: _actionButtonSize,
                                decoration: BoxDecoration(
                                  color: isPlaying
                                      ? const Color(0xFF1D7F5F)
                                      : const Color(0xFFEAEFEA),
                                  borderRadius: BorderRadius.circular(
                                    _actionButtonSize / 2,
                                  ),
                                ),
                                child: Icon(
                                  isPlaying
                                      ? Icons.stop_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 18,
                                  color: isPlaying
                                      ? Colors.white
                                      : const Color(0xFF35584C),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: isPlaying
                            ? Container(
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  12,
                                  0,
                                  10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FBF9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFDCE6E1),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 28,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD9E4DF),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: _AudioWaveformStrip(
                                        samples: note.waveformSamples,
                                        progress: progress,
                                        active: true,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        '播放进度 ${_formatDuration(playbackPosition)} / ${_formatDuration(totalDuration)}',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFF60716B),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 11,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
      height: 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < bars.length; index++) ...[
            if (index > 0) const SizedBox(width: 3),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 4 + (bars[index] * 10),
                  decoration: BoxDecoration(
                    color: _barColor((index + 1) / bars.length),
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
      return List<double>.filled(24, 0.24);
    }
    const targetCount = 24;
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
      final peak = segment.reduce(math.max);
      result.add(peak);
    }
    return result;
  }

  Color _barColor(double ratio) {
    final played = ratio <= progress.clamp(0.0, 1.0);
    if (played) {
      return active ? const Color(0xFF1D7F5F) : const Color(0xFF8FBBAA);
    }
    return active ? const Color(0xFFB9D9CC) : const Color(0xFFD8E3DE);
  }
}

class _QuickNotesEmptyState extends StatelessWidget {
  const _QuickNotesEmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFFCF7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE7D1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                size: 30,
                color: Color(0xFFE58A3A),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有闪念',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '点击右下角按钮输入文字，或长按按钮直接开始语音记录。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF60716B)),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickNotesErrorState extends StatelessWidget {
  const _QuickNotesErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFFCF7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3EE),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 28,
                color: Color(0xFFB85C38),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '闪念加载失败',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF60716B)),
            ),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: () => unawaited(onRetry()),
              child: const Text('重新加载'),
            ),
          ],
        ),
      ),
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

class _QuickNotesHeroCard extends StatelessWidget {
  const _QuickNotesHeroCard({
    required this.noteCount,
    required this.voiceCount,
    required this.isRefreshing,
  });

  final int noteCount;
  final int voiceCount;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4EAE4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUICK NOTES',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFFE58A3A),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            noteCount == 0 ? '随手记下刚出现的想法' : '已记录 $noteCount 条闪念',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF16322C),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '点击右下角创建文字闪念，长按可直接进行语音记录。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF60716B)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickNotesMetricChip(
                icon: Icons.notes_rounded,
                label: '文字 $noteCount',
              ),
              _QuickNotesMetricChip(
                icon: Icons.graphic_eq_rounded,
                label: '语音 $voiceCount',
              ),
              _QuickNotesMetricChip(
                icon: isRefreshing
                    ? Icons.sync_rounded
                    : Icons.touch_app_rounded,
                label: isRefreshing ? '刷新中' : '下拉刷新',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickNotesMetricChip extends StatelessWidget {
  const _QuickNotesMetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF476058)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF476058),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickNoteSkeletonCard extends StatelessWidget {
  const _QuickNoteSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _QuickNoteSkeletonBar(widthFactor: 0.24, height: 14),
            SizedBox(height: 16),
            _QuickNoteSkeletonBar(widthFactor: 0.78, height: 18),
            SizedBox(height: 10),
            _QuickNoteSkeletonBar(widthFactor: 0.56, height: 18),
            SizedBox(height: 14),
            _QuickNoteSkeletonAudioBlock(),
          ],
        ),
      ),
    );
  }
}

class _QuickNoteSkeletonAudioBlock extends StatelessWidget {
  const _QuickNoteSkeletonAudioBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E8E4)),
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
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: _BreathingPlaceholder(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(height: height),
      ),
    );
  }
}

class _BreathingPlaceholder extends StatefulWidget {
  const _BreathingPlaceholder({
    required this.child,
    required this.borderRadius,
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<_BreathingPlaceholder> createState() => _BreathingPlaceholderState();
}

class _BreathingPlaceholderState extends State<_BreathingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = _controller.value;
        final begin = Alignment(-1.8 + (2.6 * progress), 0);
        final end = Alignment(-0.8 + (2.6 * progress), 0);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: const [
                Color(0xFFE3ECE8),
                Color(0xFFF5F9F7),
                Color(0xFFE3ECE8),
              ],
              stops: const [0.1, 0.5, 0.9],
            ),
          ),
          child: child,
        );
      },
    );
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
