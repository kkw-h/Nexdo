import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/network/api_client.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';
import 'api_debug_page.dart';

enum AuthMode { login, register }

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.repository,
    required this.apiClient,
    required this.onAuthenticated,
  });

  final AuthRepository repository;
  final NexdoApiClient apiClient;
  final ValueChanged<AuthUser> onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  AuthMode _mode = AuthMode.login;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = _mode == AuthMode.register;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFDCEEE6), Color(0xFFF5F7F2)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.authCardMaxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF173A33),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  height: 54,
                                  width: 54,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFE7D1),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(
                                    Icons.task_alt_rounded,
                                    color: Color(0xFF173A33),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  isRegister ? '开始建立你的任务空间' : '欢迎回到 Nexdo',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isRegister
                                      ? '一个地方管理提醒、清单和闪念，让日程与想法保持同步。'
                                      : '登录后继续处理提醒、记录闪念并维护你的任务系统。',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFFC8D6D0),
                                      ),
                                ),
                                const SizedBox(height: 16),
                                const Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _AuthFeatureChip(
                                      icon: Icons.notifications_active_rounded,
                                      label: '提醒同步',
                                    ),
                                    _AuthFeatureChip(
                                      icon: Icons.bolt_rounded,
                                      label: '闪念速记',
                                    ),
                                    _AuthFeatureChip(
                                      icon: Icons.view_list_rounded,
                                      label: '清单分组',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            isRegister ? '创建你的 Nexdo 账号' : '登录 Nexdo',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isRegister
                                ? '注册后即可直接连接 Nexdo API，同步提醒与闪念数据。'
                                : '输入你的账号信息，继续管理提醒、清单、闪念和日历安排。',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF60716B)),
                          ),
                          const SizedBox(height: 20),
                          _AuthModeSegmentedControl(
                            mode: _mode,
                            onChanged: (mode) {
                              setState(() {
                                _mode = mode;
                              });
                            },
                          ),
                          const SizedBox(height: 20),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                if (isRegister) ...[
                                  TextFormField(
                                    controller: _nameController,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: '昵称',
                                      hintText: '输入你的名字',
                                      prefixIcon: Icon(Icons.person_rounded),
                                    ),
                                    validator: (value) {
                                      if (!isRegister) {
                                        return null;
                                      }
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return '请输入昵称';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: '邮箱',
                                    hintText: 'name@example.com',
                                    prefixIcon: Icon(
                                      Icons.alternate_email_rounded,
                                    ),
                                  ),
                                  validator: (value) {
                                    final text = value?.trim() ?? '';
                                    if (text.isEmpty) {
                                      return '请输入邮箱';
                                    }
                                    if (!text.contains('@') ||
                                        !text.contains('.')) {
                                      return '请输入有效邮箱';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  textInputAction: isRegister
                                      ? TextInputAction.next
                                      : TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: '密码',
                                    hintText: '至少 6 位',
                                    prefixIcon: Icon(Icons.lock_rounded),
                                  ),
                                  validator: (value) {
                                    final text = value ?? '';
                                    if (text.isEmpty) {
                                      return '请输入密码';
                                    }
                                    if (text.length < 6) {
                                      return '密码至少 6 位';
                                    }
                                    return null;
                                  },
                                ),
                                if (isRegister) ...[
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _confirmPasswordController,
                                    obscureText: true,
                                    textInputAction: TextInputAction.done,
                                    decoration: const InputDecoration(
                                      labelText: '确认密码',
                                      hintText: '再次输入密码',
                                      prefixIcon: Icon(
                                        Icons.verified_user_rounded,
                                      ),
                                    ),
                                    validator: (value) {
                                      if (!isRegister) {
                                        return null;
                                      }
                                      if ((value ?? '').isEmpty) {
                                        return '请再次输入密码';
                                      }
                                      if (value != _passwordController.text) {
                                        return '两次输入的密码不一致';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _submitting ? null : _submit,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(isRegister ? '注册并进入' : '登录'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isRegister ? '已经有账号了？' : '还没有账号？',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              TextButton(
                                onPressed: _submitting
                                    ? null
                                    : () {
                                        setState(() {
                                          _mode = isRegister
                                              ? AuthMode.login
                                              : AuthMode.register;
                                        });
                                      },
                                child: Text(isRegister ? '去登录' : '注册一个'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '账号体系已连接 Nexdo API，登录/注册将直接访问云端接口。',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF7A8A84)),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: _submitting ? null : _openDebugPage,
                              icon: const Icon(
                                Icons.bug_report_outlined,
                                size: 18,
                              ),
                              label: const Text('接口调试'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final registerLocale = _localeTag(context);

    setState(() {
      _submitting = true;
    });

    try {
      final user = switch (_mode) {
        AuthMode.login => await widget.repository.login(
          email: _emailController.text,
          password: _passwordController.text,
        ),
        AuthMode.register => await widget.repository.register(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          locale: registerLocale,
          timezone: await _resolveTimezone(),
        ),
      };
      if (!mounted) {
        return;
      }
      widget.onAuthenticated(user);
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<String> _resolveTimezone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      return timezoneInfo.identifier;
    } catch (_) {
      return 'Asia/Shanghai';
    }
  }

  String _localeTag(BuildContext context) {
    final locale =
        Localizations.maybeLocaleOf(context) ??
        WidgetsBinding.instance.platformDispatcher.locale;
    final countryCode = locale.countryCode;
    if (countryCode == null || countryCode.isEmpty) {
      return locale.languageCode;
    }
    return '${locale.languageCode}-$countryCode';
  }

  Future<void> _openDebugPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiDebugPage(apiClient: widget.apiClient),
      ),
    );
  }
}

class _AuthModeSegmentedControl extends StatelessWidget {
  const _AuthModeSegmentedControl({
    required this.mode,
    required this.onChanged,
  });

  final AuthMode mode;
  final ValueChanged<AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<AuthMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment<AuthMode>(value: AuthMode.login, label: Text('登录')),
          ButtonSegment<AuthMode>(value: AuthMode.register, label: Text('注册')),
        ],
        selected: {mode},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _AuthFeatureChip extends StatelessWidget {
  const _AuthFeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x26FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x30FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFFFE7D1)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFFFFE7D1),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
