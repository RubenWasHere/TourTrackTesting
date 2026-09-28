// ============================================================
// tour_pre_start_screen.dart
// ============================================================
// This screen manages the tour pre-start lobby, displaying live participant
// attendance, weather forecasts, meeting point maps, and guide location broadcasting.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../models/tour.dart';
import '../repositories/location_repository.dart';
import '../services/location_service.dart';
import 'tracking_screen.dart';

const _kBrandBlue = Color(0xFF1F4E9E);
const _kFieldFill = Color(0xFFF3F3F3);
const _kBorderGrey = Color(0xFFE0E0E0);
const _kDialogBg = Color(0xFFFFFDF5);

class TourPreStartScreen extends StatefulWidget {
  const TourPreStartScreen({super.key, required this.tour});

  final Tour tour;

  @override
  State<TourPreStartScreen> createState() => _TourPreStartScreenState();
}

class _TourPreStartScreenState extends State<TourPreStartScreen> with SingleTickerProviderStateMixin {
  final LocationRepository _locationRepository = LocationRepository();
  final LocationService _locationService = LocationService();
  
  GoogleMapController? _mapController;
  double _dragValue = 0.0;
  bool _isCompleted = false;
  Timer? _tickerTimer;

  // Attendance & Tracking Subscriptions
  StreamSubscription<QuerySnapshot>? _participantsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _unifiedTrackingSubscription;
  StreamSubscription<Position>? _guideLocationSubscription;
  
  final Map<String, bool> _participantAttendanceMap = {};
  
  // Cached state to prevent UI-build side effects
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestDocs = [];
  int _arrivedCountCache = 0;

  // Weather state variables
  Map<String, dynamic>? _weatherData;
  bool _isLoadingWeather = true;

  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    _fetchWeather();
    _startParticipantsStream();
    _startUnifiedTrackingListener(); 
    _startGuideLocationBroadcasting(); // Broadcasts guide's live location during pre-start lobby

