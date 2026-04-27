import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.platform,
    required this.deviceName,
    required this.appVersion,
    required this.userAgent,
  });

  final String deviceId;
  final String platform;
  final String deviceName;
  final String appVersion;
  final String userAgent;
}

class DeviceIdentityProvider {
  DeviceIdentityProvider._();

  static final DeviceIdentityProvider instance = DeviceIdentityProvider._();

  static const _deviceIdKey = 'device.identity.id';

  DeviceIdentity? _cached;

  Future<DeviceIdentity> ensureIdentity() async {
    if (_cached != null) {
      return _cached!;
    }
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }

    final deviceInfo = DeviceInfoPlugin();
    String platformLabel = _platformLabel();
    String deviceName = '未知设备';

    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        final manufacturer = info.manufacturer.trim();
        final model = info.model.trim();
        final joined = '$manufacturer $model'.trim();
        deviceName = joined.isEmpty ? 'Android 设备' : joined;
        platformLabel = 'Android ${info.version.release}';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final iosName = info.name.trim();
        final machine = info.utsname.machine.trim();
        deviceName = iosName.isNotEmpty ? iosName : (machine.isNotEmpty ? machine : 'iOS Device');
        platformLabel = 'iOS ${info.systemVersion}';
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        final name = info.computerName.trim();
        deviceName = name.isNotEmpty ? name : 'macOS Device';
        platformLabel = 'macOS ${info.osRelease}';
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        final name = info.computerName.trim();
        deviceName = name.isNotEmpty ? name : 'Windows Device';
        platformLabel = 'Windows ${info.productName}';
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        final pretty = info.prettyName.trim();
        final name = info.name.trim();
        deviceName = pretty.isNotEmpty ? pretty : (name.isNotEmpty ? name : 'Linux Device');
        platformLabel = 'Linux';
      } else if (Platform.isFuchsia) {
        deviceName = 'Fuchsia Device';
        platformLabel = 'Fuchsia';
      }
    } catch (_) {
      deviceName = '未知设备';
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = packageInfo.version;
    final userAgent = _sanitizeHeaderValue(
      'Nexdo/$appVersion ($platformLabel; $deviceName)',
    );

    _cached = DeviceIdentity(
      deviceId: deviceId,
      platform: platformLabel,
      deviceName: deviceName,
      appVersion: appVersion,
      userAgent: userAgent,
    );
    return _cached!;
  }

  String _platformLabel() {
    switch (Platform.operatingSystem) {
      case 'android':
        return 'Android';
      case 'ios':
        return 'iOS';
      case 'macos':
        return 'macOS';
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
      default:
        return Platform.operatingSystem;
    }
  }

  String _sanitizeHeaderValue(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.codeUnits) {
      if (codeUnit >= 32 && codeUnit <= 126) {
        buffer.writeCharCode(codeUnit);
      } else {
        buffer.write('?');
      }
    }
    return buffer.toString();
  }
}
