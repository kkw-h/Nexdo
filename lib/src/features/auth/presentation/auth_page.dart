import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
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
    final palette = AppThemeScope.of(context).palette;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(color: palette.background),
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
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 46,
                            width: 46,
                            decoration: BoxDecoration(
                              color: palette.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.task_alt_rounded,
                              color: palette.primary,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            isRegister ? '创建账号' : '登录 Nexdo',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: palette.onSurface,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isRegister ? '使用邮箱创建新账号' : '继续使用你的账号',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: palette.textMuted),
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
                          const SizedBox(height: 18),
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
                          const SizedBox(height: 12),
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
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _submitting ? null : _openDebugPage,
                              icon: const Icon(
                                Icons.bug_report_outlined,
                                size: 18,
                              ),
                              label: const Text('调试'),
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppThemeScope.of(context).palette.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppThemeScope.of(context).palette.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SegmentedButton<AuthMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<AuthMode>(value: AuthMode.login, label: Text('登录')),
              ButtonSegment<AuthMode>(
                value: AuthMode.register,
                label: Text('注册'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
      ),
    );
  }
}