    // Live tick every second to keep countdowns and elapsed timers ticking smoothly
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _participantsSubscription?.cancel();
    _unifiedTrackingSubscription?.cancel();
    _guideLocationSubscription?.cancel();
    _spinController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  /// Broadcasts the guide's live position to Firestore using the optimized 2m/2s location settings.
  void _startGuideLocationBroadcasting() {
    _guideLocationSubscription = _locationService.getPositionStream().listen((Position position) {
      if (!mounted) return;

      FirebaseFirestore.instance
          .collection('tours')
          .doc(widget.tour.id)
          .collection('locations')
          .doc(widget.tour.guideUid)
          .set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'role': 'guide',
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Listens to the static participants collection to track attendance flags.
  void _startParticipantsStream() {
    _participantsSubscription = FirebaseFirestore.instance
        .collection('tours')
        .doc(widget.tour.id)
        .collection('participants')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['hasAttended'] == true) {
            _participantAttendanceMap[doc.id] = true;
          }
        }
      });
      _evaluateProximity(_latestDocs);
    });
  }

  /// Listens continuously to location changes in the background and evaluates proximity.
  void _startUnifiedTrackingListener() {
    _unifiedTrackingSubscription = _locationRepository
        .getTourLocations(widget.tour.id)
        .listen((snapshot) {
      if (!mounted) return;
      _latestDocs = snapshot.docs;
      _evaluateProximity(_latestDocs);
    });
  }

  /// Evaluates tourist proximity independently of UI builds with optimistic local updates.
  void _evaluateProximity(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) return;

    double? anchorLat;
    double? anchorLng;
    try {
      final guideDoc = docs.firstWhere(
        (doc) => doc.data()['role'] == 'guide' || doc.id == widget.tour.guideUid,
      );
      anchorLat = guideDoc.data()['latitude'] as double?;
      anchorLng = guideDoc.data()['longitude'] as double?;
    } catch (_) {}

    anchorLat ??= widget.tour.startLocationLat;
    anchorLng ??= widget.tour.startLocationLng;

    if (anchorLat == null || anchorLng == null) return;

    final radiusMeters = widget.tour.greenRadiusMeters ?? 50.0;
    int activeCount = 0;

    for (var doc in docs) {
      final data = doc.data();
      final role = data['role'] as String? ?? 'tourist';
      if (role == 'guide') continue;

      final touristUid = doc.id;
      final hasAttended = _participantAttendanceMap[touristUid] == true;

      if (hasAttended) {
        activeCount++;
        continue;
      }

      final lat = data['latitude'] as double?;
      final lng = data['longitude'] as double?;

      if (lat != null && lng != null) {
        final distance = Geolocator.distanceBetween(anchorLat, anchorLng, lat, lng);
        if (distance <= radiusMeters) {
          // Optimistic local state update
          _participantAttendanceMap[touristUid] = true;

          // Sync to Firestore immediately from background listener
          FirebaseFirestore.instance
              .collection('tours')
              .doc(widget.tour.id)
              .collection('participants')
              .doc(touristUid)
              .set({
            'hasAttended': true,
            'attendedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          activeCount++;
        }
      }
    }

    if (mounted && _arrivedCountCache != activeCount) {
      setState(() {
        _arrivedCountCache = activeCount;
      });
    }
  }

  Future<void> _fetchWeather() async {
    final lat = widget.tour.startLocationLat;
    final lng = widget.tour.startLocationLng;

    if (lat == null || lng == null) {
      if (mounted) setState(() => _isLoadingWeather = false);
      return;
    }

    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current=temperature_2m,weather_code',
      );
      final response = await http.get(url);
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _weatherData = data['current'] as Map<String, dynamic>?;
          _isLoadingWeather = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingWeather = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  (String, IconData) _getWeatherCondition(int code) {
    switch (code) {
      case 0: return ('Clear sky', Icons.wb_sunny_outlined);
      case 1: case 2: case 3: return ('Partly cloudy', Icons.cloud_queue);
      case 45: case 48: return ('Foggy', Icons.foggy);
      case 51: case 53: case 55: case 56: case 57: return ('Drizzle', Icons.grain);
      case 61: case 63: case 65: case 66: case 67: return ('Rain', Icons.umbrella_outlined);
      case 71: case 73: case 75: case 77: return ('Snow', Icons.ac_unit);
      case 95: case 96: case 99: return ('Thunderstorm', Icons.flash_on);
      default: return ('Fair', Icons.wb_cloudy_outlined);
    }
  }

  void _onPanUpdate(DragUpdateDetails details, double maxWidth) {
    if (_isCompleted) return;
    setState(() {
      const thumbWidth = 60.0;
      final slideRange = maxWidth - thumbWidth;
      if (slideRange <= 0) return;

      _dragValue += details.delta.dx / slideRange;
      _dragValue = _dragValue.clamp(0.0, 1.0);
    });
  }

  Future<bool> _checkShouldWarnBeforeStart() async {
    final timingState = _getTourTimingState(widget.tour.scheduledAt).$2;
    bool isEarly = timingState == 0;

    bool someoneMissing = false;
    try {
      final touristDocs = _latestDocs.where((doc) {
        final role = doc.data()['role'] as String? ?? 'tourist';
        return role != 'guide';
      }).toList();

      final totalTourists = touristDocs.length;
      int arrivedCount = 0;
      for (var doc in touristDocs) {
        if (_participantAttendanceMap[doc.id] == true) {
          arrivedCount++;
        }
      }
      if (arrivedCount < totalTourists) {
        someoneMissing = true;
      }
    } catch (_) {}

    if (!isEarly && !someoneMissing) return true;

    String message = '';
    if (isEarly && someoneMissing) {
      message = 'This tour is scheduled for a future time, and not all participants have checked in yet. Are you sure you want to start now?';
    } else if (isEarly) {
      message = 'This tour is scheduled for a future time. Are you sure you want to start early?';
    } else {
      message = 'Not all participants have checked in yet. Are you sure you want to begin before everyone arrives?';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kDialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Start Tour Warning',
          style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold),
        ),
        content: Text(message, style: const TextStyle(color: Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start Anyway', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _onPanEnd(double maxWidth) async {
    if (_isCompleted) return;

    if (_dragValue > 0.85) {
      final proceed = await _checkShouldWarnBeforeStart();
      if (!proceed) {
        setState(() {
          _dragValue = 0.0;
        });
        return;
      }

      setState(() {
        _dragValue = 1.0;
        _isCompleted = true;
      });

      await _spinController.forward();

      if (!mounted) return;

      try {
        await FirebaseFirestore.instance
            .collection('tours')
            .doc(widget.tour.id)
            .update({'status': 'active'})
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        if (!mounted) return;
        _spinController.reset();
        setState(() {
          _dragValue = 0.0;
          _isCompleted = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start the tour. Check your connection and try again.'),
          ),
        );
        return;
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => TrackingScreen(
            tourId: widget.tour.id,
            role: TrackingRole.guide,
          ),
        ),
      );
    } else {
      setState(() {
        _dragValue = 0.0;
      });
    }
  }

  Future<void> _openDirections() async {
    final lat = widget.tour.startLocationLat;
    final lng = widget.tour.startLocationLng;

    if (lat == null || lng == null) return;

    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  (String, int) _getTourTimingState(DateTime? scheduledAt) {
    if (scheduledAt == null) return ('Ready to start anytime', 1);

    final now = DateTime.now();

    if (now.isBefore(scheduledAt)) {
      final difference = scheduledAt.difference(now);
      if (difference.inDays > 0) {
        return ('Starts in ${difference.inDays}d ${difference.inHours % 24}h ${difference.inMinutes % 60}m ${difference.inSeconds % 60}s', 0);
      } else if (difference.inHours > 0) {
        return ('Starts in ${difference.inHours}h ${difference.inMinutes % 60}m ${difference.inSeconds % 60}s', 0);
      } else if (difference.inMinutes > 0) {
        return ('Starts in ${difference.inMinutes}m ${difference.inSeconds % 60}s', 0);
      } else {
        return ('Starts in ${difference.inSeconds}s', 0);
      }
    }

    final elapsed = now.difference(scheduledAt);
    if (elapsed.inDays > 0) {
      return ('Ready • ${elapsed.inDays}d ${elapsed.inHours % 24}h ${elapsed.inMinutes % 60}m ${elapsed.inSeconds % 60}s ago', 1);
    } else if (elapsed.inHours > 0) {
      return ('Ready • ${elapsed.inHours}h ${elapsed.inMinutes % 60}m ${elapsed.inSeconds % 60}s ago', 1);
    } else if (elapsed.inMinutes > 0) {
      return ('Ready • ${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s ago', 1);
    } else {
      return ('Ready • ${elapsed.inSeconds}s ago', 1);
    }
  }

  String _formatOriginalDate(DateTime? dt) {
    if (dt == null) return '';
    final hourStr = dt.hour.toString().padLeft(2, '0');
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} at $hourStr:$minuteStr';
  }

  void _showParticipantBottomSheet(BuildContext context) {
    final radiusMeters = widget.tour.greenRadiusMeters ?? 50.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Participant Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kBrandBlue),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '"Checked In": Tourists that have been in your proximity at least once since the tour became ready.\n\n"Joined": Tourists that have entered the code but have not been in your proximity yet.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _locationRepository.getTourLocations(widget.tour.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = snapshot.hasData
                            ? snapshot.data!.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>()
                            : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                        if (docs.isEmpty) {
                          return const Center(
                            child: Text('No participants joined yet.', style: TextStyle(color: Colors.grey)),
                          );
                        }

                        double? anchorLat;
                        double? anchorLng;
                        try {
                          final guideDoc = docs.firstWhere(
                            (doc) => doc.data()['role'] == 'guide' || doc.id == widget.tour.guideUid,
                          );
                          anchorLat = guideDoc.data()['latitude'] as double?;
                          anchorLng = guideDoc.data()['longitude'] as double?;
                        } catch (_) {}

                        anchorLat ??= widget.tour.startLocationLat;
                        anchorLng ??= widget.tour.startLocationLng;

                        final List<Map<String, dynamic>> sortedItems = [];

                        for (var doc in docs) {
                          final data = doc.data();
                          final userId = doc.id;
                          final role = data['role'] as String? ?? 'tourist';
                          final isGuide = role == 'guide';
                          final hasAttended = _participantAttendanceMap[userId] == true;

                          double? distance;
                          if (!isGuide && anchorLat != null && anchorLng != null) {
                            final lat = data['latitude'] as double?;
                            final lng = data['longitude'] as double?;
                            if (lat != null && lng != null) {
                              distance = Geolocator.distanceBetween(anchorLat, anchorLng, lat, lng);
                            }
                          }

                          int priority = 3;
                          if (isGuide) {
                            priority = 0;
                          } else if (hasAttended) {
                            if (distance == null || distance <= radiusMeters) {
                              priority = 1;
                            } else {
                              priority = 2;
                            }
                          } else {
                            priority = 3;
                          }

                          sortedItems.add({
                            'doc': doc,
                            'priority': priority,
                            'hasAttended': hasAttended,
                          });
                        }

                        sortedItems.sort((a, b) => (a['priority'] as int).compareTo(b['priority'] as int));

                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: sortedItems.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final item = sortedItems[index];
                            return _ParticipantTile(
                              tourId: widget.tour.id,
                              doc: item['doc'],
                              anchorLat: anchorLat,
                              anchorLng: anchorLng,
                              radiusMeters: radiusMeters,
                              hasAttended: item['hasAttended'],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    if (!widget.tour.hasStartLocation) return const SizedBox.shrink();

    if (widget.tour.scheduledAt != null) {
      final now = DateTime.now();
      final difference = widget.tour.scheduledAt!.difference(now);
      if (difference.inHours > 24) {
        return const SizedBox.shrink();
      }
    }

    if (_isLoadingWeather) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _kFieldFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorderGrey),
        ),
        child: const Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Fetching current weather...', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    if (_weatherData == null) return const SizedBox.shrink();

    final temp = _weatherData!['temperature_2m'] as double? ?? 0.0;
    final code = _weatherData!['weather_code'] as int? ?? 0;
    final (conditionText, conditionIcon) = _getWeatherCondition(code);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _kFieldFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderGrey),
      ),
      child: Row(
        children: [
          Icon(conditionIcon, color: _kBrandBlue, size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Current weather at meeting point', style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text(
                '${temp.toStringAsFixed(1)}°C • $conditionText',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tour = widget.tour;
    final hasLocation = tour.hasStartLocation;
    final (statusText, timingState) = _getTourTimingState(tour.scheduledAt);
    final formattedScheduledTime = _formatOriginalDate(tour.scheduledAt);

    Color bannerBg;
    Color bannerText;
    IconData bannerIcon;
    Color sliderBg;
    Color sliderThumbColor;
    Color sliderTextColor;
    String sliderLabel;

    if (timingState == 0) {
      bannerBg = const Color(0xFFFFEBEE);
      bannerText = const Color(0xFFC62828);
      bannerIcon = Icons.schedule;
      sliderBg = const Color(0xFFFFEBEE);
      sliderThumbColor = const Color(0xFFE53935);
      sliderTextColor = const Color(0xFFC62828);
      sliderLabel = 'Slide to start early';
    } else {
      bannerBg = const Color(0xFFE8F5E9);
      bannerText = const Color(0xFF2E7D32);
      bannerIcon = Icons.timer_outlined;
      sliderBg = const Color(0xFFE8F5E9);
      sliderThumbColor = const Color(0xFF4CAF50);
      sliderTextColor = const Color(0xFF2E7D32);
      sliderLabel = 'Ready to start';
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(tour.name, style: const TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bannerBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(bannerIcon, color: bannerText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusText,
                            style: TextStyle(fontWeight: FontWeight.w700, color: bannerText, fontSize: 14),
                          ),
                          if (formattedScheduledTime.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Scheduled: $formattedScheduledTime',
                              style: TextStyle(fontSize: 12, color: bannerText.withValues(alpha: 0.8)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _buildWeatherCard(),

              if (hasLocation) ...[
                Container(
                  height: 140,
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorderGrey),
                  ),
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(tour.startLocationLat!, tour.startLocationLng!),
                          zoom: 15,
                        ),
                        onMapCreated: (controller) => _mapController = controller,
                        markers: {
                          Marker(
                            markerId: const MarkerId('start_pin'),
                            position: LatLng(tour.startLocationLat!, tour.startLocationLng!),
                          ),
                        },
                        zoomControlsEnabled: false,
                        scrollGesturesEnabled: true,
                        zoomGesturesEnabled: true,
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        myLocationButtonEnabled: false,
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: FloatingActionButton.small(
                          heroTag: 'recenter_map',
                          backgroundColor: Colors.white,
                          foregroundColor: _kBrandBlue,
                          child: const Icon(Icons.center_focus_strong, size: 20),
                          onPressed: () {
                            _mapController?.animateCamera(
                              CameraUpdate.newLatLngZoom(
                                LatLng(tour.startLocationLat!, tour.startLocationLng!),
                                15,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openDirections,
                    icon: const Icon(Icons.directions_outlined, size: 18, color: _kBrandBlue),
                    label: const Text('Get Directions', style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kBrandBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const Text(
                'Description',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Text(
                tour.description?.isNotEmpty == true
                    ? tour.description!
                    : 'No additional instructions added for this tour.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),

              // UI counter using cached state
              Builder(
                builder: (context) {
                  final touristDocs = _latestDocs.where((doc) {
                    final role = doc.data()['role'] as String? ?? 'tourist';
                    return role != 'guide';
                  }).toList();

                  final totalTourists = touristDocs.length;
                  final arrivedCount = _arrivedCountCache;
                  final expectedHeadcount = tour.expectedHeadcount;
                  final isExceeding = expectedHeadcount != null && totalTourists > expectedHeadcount;
                  
                  String checkInDisplay;
                  String checkInTitle;
                  if (timingState == 1) {
                    checkInTitle = 'Attendance';
                    checkInDisplay = '$arrivedCount / $totalTourists Checked In';
                  } else {
                    checkInTitle = 'Check-ins';
                    checkInDisplay = expectedHeadcount != null
                        ? '$totalTourists / $expectedHeadcount joined'
                        : '$totalTourists joined';
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _showParticipantBottomSheet(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isExceeding ? const Color(0xFFFFF8E1) : _kFieldFill,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isExceeding ? Colors.amber.shade400 : _kBorderGrey,
                                width: isExceeding ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Icon(
                                      isExceeding ? Icons.warning_amber_rounded : Icons.people_outline,
                                      size: 20,
                                      color: isExceeding ? Colors.amber.shade800 : _kBrandBlue,
                                    ),
                                    const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isExceeding ? 'Exceeds Headcount' : checkInTitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isExceeding ? Colors.amber.shade900 : Colors.grey,
                                    fontWeight: isExceeding ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  checkInDisplay,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isExceeding ? Colors.amber.shade900 : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _kFieldFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorderGrey),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 20, color: _kBrandBlue),
                              SizedBox(height: 8),
                              Text('Group Chat', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              SizedBox(height: 2),
                              Text('Ready', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const Spacer(),

              LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth;
                  const thumbSize = 50.0;
                  final maxSlide = maxWidth - thumbSize - 6;

                  return Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: sliderBg,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: sliderThumbColor.withValues(alpha: 0.5), width: 1.2),
                    ),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Center(
                          child: Opacity(
                            opacity: (1.0 - (_dragValue * 1.5)).clamp(0.0, 1.0),
                            child: Text(
                              sliderLabel,
                              style: TextStyle(
                                color: sliderTextColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 3 + (_dragValue * maxSlide),
                          child: GestureDetector(
                            onPanUpdate: (details) => _onPanUpdate(details, maxWidth),
                            onPanEnd: (_) => _onPanEnd(maxWidth),
                            child: Container(
                              height: thumbSize,
                              width: thumbSize,
                              decoration: BoxDecoration(
                                color: sliderThumbColor,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: RotationTransition(
                                  turns: Tween(begin: 0.0, end: 1.0).animate(
                                    CurvedAnimation(
                                      parent: _spinController,
                                      curve: Curves.easeInOutBack,
                                    ),
                                  ),
                                  child: Image.asset(
                                    'assets/images/bird_logo.png',
                                    width: 28,
                                    height: 28,
                                    errorBuilder: (context, error, stackTrace) => const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.tourId,
    required this.doc,
    required this.anchorLat,
    required this.anchorLng,
    required this.radiusMeters,
    required this.hasAttended,
  });

  final String tourId;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final double? anchorLat;
  final double? anchorLng;
  final double radiusMeters;
  final bool hasAttended;

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'U';
  }

  void _showParticipantOptions(BuildContext context, String name) {
    final userId = doc.id;
    final data = doc.data();
    final phone = data['phone'] as String?;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kBrandBlue),
              ),
              const SizedBox(height: 16),
              if (phone != null && phone.isNotEmpty) ...[
                ListTile(
                  leading: const Icon(Icons.phone_outlined, color: _kBrandBlue),
                  title: const Text('Call Participant'),
                  onTap: () {
                    Navigator.pop(context);
                    launchUrl(Uri.parse('tel:$phone'));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sms_outlined, color: _kBrandBlue),
                  title: const Text('Send SMS'),
                  onTap: () {
                    Navigator.pop(context);
                    launchUrl(Uri.parse('sms:$phone'));
                  },
                ),
                const Divider(),
              ],
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
                title: const Text('Remove from Tour', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remove Participant'),
                      content: Text('Are you sure you want to remove $name from this tour?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await FirebaseFirestore.instance
                        .collection('tours')
                        .doc(tourId)
                        .collection('participants')
                        .doc(userId)
                        .delete();
                    await FirebaseFirestore.instance
                        .collection('tours')
                        .doc(tourId)
                        .collection('locations')
                        .doc(userId)
                        .delete();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final userId = doc.id;
    final role = data['role'] as String? ?? 'tourist';
    final isGuide = role == 'guide';
    
    final locationPhotoUrl = data['photoUrl'] as String? ?? 
                           data['imageUrl'] as String? ?? 
                           data['avatar'] as String?;

    if (locationPhotoUrl != null && locationPhotoUrl.isNotEmpty) {
      return _buildTileContent(context, locationPhotoUrl);
    }

    final collectionName = isGuide ? 'guides' : 'tourists';
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection(collectionName).doc(userId).get(),
      builder: (context, snapshot) {
        String? accountPhotoUrl;
        if (snapshot.hasData && snapshot.data!.exists) {
          final profileData = snapshot.data!.data();
          accountPhotoUrl = profileData?['photoUrl'] as String? ??
                            profileData?['imageUrl'] as String? ??
                            profileData?['avatar'] as String?;
        }
        return _buildTileContent(context, accountPhotoUrl);
      },
    );
  }

  Widget _buildTileContent(BuildContext context, String? photoUrl) {
    final data = doc.data();
    final name = data['displayName'] as String? ?? 'Tourist';
    final role = roleFromData(data);
    final isGuide = role == 'guide';

    String statusText = 'Joined';
    Color statusColor = Colors.red;
    IconData statusIcon = Icons.error_outline;

    final lat = data['latitude'] as double?;
    final lng = data['longitude'] as double?;
    final timestamp = data['timestamp'] as Timestamp? ?? data['updatedAt'] as Timestamp?;

    bool isStale = false;
    if (timestamp != null) {
      final lastUpdated = timestamp.toDate();
      if (DateTime.now().difference(lastUpdated).inMinutes > 1) {
        isStale = true;
      }
    }

    if (isGuide) {
      statusText = 'Tour Guide (Staff)';
      statusColor = _kBrandBlue;
      statusIcon = Icons.star;
    } else {
      double? distance;
      if (anchorLat != null && anchorLng != null && lat != null && lng != null) {
        distance = Geolocator.distanceBetween(anchorLat!, anchorLng!, lat, lng);
      }

      if (isStale) {
        statusText = 'Checked in • App inactive / Signal lost';
        statusColor = Colors.grey;
        statusIcon = Icons.cloud_off;
      } else if (hasAttended) {
        if (distance == null || distance <= radiusMeters) {
          final distStr = distance != null ? ' • ${distance.toStringAsFixed(0)}m away' : '';
          statusText = 'Checked in$distStr';
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
        } else {
          statusText = 'Checked in • Wandered off (${distance.toStringAsFixed(0)}m away)';
          statusColor = Colors.orange;
          statusIcon = Icons.near_me;
        }
      } else {
        statusText = 'Joined';
        statusColor = Colors.red;
        statusIcon = Icons.error_outline;
      }
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: isGuide ? null : () => _showParticipantOptions(context, name),
      leading: CircleAvatar(
        backgroundColor: isGuide ? _kBrandBlue : Colors.grey[200],
        backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
            ? NetworkImage(photoUrl)
            : null,
        child: (photoUrl == null || photoUrl.isEmpty)
            ? Text(
                _getInitials(name),
                style: TextStyle(
                  color: isGuide ? Colors.white : Colors.grey[800],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              )
            : null,
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(
        statusText,
        style: TextStyle(
          fontSize: 12,
          color: statusColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: isGuide
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.verified, color: _kBrandBlue, size: 18),
                SizedBox(width: 4),
                Text(
                  'Guide',
                  style: TextStyle(
                    color: _kBrandBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            )
          : Icon(statusIcon, color: statusColor, size: 20),
    );
  }

  String roleFromData(Map<String, dynamic> data) => data['role'] as String? ?? 'tourist';
}