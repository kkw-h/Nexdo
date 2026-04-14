import 'package:flutter/material.dart';
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
      final data = await widget.repository.getDevices();
      final devices = data.map((e) => AuthDevice.fromMap(e)).toList();
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('加载失败: $_error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _fetchDevices, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return const Center(child: Text('暂无设备信息'));
    }

    return RefreshIndicator(
      onRefresh: _fetchDevices,
      child: ListView.builder(
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices[index];
          return ListTile(
            leading: Icon(
              device.userAgent.toLowerCase().contains('mobile') ||
                      device.userAgent.toLowerCase().contains('android') ||
                      device.userAgent.toLowerCase().contains('ios') ||
                      device.userAgent.toLowerCase().contains('dart')
                  ? Icons.smartphone
                  : Icons.computer,
              color: device.isCurrent ? Theme.of(context).primaryColor : null,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    device.userAgent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (device.isCurrent)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '当前设备',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('IP: ${device.ipAddress}'),
                Text('最近活跃: ${_formatDate(device.lastActiveAt)}'),
              ],
            ),
            trailing: device.isCurrent
                ? null
                : IconButton(
                    icon: const Icon(Icons.logout, color: Colors.red),
                    onPressed: () => _logoutDevice(device),
                  ),
          );
        },
      ),
    );
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
