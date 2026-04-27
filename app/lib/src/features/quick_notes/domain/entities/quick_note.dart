import 'dart:convert';

class QuickNote {
  const QuickNote({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.status = 'draft',
    this.convertedReminderId,
    this.audioUrl,
    this.audioFilename,
    this.audioMimeType,
    this.audioSizeBytes,
    this.audioPath,
    this.audioDurationMillis,
    this.waveformSamples,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String status;
  final String? convertedReminderId;
  final String? audioUrl;
  final String? audioFilename;
  final String? audioMimeType;
  final int? audioSizeBytes;
  final String? audioPath;
  final int? audioDurationMillis;
  final List<double>? waveformSamples;

  bool get hasAudio =>
      (audioPath != null && audioPath!.isNotEmpty) ||
      (audioUrl != null && audioUrl!.isNotEmpty);

  QuickNote copyWith({
    String? id,
    String? text,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? status,
    String? convertedReminderId,
    String? audioUrl,
    String? audioFilename,
    String? audioMimeType,
    int? audioSizeBytes,
    String? audioPath,
    int? audioDurationMillis,
    List<double>? waveformSamples,
    bool clearAudioPath = false,
  }) {
    return QuickNote(
      id: id ?? this.id,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      convertedReminderId: convertedReminderId ?? this.convertedReminderId,
      audioUrl: audioUrl ?? this.audioUrl,
      audioFilename: audioFilename ?? this.audioFilename,
      audioMimeType: audioMimeType ?? this.audioMimeType,
      audioSizeBytes: audioSizeBytes ?? this.audioSizeBytes,
      audioPath: clearAudioPath ? null : (audioPath ?? this.audioPath),
      audioDurationMillis: audioDurationMillis ?? this.audioDurationMillis,
      waveformSamples: waveformSamples ?? this.waveformSamples,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'status': status,
      'convertedReminderId': convertedReminderId,
      'audioUrl': audioUrl,
      'audioFilename': audioFilename,
      'audioMimeType': audioMimeType,
      'audioSizeBytes': audioSizeBytes,
      'audioPath': audioPath,
      'audioDurationMillis': audioDurationMillis,
      'waveformSamples': waveformSamples,
    };
  }

  factory QuickNote.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic value) {
      if (value is String && value.isNotEmpty) {
        return DateTime.parse(value);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return QuickNote(
      id: map['id'] as String,
      text: (map['text'] ?? map['content']) as String? ?? '',
      createdAt: parseDate(map['createdAt'] ?? map['created_at']),
      updatedAt: parseDate(map['updatedAt'] ?? map['updated_at']),
      status: map['status'] as String? ?? 'draft',
      convertedReminderId:
          (map['convertedReminderId'] ?? map['converted_reminder_id'])
              as String?,
      audioUrl: (map['audioUrl'] ?? map['audio_url']) as String?,
      audioFilename: (map['audioFilename'] ?? map['audio_filename']) as String?,
      audioMimeType:
          (map['audioMimeType'] ?? map['audio_mime_type']) as String?,
      audioSizeBytes:
          ((map['audioSizeBytes'] ?? map['audio_size_bytes']) as num?)?.toInt(),
      audioPath: map['audioPath'] as String?,
      audioDurationMillis:
          ((map['audioDurationMillis'] ?? map['audio_duration_ms']) as num?)
              ?.toInt(),
      waveformSamples: ((map['waveformSamples'] ?? map['waveform_samples'])
              as List<dynamic>?)
          ?.map((item) => (item as num).toDouble())
          .toList(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory QuickNote.fromJson(String source) =>
      QuickNote.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
