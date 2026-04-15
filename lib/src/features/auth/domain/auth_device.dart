class AuthDevice {
  const AuthDevice({
    required this.id,
    required this.userId,
    required this.deviceName,
    required this.platform,
    required this.userAgent,
    required this.ipAddress,
    required this.createdAt,
    required this.lastActiveAt,
    this.deviceFingerprint,
    this.isCurrent = false,
  });

  final String id;
  final String userId;
  final String deviceName;
  final String platform;
  final String userAgent;
  final String ipAddress;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final String? deviceFingerprint;
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

    String inferDeviceName(String? value) {
      final raw = (value ?? '').trim();
      if (raw.isNotEmpty) {
        return raw;
      }
      final agent = (map['user_agent']?.toString() ?? '').toLowerCase();
      if (agent.contains('iphone')) return 'iPhone';
      if (agent.contains('ipad')) return 'iPad';
      if (agent.contains('android')) return 'Android';
      if (agent.contains('mac os')) return 'Mac';
      if (agent.contains('windows')) return 'Windows';
      if (agent.contains('linux')) return 'Linux';
      return '未知设备';
    }

    String inferPlatform(String? value) {
      final raw = (value ?? '').trim();
      if (raw.isNotEmpty) {
        return raw;
      }
      final agent = (map['user_agent']?.toString() ?? '').toLowerCase();
      if (agent.contains('iphone') || agent.contains('ipad') || agent.contains('ios')) {
        return 'iOS';
      }
      if (agent.contains('android')) {
        return 'Android';
      }
      if (agent.contains('mac os')) {
        return 'macOS';
      }
      if (agent.contains('windows nt')) {
        return 'Windows';
      }
      if (agent.contains('linux')) {
        return 'Linux';
      }
      return '未知平台';
    }

    return AuthDevice(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      deviceName: inferDeviceName(map['device_name'] as String?),
      platform: inferPlatform(map['platform'] as String?),
      userAgent: map['user_agent']?.toString() ?? 'Unknown Device',
      ipAddress: map['ip_address']?.toString() ?? 'Unknown IP',
      createdAt: parseDate(map['created_at']),
      lastActiveAt: parseDate(map['last_active_at'] ?? map['updated_at']),
      deviceFingerprint: map['device_id']?.toString(),
      isCurrent: (map['is_current'] as bool? ?? false) || isCurrent,
    );
  }
}
