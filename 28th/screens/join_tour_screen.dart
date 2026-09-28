// ============================================================
// join_tour_screen.dart
// ============================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../repositories/tour_repository.dart';
import '../models/tour.dart';
import 'tourist_pre_start_screen.dart';

const _brandBlue = Color(0xFF1F4E9E);
const _brandYellow = Color(0xFFFFDE59);

class JoinTourScreen extends StatefulWidget {
  const JoinTourScreen({super.key, this._repository});

  final TourRepository? _repository;

  @override
  State<JoinTourScreen> createState() => _JoinTourScreenState();
}

class _JoinTourScreenState extends State<JoinTourScreen> {
  final _codeController = TextEditingController();
  late final TourRepository _repository =
      widget._repository ?? TourRepository();
  String? _errorMessage;
  bool _isJoining = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinWithCode(String value) async {
    final code = value.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Enter a tour code to continue.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _errorMessage = 'Please sign in as a tourist first.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _errorMessage = null;
      _isJoining = true;
    });

    try {
      final joinedTour = await _repository.joinTour(
        joinCode: code,
        userUid: user.uid,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TourJoinSuccessScreen(
            tourId: joinedTour.id,
            tourName: joinedTour.name,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Tour not found. Please check the code and try again.');
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _scanQrCode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (code != null && mounted) await _joinWithCode(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TourTrack', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        foregroundColor: _brandBlue,
        backgroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            const Icon(Icons.group_add_outlined, size: 64, color: _brandBlue),
            const SizedBox(height: 20),
            const Text(
              'Join a Tour',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _brandBlue,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please enter the code provided by your guide',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black87, height: 1.4),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Tour code',
                hintText: 'e.g. A1B2C3',
                prefixIcon: const Icon(Icons.key_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: _isJoining ? null : _joinWithCode,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isJoining
                    ? null
                    : () => _joinWithCode(_codeController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandYellow,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isJoining
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Or', style: TextStyle(color: Colors.black54)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 30),
            Center(
              child: Column(
                children: [
                  InkWell(
                    onTap: _isJoining ? null : _scanQrCode,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 85,
                      height: 85,
                      decoration: BoxDecoration(
                        color: _brandYellow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.black,
                        size: 45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scan QR',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        _hasScanned = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(color: _brandBlue),
        title: const Text('Scan QR code', style: TextStyle(color: _brandBlue, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: _brandYellow, width: 4),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text(
              'Position the tour QR code inside the frame.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class TourJoinSuccessScreen extends StatefulWidget {
  const TourJoinSuccessScreen({super.key, required this.tourId, this.tourName});

  final String tourId;
  final String? tourName;

  @override
  State<TourJoinSuccessScreen> createState() => _TourJoinSuccessScreenState();
}

class _TourJoinSuccessScreenState extends State<TourJoinSuccessScreen> {
  bool _isLoading = false;

  Future<void> _viewTourDetails() async {
    setState(() => _isLoading = true);
    try {
      final tour = await TourRepository().getTour(widget.tourId);
      if (!mounted) return;

      if (tour != null) {
        // Pop the success screen and join screen, returning to TouristHomeScreen, then push PreStart
        Navigator.of(context).pop(); // pop success screen
        Navigator.of(context).pop(); // pop join screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TouristPreStartScreen(tour: tour),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load tour details. Try opening from home.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _returnHome() {
    // Pop success screen and join screen to land back cleanly on TouristHomeScreen
    Navigator.of(context).pop(); // pop success screen
    Navigator.of(context).pop(); // pop join screen
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/images/JoinTourBackground.png"),
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _brandYellow, width: 3),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 40,
                        color: _brandYellow,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Success!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Congratulations! You have successfully joined '
                      '"${widget.tourName ?? 'the tour'}"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _viewTourDetails,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandYellow,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'View Tour Details',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _returnHome,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brandBlue,
                          side: const BorderSide(color: _brandBlue, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'Return Home',
                          style: TextStyle(fontWeight: FontWeight.w700),
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
    );
  }
}