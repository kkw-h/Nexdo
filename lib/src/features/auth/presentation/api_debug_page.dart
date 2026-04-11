import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

class ApiDebugPage extends StatefulWidget {
  const ApiDebugPage({super.key, required this.apiClient});

  final NexdoApiClient apiClient;

  @override
  State<ApiDebugPage> createState() => _ApiDebugPageState();
}

class _ApiDebugPageState extends State<ApiDebugPage> {
  bool _loading = false;
  String? _result;
  String? _error;
  DateTime? _timestamp;
  late final TextEditingController _baseUrlController;
  late String _activeBaseUrl;

  @override
  void initState() {
    super.initState();
    _activeBaseUrl = widget.apiClient.baseUrl;
    _baseUrlController = TextEditingController(text: _activeBaseUrl);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('接口调试工具')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前接口地址', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '例如：https://api.example.com/api/v1',
                ),
                enabled: !_loading,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _applyBaseUrl,
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: const Text('应用地址'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '用于验证 Flutter 到 Nexdo API 的连通性。可以修改上方地址并点击应用，再触发 `GET /health` 查看结果。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF60716B),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loading ? null : _testHealth,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.monitor_heart_rounded),
                label: Text(_loading ? '请求中…' : '测试 GET /health'),
              ),
              const SizedBox(height: 20),
              if (_timestamp != null)
                Text(
                  '最近一次请求：${_timestamp!.toLocal()}',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _result ?? _error ?? '尚未发起请求。当前地址：$_activeBaseUrl',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _error != null
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurface,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _testHealth() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final client = NexdoApiClient(baseUrl: _activeBaseUrl);
      final response = await client.request(method: 'GET', path: '/health');
      final encoder = const JsonEncoder.withIndent('  ');
      setState(() {
        _result = encoder.convert(response);
        _timestamp = DateTime.now();
      });
    } on ApiException catch (error) {
      setState(() {
        _error = 'ApiException: ${error.message} (status: ${error.statusCode})';
        _timestamp = DateTime.now();
      });
    } catch (error) {
      setState(() {
        _error = '未知错误: $error';
        _timestamp = DateTime.now();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _applyBaseUrl() {
    final candidate = _baseUrlController.text.trim();
    if (candidate.isEmpty) {
      return;
    }
    setState(() {
      _activeBaseUrl = candidate;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已切换到 $candidate')));
  }
}
