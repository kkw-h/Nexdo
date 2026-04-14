class AuthDevice {
  const AuthDevice({
    required this.id,
    required this.userId,
    required this.userAgent,
    required this.ipAddress,
    required this.createdAt,
    required this.lastActiveAt,
    this.isCurrent = false,
  });

  final String id;
  final String userId;
  final String userAgent;
  final String ipAddress;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final bool isCurrent;

  factory AuthDevice.fromMap(
    Map<String, dynamic> map, {
    bool isCurrent = false,
  }) {
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
      return DateTime.tryParse(value.toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    return AuthDevice(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      userAgent: map['user_agent']?.toString() ?? 'Unknown Device',
      ipAddress: map['ip_address']?.toString() ?? 'Unknown IP',
      createdAt: parseDate(map['created_at']),
      lastActiveAt: parseDate(map['last_active_at'] ?? map['updated_at']),
      isCurrent: map['is_current'] as bool? ?? isCurrent,
    );
  }
}
