// ============================================================
// share_code_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/tour.dart';

const _kBrandBlue = Color(0xFF1F4E9E);

class ShareCodeScreen extends StatelessWidget {
  const ShareCodeScreen({super.key, required this.tour});

  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final inviteLink = 'https://tourtrack.app/join?code=${tour.joinCode}';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'TourTrack',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: _kBrandBlue,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              // Tour Name Header
              Text(
                tour.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              const Text(
                'QR Code',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              QrImageView(
                data: inviteLink,
                size: 200,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 20),
              Row(
                children: const [
                  Expanded(child: Divider(indent: 20, endIndent: 12)),
                  Text('Or', style: TextStyle(color: Colors.black54)),
                  Expanded(child: Divider(indent: 12, endIndent: 20)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Join Code',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F3F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tour.joinCode,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: inviteLink));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invite link copied to clipboard!')),
                  );
                },
                icon: const Icon(Icons.copy, size: 18, color: _kBrandBlue),
                label: const Text(
                  'Copy Invite Link',
                  style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 24),
              Image.asset('assets/images/bird_logo.png', width: 80),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}