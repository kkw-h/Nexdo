import 'package:flutter/material.dart';
import 'package:nexdo/src/core/network/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../reminders/presentation/reminder_app_shell.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';
import 'auth_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthRepository? _repository;
  NexdoApiClient? _apiClient;
  AuthUser? _currentUser;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final apiClient = NexdoApiClient();
    final repository = AuthRepository(
      preferences: preferences,
      apiClient: apiClient,
    );
    AuthUser? user;
    try {
      user = await repository.getCurrentUser();
      if (user != null) {
        final refreshed = await repository.refreshSessionOnAppLaunch();
        if (refreshed != null) {
          user = refreshed;
        }
      }
    } catch (_) {
      user = null;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _repository = repository;
      _apiClient = apiClient;
      _currentUser = user;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _repository == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final repository = _repository!;
    final user = _currentUser;
    if (user == null) {
      final apiClient = _apiClient;
      if (apiClient == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return AuthPage(
        repository: repository,
        apiClient: apiClient,
        onAuthenticated: (authenticatedUser) {
          setState(() {
            _currentUser = authenticatedUser;
          });
        },
      );
    }

    final apiClient = _apiClient;
    if (apiClient == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ReminderAppShell(
      currentUser: user,
      apiClient: apiClient,
      authRepository: repository,
      onLogout: () async {
        await repository.logout();
        if (!mounted) {
          return;
        }
        setState(() {
          _currentUser = null;
        });
      },
    );
  }
}
