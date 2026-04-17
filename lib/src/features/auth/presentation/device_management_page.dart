import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/device/device_identity.dart';
import '../data/auth_repository.dart';
import '../domain/auth_device.dart';

class DeviceManagementPage extends StatefulWidget {
  const DeviceManagementPage({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends State<DeviceManagementPage> {
  bool _isLoading = true;
  String? _error;
  List<AuthDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  Future<void> _fetchDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final identity = await DeviceIdentityProvider.instance.ensureIdentity();
      final data = await widget.repository.getDevices();
      final devices = data.map((e) {
        final mapDeviceId = e['device_id']?.toString();
        final inferredCurrent =
            mapDeviceId != null && mapDeviceId == identity.deviceId;
        return AuthDevice.fromMap(e, isCurrent: inferredCurrent);
      }).toList();
      // Sort devices: current first, then by lastActiveAt descending
      devices.sort((a, b) {
        if (a.isCurrent && !b.isCurrent) return -1;
        if (!a.isCurrent && b.isCurrent) return 1;
        return b.lastActiveAt.compareTo(a.lastActiveAt);
      });
      if (mounted) {
        setState(() {
          _devices = devices;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logoutDevice(AuthDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下线设备'),
        content: Text('确定要下线该设备吗？\n${device.userAgent}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      await widget.repository.logoutDevice(device.id);
      if (mounted) {
        navigator.pop(); // dismiss loading
        messenger.showSnackBar(const SnackBar(content: Text('设备已下线')));
        _fetchDevices();
      }
    } catch (e) {
      if (mounted) {
        navigator.pop(); // dismiss loading
        messenger.showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备管理')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE4EEE6), Color(0xFFF7F4EC)],
          ),
        ),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      color: Color(0xFFB85C38),
                      size: 30,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '设备列表加载失败',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF60716B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _fetchDevices,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_devices.isEmpty) {
      return const SafeArea(
        child: Padding(padding: EdgeInsets.all(16), child: _EmptyDevicesCard()),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDevices,
      child: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _devices.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _DeviceHeroCard(deviceCount: _devices.length),
              );
            }
            final device = _devices[index - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: device.isCurrent
                                  ? Theme.of(
                                      context,
                                    ).primaryColor.withValues(alpha: 0.12)
                                  : const Color(0xFFF2F5F1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _iconForDevice(device.platform, device.userAgent),
                              color: device.isCurrent
                                  ? Theme.of(context).primaryColor
                                  : const Color(0xFF60716B),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              device.deviceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (device.isCurrent)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).primaryColor.withAlpha(26),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '当前设备',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _DeviceInfoLine(
                        label: '平台',
                        value: '${device.platform} · ${device.userAgent}',
                      ),
                      _DeviceInfoLine(
                        label: 'IP',
                        value:
                            '${_ipVersion(device.ipAddress)} · ${device.ipAddress}',
                      ),
                      _DeviceInfoLine(
                        label: '设备标识',
                        value: device.deviceFingerprint ?? '未知',
                      ),
                      _DeviceInfoLine(
                        label: '最近活跃',
                        value: _formatDate(device.lastActiveAt),
                      ),
                      if (!device.isCurrent) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _logoutDevice(device),
                            icon: const Icon(
                              Icons.logout_rounded,
                              color: Color(0xFFB85C38),
                            ),
                            label: const Text(
                              '下线设备',
                              style: TextStyle(color: Color(0xFFB85C38)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _iconForDevice(String platform, String agent) {
    final value = platform.toLowerCase();
    final normalizedAgent = agent.toLowerCase();
    if (value.contains('ios') ||
        value.contains('iphone') ||
        normalizedAgent.contains('iphone')) {
      return Icons.phone_iphone;
    }
    if (value.contains('android') || normalizedAgent.contains('android')) {
      return Icons.android;
    }
    if (value.contains('mac')) {
      return Icons.laptop_mac;
    }
    if (value.contains('windows')) {
      return Icons.laptop_windows;
    }
    if (value.contains('linux')) {
      return Icons.laptop;
    }
    return Icons.devices_other;
  }

  String _ipVersion(String ip) {
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null) {
      return '未知';
    }
    switch (parsed.type) {
      case InternetAddressType.IPv4:
        return 'IPv4';
      case InternetAddressType.IPv6:
        return 'IPv6';
      case InternetAddressType.unix:
        return 'Unix';
      default:
        return '未知';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 30) {
      return '${difference.inDays}天前';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }
}

class _DeviceHeroCard extends StatelessWidget {
  const _DeviceHeroCard({required this.deviceCount});

  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            'DEVICES',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFFE58A3A),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '当前共 $deviceCount 台设备登录中',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF16322C),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '你可以在这里查看最近活跃设备，并将不再使用的设备下线。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF60716B)),
          ),
        ],
      ),
    );
  }
}

class _DeviceInfoLine extends StatelessWidget {
  const _DeviceInfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF60716B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF16322C)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDevicesCard extends StatelessWidget {
  const _EmptyDevicesCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F0EA),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.devices_rounded,
                color: Color(0xFF126A5A),
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无设备信息',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '当前没有可展示的登录设备记录，下拉后可以再次尝试刷新。',
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
