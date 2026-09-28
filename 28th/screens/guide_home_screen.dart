// ============================================================
// guide_home_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/guide_account_service.dart';
import '../widgets/location_permission_gate.dart';
import 'tour_config_screen.dart';
import 'share_code_screen.dart';
import 'guide_settings_screen.dart';
import 'tour_pre_start_screen.dart';
import '../models/tour.dart';
import '../repositories/tour_repository.dart';

const _kBrandBlue = Color(0xFF1F4E9E);
const _kBrandYellow = Color(0xFFFFDE59);
const _kCreateFill = Color(0xFFFFF7E0);
const _kNotReadyBlack = Color(0xFF1A1A1A);

class GuideHomeScreen extends StatelessWidget {
  const GuideHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final guideService = GuideAccountService();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return PopScope(
      canPop: false, // Silently blocks hardware back button to prevent accidental exit
      child: LocationPermissionGate(
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              const Positioned.fill(
                child: Image(
                  image: AssetImage('assets/images/HomePageBackground.png'),
                  fit: BoxFit.cover,
                ),
              ),
              SafeArea(
                child: StreamBuilder<Map<String, dynamic>?>(
                  stream: guideService.watchCurrentGuideProfile(),
                  builder: (context, profileSnapshot) {
                    final profileData = profileSnapshot.data;
                    final guideName = profileData?['name'] ?? 'Guide';
                    final photoUrl = profileData?['photoUrl'];

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        // Header: Centered Logo & Settings Cog
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox(width: 40),
                            const Text(
                              'TourTrack',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: _kBrandBlue,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.settings_outlined,
                                color: Colors.black87,
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const GuideSettingsScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Friendly Welcome & Live Profile Avatar with Dynamic Greetings
                        _WelcomeHeader(name: guideName, photoUrl: photoUrl),
                        const SizedBox(height: 28),

                        // Create Tour circular button
                        Center(
                          child: _CreateTourButton(
                            onTap: () async {
                              final String? tourId = await Navigator.of(context).push<String>(
                                MaterialPageRoute(
                                  builder: (context) => const TourConfigScreen(),
                                ),
                              );

                              if (tourId != null && context.mounted) {
                                final Tour? newTour = await TourRepository().getTour(tourId);
                                if (newTour != null && context.mounted) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => ShareCodeScreen(tour: newTour),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Real Scheduled Tours Stream using TourRepository
                        StreamBuilder<List<Tour>>(
                          stream: TourRepository().getScheduledToursForGuide(currentUserId),
                          builder: (context, snapshot) {
                            final tours = snapshot.data ?? [];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Scheduled Tours',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (snapshot.connectionState == ConnectionState.waiting)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(20.0),
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (tours.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'No scheduled tours yet. Tap "Create Tour" above to start one!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey, fontSize: 14),
                                      ),
                                    ),
                                  )
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: tours.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      return _TourCard(tour: tours[index]);
                                    },
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.name, this.photoUrl});

  final String name;
  final String? photoUrl;

  String _getDynamicGreeting() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.metadata.creationTime != null) {
      final accountAge = DateTime.now().difference(user.metadata.creationTime!);
      if (accountAge.inMinutes < 2) {
        return 'Welcome to TourTrack';
      }
    }

    const messages = [
      'Ready to lead the pack today?',
      'Where to next, Captain?',
      'Let\'s make this tour unforgettable.',
      'Time to hit the trail!',
      'All set for a great adventure?',
      'How\'s it going?',
      'Try not to lose anyone in the gift shop this time.',
      'Yes, there will be bathroom breaks. No, not right now.',
      'Time to pretend you know the history of that random building.',
      'May your microphone battery outlast the crowd\'s questions.',
    ];

    final randomIndex = DateTime.now().minute % messages.length;
    return messages[randomIndex];
  }

  @override
  Widget build(BuildContext context) {
    final greetingText = _getDynamicGreeting();

    return Column(
      children: [
        Text(
          greetingText,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF8FC7EE),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: photoUrl != null && photoUrl!.isNotEmpty
                ? Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                          ),
                    errorBuilder: (_, _, _) => const Icon(Icons.person, color: Colors.white, size: 40),
                  )
                : const Icon(Icons.person, color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _CreateTourButton extends StatelessWidget {
  const _CreateTourButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kCreateFill,
          border: Border.all(color: _kBrandYellow, width: 6),
          boxShadow: [
            BoxShadow(
              color: _kBrandYellow.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Text(
          'Create Tour',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({required this.tour});

  final Tour tour;

  (String, bool, bool) _getTimeStatus(DateTime? scheduledAt) {
    if (scheduledAt == null) return (tour.status, false, false);

    final now = DateTime.now();
    final difference = scheduledAt.difference(now);

    if (difference.isNegative) {
      final absDiff = difference.abs();
      if (absDiff.inMinutes <= 5) {
        return ('Starting now', true, false);
      }

      if (absDiff.inDays > 0) {
        return ('Overdue by ${absDiff.inDays}d ${absDiff.inHours % 24}h', false, true);
      } else if (absDiff.inHours > 0) {
        return ('Overdue by ${absDiff.inHours}h ${absDiff.inMinutes % 60}m', false, true);
      } else {
        return ('Overdue (${absDiff.inMinutes}m ago)', false, true);
      }
    } else {
      if (difference.inDays > 0) {
        return ('${difference.inDays}d ${difference.inHours % 24}h remaining', false, false);
      } else if (difference.inHours > 0) {
        return ('${difference.inHours}h ${difference.inMinutes % 60}m remaining', false, false);
      } else if (difference.inMinutes > 0) {
        return ('${difference.inMinutes}m remaining', false, false);
      } else {
        return ('Starting soon!', true, false);
      }
    }
  }

  String _formatOriginalDate(DateTime? dt) {
    if (dt == null) return '';
    final hourStr = dt.hour.toString().padLeft(2, '0');
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} at $hourStr:$minuteStr';
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = tour.photoUrl != null && tour.photoUrl!.trim().isNotEmpty;
    final (timeStatusText, isReady, isOverdue) = _getTimeStatus(tour.scheduledAt);
    final formattedDate = _formatOriginalDate(tour.scheduledAt);

    Color? textColor;
    if (isReady) {
      textColor = const Color(0xFF4CAF50);
    } else if (isOverdue) {
      textColor = const Color(0xFFFF6B6B);
    } else {
      textColor = hasPhoto ? Colors.white70 : Colors.grey[700];
    }

    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE9E9E9)),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            if (hasPhoto) ...[
              Positioned.fill(
                child: Transform.scale(
                  scale: 1.15,
                  child: Image.network(
                    tour.photoUrl!.trim(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tour.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: hasPhoto ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeStatusText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: (isReady || isOverdue) ? FontWeight.bold : FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (formattedDate.isNotEmpty)
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: hasPhoto ? Colors.white60 : Colors.grey[500],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _EditPill(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => TourConfigScreen(existingTour: tour),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 5),
                      _ViewPill(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => TourPreStartScreen(tour: tour),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 5),
                      tour.scheduledAt != null
                          ? GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => ShareCodeScreen(tour: tour),
                                  ),
                                );
                              },
                              child: const _StatusPill(
                                label: 'Share Code',
                                background: _kBrandBlue,
                                textColor: Colors.white,
                              ),
                            )
                          : const _StatusPill(
                              label: 'Not Ready',
                              background: _kNotReadyBlack,
                              textColor: Colors.white,
                            ),
                    ],
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

class _EditPill extends StatelessWidget {
  const _EditPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _kBrandYellow,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit, size: 12, color: Colors.black87),
            SizedBox(width: 4),
            Text(
              'Edit',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewPill extends StatelessWidget {
  const _ViewPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _kBrandBlue, width: 1.2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_outlined, size: 12, color: _kBrandBlue),
            SizedBox(width: 4),
            Text(
              'View',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _kBrandBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.background,
    required this.textColor,
  });

  final String label;
  final Color background;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}
