import 'dart:convert';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
    this.updatedAt,
    this.avatarUrl,
    this.timezone,
    this.locale,
  });

  final String id;
  final String name;
  final String email;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? avatarUrl;
  final String? timezone;
  final String? locale;

  AuthUser copyWith({
    String? id,
    String? name,
    String? email,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? avatarUrl,
    String? timezone,
    String? locale,
  }) {
    return AuthUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      timezone: timezone ?? this.timezone,
      locale: locale ?? this.locale,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'avatarUrl': avatarUrl,
      'timezone': timezone,
      'locale': locale,
    };
  }

  factory AuthUser.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) {
        return null;
      }
      return DateTime.tryParse(value as String);
    }

    String readString(List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value is String && value.isNotEmpty) {
          return value;
        }
      }
      return '';
    }

    final createdAt =
        parseDate(map['createdAt'] ?? map['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final nickname = readString(['nickname', 'name']);
    final avatar = readString(['avatarUrl', 'avatar_url']);
    final timezone = readString(['timezone']);
    final locale = readString(['locale']);

    return AuthUser(
      id: readString(['id']),
      name: nickname,
      email: readString(['email']),
      avatarUrl: avatar.isEmpty ? null : avatar,
      timezone: timezone.isEmpty ? null : timezone,
      locale: locale.isEmpty ? null : locale,
      createdAt: createdAt,
      updatedAt: parseDate(map['updatedAt'] ?? map['updated_at']),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AuthUser.fromJson(String source) =>
      AuthUser.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
