// Presents the password reset form, validates the email, and triggers Firebase
// Auth's reset-password flow before showing a success state for the user.

import 'package:flutter/material.dart';
import '../services/auth_service.dart';

// brand colours
const _kBrandBlue = Color(0xFF1F4E9E);
const _kBrandYellow = Color(0xFFFFDE59);
const _kFieldFill = Color(0xFFF3F3F3);
const _kBorderGrey = Color(0xFFE0E0E0);

// Public screen widget for the password-reset page.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

// Holds the reset form state, validation, request handling, and success/error UI.
class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;
  bool _emailSent = false;
  // UI-only state: whether the email field currently holds a syntactically
  // valid address (drives the checkmark shown on the login/signup screens).
  bool _emailValid = false;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_updateEmailValidity);
  }

  void _updateEmailValidity() {
    final valid = _emailRegex.hasMatch(_emailController.text.trim());
    if (valid != _emailValid) setState(() => _emailValid = valid);
  }

  @override
  void dispose() {
    _emailController.removeListener(_updateEmailValidity);
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.resetPassword(email: _emailController.text);
      if (!mounted) return;

      setState(() {
        _emailSent = true;
      });
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _BackButton(onTap: () => Navigator.of(context).maybePop()),
                ],
              ),
              const SizedBox(height: 28),
              if (_emailSent) ...[
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 48,
                  color: _kBrandBlue,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Check your email',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'If an account exists for that email, a reset link has been sent.',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrandYellow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Back to login',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ] else ...[
                _ResetTitle(),
                // const Text(
                //   'Reset your password',
                //   style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                // ),
                // const SizedBox(height: 8),
                // Text(
                //   'Enter the email linked to your account and we will send a reset link.',
                //   style: TextStyle(color: Colors.grey[700]),
                // ),
                const SizedBox(height: 28),
                const _FieldLabel('Email address'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _fieldDecoration(
                    hintText: 'example@gmail.com',
                    suffixIcon: _emailValid
                        ? const Icon(Icons.check_circle, color: Colors.black87)
                        : null,
                  ),
                  validator: (value) {
                    final requiredError = _required(value);
                    if (requiredError != null) return requiredError;
                    return _emailRegex.hasMatch(value!.trim())
                        ? null
                        : 'Enter a valid email address.';
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _sendResetEmail,
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrandYellow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'Send reset link',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration({String? hintText, Widget? suffixIcon}) {
  return InputDecoration(
    hintText: hintText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: _kFieldFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kBrandBlue, width: 1.4),
    ),
  );
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          side: const BorderSide(color: _kBorderGrey, width: 1.2),
        ),
        child: const Icon(Icons.chevron_left, color: Colors.black87),
      ),
    );
  }
}

class _ResetTitle extends StatelessWidget {
  const _ResetTitle();

  @override
  Widget build(BuildContext context) {
    return Column( 
      crossAxisAlignment: CrossAxisAlignment.start, 
      children: [
        const Text(
          'Reset your password',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),

        Text(
          'Enter the email linked to your account and we will send a reset link.',
          style: TextStyle(color: Colors.grey[700]),
        ),
      ],
    );
  }
}

// Field label text shown above the email field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }
}