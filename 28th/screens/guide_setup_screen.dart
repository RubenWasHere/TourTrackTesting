// ============================================================
// guide_setup_screen.dart
//
// Identical layout structure to TouristSetupScreen, configured
// for guides (collects photo, name, phone number, and saves via
// GuideAccountService).
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/guide_account_service.dart';
import 'calendar_onboarding_screen.dart'; // <-- Added import for calendar onboarding

// ---------------- BRAND COLORS ----------------
const _kBrandBlue = Color(0xFF1F4E9E);
const _kBrandYellow = Color(0xFFFFDE59);
const _kBrandYellowLight = Color(0xFFFFF4CC);

class _CountryCode {
  final String code;
  final String flag;
  final String name;
  const _CountryCode(this.code, this.flag, this.name);
}

const _countryCodes = [
  _CountryCode('+64', '🇳🇿', 'New Zealand'),
  _CountryCode('+61', '🇦🇺', 'Australia'),
  _CountryCode('+1', '🇺🇸', 'United States'),
  _CountryCode('+44', '🇬🇧', 'United Kingdom'),
];

class GuideSetupScreen extends StatefulWidget {
  const GuideSetupScreen({super.key});

  @override
  State<GuideSetupScreen> createState() => _GuideSetupScreenState();
}

class _GuideSetupScreenState extends State<GuideSetupScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _scrollController = ScrollController();
  final _guideAccountService = GuideAccountService();

  _CountryCode _selectedCountry = _countryCodes.first;
  File? _photoFile;
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add Guide Profile Picture',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: _kBrandBlue),
                  title: const Text('Take a picture', style: TextStyle(fontSize: 16)),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: _kBrandBlue),
                  title: const Text('Choose from gallery', style: TextStyle(fontSize: 16)),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (pickedFile == null) return;

    setState(() {
      _photoFile = File(pickedFile.path);
    });
  }

  void _setAuthError(String message) {
    setState(() => _errorMessage = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleLetsGo() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() => _errorMessage = null);

    if (name.isEmpty) {
      _setAuthError('Please enter your name.');
      return;
    }
    if (phone.isEmpty) {
      _setAuthError('Please enter your phone number.');
      return;
    }

    final digitsOnly = RegExp(r'^[0-9]+$');
    if (!digitsOnly.hasMatch(phone) || phone.length < 7 || phone.length > 11) {
      _setAuthError("That phone number doesn't look quite right, try again.");
      return;
    }

    final confirmed = await _showConfirmationDialog(name: name, phone: phone);
    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      await _guideAccountService.saveGuideProfile(
        name: name,
        fullPhoneNumber: '${_selectedCountry.code}$phone',
        photoFile: _photoFile,
      );

      if (!mounted) return;

      // Navigate to Calendar Onboarding Screen instead of Home directly
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CalendarOnboardingScreen()),
      );
    } catch (e, stackTrace) {
      debugPrint('saveGuideProfile failed with error: $e');
      debugPrint('Stack trace: $stackTrace');
      _setAuthError('Something went wrong, please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showPrivacyPolicyModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _kBrandBlue,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: const [
                        Text(
                          'Last updated: September 2026',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '1. Information We Collect',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'We collect information you provide directly to us when creating a guide account, such as your name, email address, and phone number, as well as profile pictures for tourist coordination purposes.',
                          style: TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '2. How We Use Your Information',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Your details are used strictly to coordinate your tour groups and identify you as an official guide.',
                          style: TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '3. Data Security',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'We take reasonable measures to protect information about you from loss, theft, misuse, and unauthorized access.',
                          style: TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool?> _showConfirmationDialog({
    required String name,
    required String phone,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Does this look right?',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: ClipOval(
                      child: _photoFile != null
                          ? Image.file(
                              _photoFile!,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 90,
                              height: 90,
                              color: _kBrandYellowLight,
                              child: const Icon(
                                Icons.person,
                                size: 45,
                                color: _kBrandBlue,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ConfirmRow(label: 'Name', value: name),
                  const SizedBox(height: 12),
                  _ConfirmRow(
                    label: 'Phone',
                    value: '${_selectedCountry.code} $phone',
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Edit',
                            style: TextStyle(fontSize: 16, color: Colors.black87),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kBrandYellow,
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            "Yes, that's right",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _scrollController.dispose();
    super.dispose();
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
              // Header & Language Pill
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

              // Scrollable Form Content
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "You're almost in",
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Set up your guide profile',
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
                            errorBuilder: (_, __, ___) => const SizedBox(width: 80, height: 80),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: GestureDetector(
                          onTap: _pickPhoto,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: const BoxDecoration(
                              color: _kBrandYellowLight,
                              shape: BoxShape.circle,
                            ),
                            child: CustomPaint(
                              painter: _DashedCirclePainter(
                                color: _kBrandYellow,
                              ),
                              child: _photoFile == null
                                  ? const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.camera_alt_outlined,
                                            size: 32,
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Add photo',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ClipOval(
                                      child: Image.file(
                                        _photoFile!,
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your name',
                        style: TextStyle(fontSize: 15, color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'e.g. Captain Alex',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: _kBrandBlue,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Phone Number',
                        style: TextStyle(fontSize: 15, color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<_CountryCode>(
                                    value: _selectedCountry,
                                    icon: const Icon(Icons.keyboard_arrow_down),
                                    items: _countryCodes.map((country) {
                                      return DropdownMenuItem(
                                        value: country,
                                        child: Text(
                                          '${country.flag} ${country.code}',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() => _selectedCountry = value);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  hintText: '212345678',
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade400,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: _kBrandBlue,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            height: 1.3,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Your name and photo will be visible to your tour group '
                              'and participants for identification purposes. Learn more in our ',
                            ),
                            WidgetSpan(
                              child: InkWell(
                                onTap: _showPrivacyPolicyModal,
                                child: const Text(
                                  'privacy policy',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _kBrandBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Pinned Bottom Action Button Area
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: Colors.white,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleLetsGo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBrandYellow,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.black87,
                            ),
                          )
                        : const Text(
                            "Let's go",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
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
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  const _ConfirmRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  const _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius - 1.5);

    const dashWidth = 6.0;
    const gapWidth = 6.0;
    final circumference = 2 * 3.14159265 * radius;
    final dashCount = (circumference / (dashWidth + gapWidth)).floor();

    final sweepPerDash =
        (2 * 3.14159265) / dashCount * (dashWidth / (dashWidth + gapWidth));
    final sweepPerGap =
        (2 * 3.14159265) / dashCount * (gapWidth / (dashWidth + gapWidth));

    double startAngle = 0;
    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(rect, startAngle, sweepPerDash, false, paint);
      startAngle += sweepPerDash + sweepPerGap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) => false;
}