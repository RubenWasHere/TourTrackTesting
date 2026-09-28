// ============================================================
// guide_login_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/guide_account_service.dart';
import '../services/notification_service.dart';
import 'guide_home_screen.dart';
import 'guide_setup_screen.dart';
import 'guide_signup_screen.dart';
import 'reset_password_screen.dart';

// Brand colors
const _kBrandBlue = Color(0xFF1F4E9E);
const _kBrandYellow = Color(0xFFFFDE59);
const _kFieldFill = Color(0xFFF3F3F3);
const _kBorderGrey = Color(0xFFE0E0E0);

// Public screen widget for the guide sign-in page.
class GuideLoginScreen extends StatefulWidget {
  const GuideLoginScreen({super.key});

  @override
  State<GuideLoginScreen> createState() => _GuideLoginScreenState();
}

// Holds the login form state, controllers, submission logic, and error UI.
class _GuideLoginScreenState extends State<GuideLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _guideAccountService = GuideAccountService();
  final _notificationService = NotificationService();

  String? _loadingAction;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _emailValid = false;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _isLoading => _loadingAction != null;

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
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loadingAction = 'login';
      _errorMessage = null;
    });

    try {
      final credential = await _authService.signInWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );

      // Check if email login requires profile setup
      final user = credential.user;
      bool needsSetup = false;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('guides')
            .doc(user.uid)
            .get();
        needsSetup = !doc.exists || doc.data()?['name'] == null;
      }

      await _guideAccountService.createOrUpdateGuideAccount(credential);

      await _notificationService.initialise();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              needsSetup ? const GuideSetupScreen() : const GuideHomeScreen(),
        ),
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _loadingAction = null);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loadingAction = 'google';
      _errorMessage = null;
    });

    try {
      final credential = await _authService.signInWithGoogle();

      final user = credential.user;
      bool needsSetup = false;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('guides')
            .doc(user.uid)
            .get();
        needsSetup = !doc.exists || doc.data()?['name'] == null;
      }

      await _guideAccountService.createOrUpdateGuideAccount(credential);

      await _notificationService.initialise();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              needsSetup ? const GuideSetupScreen() : const GuideHomeScreen(),
        ),
      );
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingAction = null);
      }
    }
  }

  Future<void> _signInWithFacebook() async {
    setState(() {
      _loadingAction = 'facebook';
      _errorMessage = null;
    });

    try {
      final credential = await _authService.signInWithFacebook();

      final user = credential.user;
      bool needsSetup = false;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('guides')
            .doc(user.uid)
            .get();
        needsSetup = !doc.exists || doc.data()?['name'] == null;
      }

      await _guideAccountService.createOrUpdateGuideAccount(credential);

      await _notificationService.initialise();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              needsSetup ? const GuideSetupScreen() : const GuideHomeScreen(),
        ),
      );
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingAction = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Column(
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.chevron_left, size: 22),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'TourTrack',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: _kBrandBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 42),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _kBrandYellow,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'English',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.language, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Welcome Back',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Let's get you logged back in",
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Image.asset(
                              'assets/images/bird_logo.png',
                              width: 80,
                              height: 80,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox(width: 80, height: 80),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        const _FieldLabel('Email address'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(
                            hintText: 'example@gmail.com',
                            suffixIcon: _emailValid
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.black87,
                                  )
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
                        const SizedBox(height: 16),
                        const _FieldLabel('Password'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: _fieldDecoration(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: Colors.grey[600],
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: _required,
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
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ResetPasswordScreen(),
                                    ),
                                  ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _signIn,
                            style: FilledButton.styleFrom(
                              backgroundColor: _kBrandYellow,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _loadingAction == 'login'
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Text(
                                    'Log In',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _OrDivider(label: 'Or Login with'),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _SocialIconButton(
                              isLoading: _loadingAction == 'facebook',
                              onPressed: _isLoading
                                  ? null
                                  : _signInWithFacebook,
                              icon: SvgPicture.asset(
                                'assets/images/facebook_icon.svg',
                                width: 22,
                                height: 22,
                              ),
                            ),
                            _SocialIconButton(
                              isLoading: _loadingAction == 'google',
                              onPressed: _isLoading ? null : _signInWithGoogle,
                              icon: SvgPicture.asset(
                                'assets/images/google_icon.svg',
                                width: 22,
                                height: 22,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => const GuideSignupScreen(),
                                    ),
                                  ),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  color: Colors.grey[800],
                                  fontSize: 14,
                                ),
                                children: const [
                                  TextSpan(text: "Don't have an account? "),
                                  TextSpan(
                                    text: 'Sign up',
                                    style: TextStyle(
                                      color: _kBrandBlue,
                                      fontWeight: FontWeight.w700,
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
                ),
              ),
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

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: _kBorderGrey)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ),
        const Expanded(child: Divider(color: _kBorderGrey)),
      ],
    );
  }
}

class _SocialIconButton extends StatelessWidget {
  const _SocialIconButton({
    required this.icon,
    required this.onPressed,
    required this.isLoading,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _kBorderGrey, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : icon,
      ),
    );
  }
}
