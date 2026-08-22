import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile/services/auth_service.dart' as auth_service;
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/services/error_mapper.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/sync_provider.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/config/demo_config.dart';

class LoginScreenRedesign extends StatefulWidget {
  const LoginScreenRedesign({super.key});

  @override
  State<LoginScreenRedesign> createState() => _LoginScreenRedesignState();
}

class _LoginScreenRedesignState extends State<LoginScreenRedesign> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool _isLoading = false;

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() => _isLoading = false);
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      await authProvider.login(username, password);

      // Get providers
      final storeProvider = Provider.of<StoreProvider>(context, listen: false);
      final syncProvider = Provider.of<SyncProvider>(context, listen: false);

      // Reset store provider data for the new user
      storeProvider.resetUserData();

      // Set up callback so stores reload after sync completes
      syncProvider.onSyncComplete = () async {
        debugPrint(
            '📥 Sync complete callback - reloading stores and user data');
        storeProvider.loadMyStores();
        storeProvider.loadStores();

        // Refresh current user data from updated local database
        await authProvider.refreshCurrentUser();
      };

      // Perform initial sync to fetch all data from server
      // This is CRITICAL for new devices - it fetches all stores, users, products, etc.
      debugPrint('🔄 Starting post-login initial sync...');
      final syncSuccess = await syncProvider.forceInitialSync();
      debugPrint('📊 Initial sync result: $syncSuccess');

      // Now initialize store provider (which reads from local DB that was just populated)
      await storeProvider.initialize();
      await storeProvider.loadStores();

      if (!mounted) return;
      // Show success notification and navigate to home
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Logged in')));
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      // Log raw error for diagnostics
      debugPrint('Login error: $e');

      // Support both legacy thrown Maps and the new AuthException
      String friendly;
      try {
        friendly = ErrorMapper.friendlyMessage(e is Map
            ? e
            : (e is auth_service.AuthException ? e : e.toString()));
      } catch (mapperError) {
        debugPrint('Error in ErrorMapper: $mapperError');
        // Fallback to a generic message
        friendly = 'Login failed. Please check your credentials and try again.';
      }

      if (mounted) {
        setState(() {
          _errorMessage = friendly;
        });
      }

      // If server reports invalid credentials, clear and focus password field for quick retry
      dynamic errObj;
      if (e is Map) errObj = e;
      if (e is auth_service.AuthException) errObj = e.toMap();

      if (mounted && errObj is Map) {
        final code = errObj['code'];
        final message = (errObj['message'] ?? '').toString().toLowerCase();
        if (code == 400 ||
            message.contains('incorrect') ||
            message.contains('password') ||
            message.contains('invalid')) {
          _passwordController.clear();
          _passwordFocus.requestFocus();
        } else if (message.contains('user') || message.contains('username')) {
          _usernameController.clear();
          _usernameFocus.requestFocus();
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use the canonical brand color from tokens for a consistent hex
    const primary = AppColors.primaryBrand;
    // In debug builds, verify the theme's primary is set to the token value
    assert(Theme.of(context).colorScheme.primary == AppColors.primaryBrand);
    return Scaffold(
      backgroundColor: primary,
      appBar:
          AppBar(backgroundColor: primary, elevation: 0, title: const Text('')),
      body: SafeArea(
        child: Center(
          child: Card(
            color: Colors.white.withValues(alpha: 0.88 * 255),
            elevation: 6,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo at top
                        Image.asset('assets/images/pos_logo.png', height: 72),
                        const SizedBox(height: 12),
                        const Text('Welcome back',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(_errorMessage!,
                                style: const TextStyle(color: Colors.red),
                                semanticsLabel: 'login_error'),
                          ),
                        PrimaryTextField(
                          controller: _usernameController,
                          focusNode: _usernameFocus,
                          label: 'Username',
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        PrimaryTextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          label: 'Password',
                          obscureText: _obscurePassword,
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                          suffixIcon: IconButton(
                            tooltip: 'Toggle password visibility',
                            icon: Icon(_obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _isLoading
                            ? const CircularProgressIndicator()
                            : PrimaryButton(
                                onPressed: _submit,
                                child: const Text('Sign in')),
                        if (DemoConfig.isDemoMode) ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade400),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline, color: Colors.amber, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Demo Mode Active',
                                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () {
                                  _usernameController.text = 'demo';
                                  _passwordController.text = 'demo123';
                                },
                                child: const Text('Fill Cashier'),
                              ),
                              TextButton(
                                onPressed: () {
                                  _usernameController.text = 'admin';
                                  _passwordController.text = 'demo123';
                                },
                                child: const Text('Fill Admin'),
                              ),
                            ],
                          ),
                        ],
                      ],
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
}
