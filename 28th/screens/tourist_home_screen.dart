// ============================================================
// tourist_home_screen.dart
// ============================================================
// Participant home screen featuring profile information, the Join Tour
// entry button, and a live stream of all joined tours leading into
// the TouristPreStartScreen.
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/tourist_account_service.dart';
import '../widgets/location_permission_gate.dart';
import '../repositories/tour_repository.dart';
import '../models/tourist_profile.dart';
import '../models/tour.dart';
import 'join_tour_screen.dart';
import 'tourist_pre_start_screen.dart';
import 'tourist_settings_screen.dart';

const _kBrandBlue = Color(0xFF1F4E9E);
const _kBrandYellow = Color(0xFFFFDE59);
const _kJoinFill = Color(0xFFFFF7E0);

class TouristHomeScreen extends StatelessWidget {
  const TouristHomeScreen({super.key, this.repository});

  final TourRepository? repository;

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final tourRepository = repository ?? TourRepository();

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
                child: StreamBuilder<TouristProfile?>(
                  stream: TouristAccountService().watchCurrentTouristProfile(),
                  builder: (context, profileSnapshot) {
                    final profile = profileSnapshot.data;
                    final touristName = profile?.name ?? 'Tourist';
                    final photoUrl = profile?.photoUrl;

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        // Header: Logo & Settings Cog
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
                                    builder: (_) => TouristSettingsScreen.fromTouristHome(
                                      onEditProfileTap: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Open profile editing flow here!')),
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Welcome Profile Header
                        _TouristWelcomeHeader(name: touristName, photoUrl: photoUrl),
                        const SizedBox(height: 28),

                        // Join Tour circular button
                        Center(
                          child: _JoinTourButton(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const JoinTourScreen()),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Joined Tours Stream with polished empty card fallback
                        StreamBuilder<List<Tour>>(
                          stream: tourRepository.getJoinedToursForTourist(currentUserId),
                          builder: (context, snapshot) {
                            final tours = snapshot.data ?? [];
                            final isLoading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'My Joined Tours',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (isLoading)
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
                                        'No joined tours yet. Tap "Join Tour" above to enter a tour code!',
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
                                      return _JoinedTourCard(tour: tours[index]);
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

class _TouristWelcomeHeader extends StatelessWidget {
  const _TouristWelcomeHeader({required this.name, this.photoUrl});

  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Ready for your next adventure?',
          style: TextStyle(
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

class _JoinTourButton extends StatelessWidget {
  const _JoinTourButton({required this.onTap});

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
          color: _kJoinFill,
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
          'Join Tour',
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

class _JoinedTourCard extends StatelessWidget {
  const _JoinedTourCard({required this.tour});

  final Tour tour;

  (String, bool) _getTimeStatus(DateTime? scheduledAt) {
    if (scheduledAt == null) return (tour.status, false);

    final now = DateTime.now();
    final difference = scheduledAt.difference(now);

    if (difference.isNegative) {
      final absDiff = difference.abs();
      if (absDiff.inMinutes <= 5) {
        return ('Starting now', true);
      }
      return ('In progress or completed', false);
    } else {
      if (difference.inDays > 0) {
        return ('Starts in ${difference.inDays}d ${difference.inHours % 24}h', false);
      } else if (difference.inHours > 0) {
        return ('Starts in ${difference.inHours}h ${difference.inMinutes % 60}m', false);
      } else if (difference.inMinutes > 0) {
        return ('Starts in ${difference.inMinutes}m', false);
      } else {
        return ('Starting soon!', true);
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
    final (timeStatusText, isReady) = _getTimeStatus(tour.scheduledAt);
    final formattedDate = _formatOriginalDate(tour.scheduledAt);

    return Container(
      height: 120,
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
                            fontWeight: isReady ? FontWeight.bold : FontWeight.w600,
                            color: isReady ? const Color(0xFF4CAF50) : (hasPhoto ? Colors.white70 : Colors.grey[700]),
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => TouristPreStartScreen(tour: tour),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _kBrandBlue,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'View Tour',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
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