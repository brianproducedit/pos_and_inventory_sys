import 'package:flutter/material.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/services/error_mapper.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/theme/tokens.dart';

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
      if (!mounted) return;
      // Show success notification and navigate to home
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Logged in')));
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      // Log raw error for diagnostics
      debugPrint('Login error: $e');

      // Support both legacy thrown Maps and the new AuthException
      final friendly = ErrorMapper.friendlyMessage(
          e is Map ? e : (e is AuthException ? e : e.toString()));

      setState(() {
        _errorMessage = friendly;
      });

      // If server reports invalid credentials, clear and focus password field for quick retry
      dynamic errObj;
      if (e is Map) errObj = e;
      if (e is AuthException) errObj = e.toMap();

      if (errObj is Map) {
        final code = errObj['code'];
        final message = (errObj['message'] ?? '').toString().toLowerCase();
        if (code == 400 ||
            message.contains('incorrect') ||
            message.contains('password')) {
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
            color: Colors.white.withOpacity(0.88),
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
