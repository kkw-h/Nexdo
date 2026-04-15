import 'package:flutter/material.dart';

import '../data/auth_repository.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _submitting = false;
  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改密码')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '更新账号密码',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '修改后，下次登录需要使用新密码。为保证安全，请输入当前密码进行验证。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF60716B),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _oldPasswordController,
                        obscureText: _obscureOldPassword,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: '当前密码',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureOldPassword = !_obscureOldPassword;
                              });
                            },
                            icon: Icon(
                              _obscureOldPassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if ((value ?? '').isEmpty) {
                            return '请输入当前密码';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: _obscureNewPassword,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: '新密码',
                          helperText: '至少 8 位，建议包含字母、数字和符号',
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureNewPassword = !_obscureNewPassword;
                              });
                            },
                            icon: Icon(
                              _obscureNewPassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final text = value ?? '';
                          if (text.isEmpty) {
                            return '请输入新密码';
                          }
                          if (text.length < 8) {
                            return '新密码至少 8 位';
                          }
                          if (text == _oldPasswordController.text) {
                            return '新密码不能与当前密码相同';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_submitting) {
                            _submit();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: '确认新密码',
                          prefixIcon: const Icon(Icons.verified_user_rounded),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if ((value ?? '').isEmpty) {
                            return '请再次输入新密码';
                          }
                          if (value != _newPasswordController.text) {
                            return '两次输入的新密码不一致';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
                              : const Text('确认修改'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.repository.changePassword(
        oldPassword: _oldPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('密码已更新')));
      Navigator.of(context).pop(true);
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
}
