// ============================================================
// screens/calendar_onboarding_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/calendar_sync_service.dart';
import '../repositories/tour_repository.dart';
import 'guide_home_screen.dart';

const _kBrandBlue = Color(0xFF1F4E9E);
const _kBrandYellow = Color(0xFFFFDE59);

class CalendarOnboardingScreen extends StatefulWidget {
  const CalendarOnboardingScreen({super.key});

  @override
  State<CalendarOnboardingScreen> createState() => _CalendarOnboardingScreenState();
}

class _CalendarOnboardingScreenState extends State<CalendarOnboardingScreen> {
  bool _isLoading = false;

  Future<void> _enableSync(BuildContext context) async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('guide_auto_sync_calendar', true);
      await prefs.setBool('has_seen_calendar_onboarding', true);

      // This triggers the native OS permission prompt naturally with full context
      final service = CalendarSyncService();
      final hasPermission = await service.requestPermissions();

      if (hasPermission) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final tours = await TourRepository().getScheduledToursForGuide(user.uid).first;
          await service.syncAllUpcomingTours(
            tours,
            onEventSynced: (tourId, calendarEventId) async {
              await TourRepository().updateTour(tourId, calendarEventId: calendarEventId);
            },
          );
        }
      }
    } catch (e) {
      debugPrint('Error during calendar onboarding sync: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _navigateToHome(context);
      }
    }
  }

  Future<void> _skip(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('guide_auto_sync_calendar', false);
    await prefs.setBool('has_seen_calendar_onboarding', true);
    if (!context.mounted) return;
    _navigateToHome(context);
  }

  void _navigateToHome(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const GuideHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _kBrandBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  size: 64,
                  color: _kBrandBlue,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Sync Tours to Your Calendar',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _kBrandBlue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'TourTrack can automatically add your scheduled tours to your devices default calendar app. Never miss a departure or double-book your day!',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrandBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : () => _enableSync(context),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Enable Auto-Sync',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isLoading ? null : () => _skip(context),
                child: const Text(
                  'Skip for now',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}