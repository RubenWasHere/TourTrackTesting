// ============================================================
// tourist_pre_start_screen.dart
// ============================================================
// Participant-facing pre-start lobby showing tour timing, weather,
// meeting point map, directions, personal check-in status, and group chat.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../models/tour.dart';
import '../services/location_service.dart';
// TODO: Import your tourist tracking screen here when ready
// import 'tourist_tracking_screen.dart';

const _kBrandBlue = Color(0xFF1F4E9E);
const _kFieldFill = Color(0xFFF3F3F3);
const _kBorderGrey = Color(0xFFE0E0E0);

class TouristPreStartScreen extends StatefulWidget {
  const TouristPreStartScreen({super.key, required this.tour});

  final Tour tour;

  @override
  State<TouristPreStartScreen> createState() => _TouristPreStartScreenState();
}

class _TouristPreStartScreenState extends State<TouristPreStartScreen> {
  final LocationService _locationService = LocationService();
  GoogleMapController? _mapController;
  Timer? _tickerTimer;

  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<DocumentSnapshot>? _participantStatusSubscription;

  bool _hasAttended = false;
  bool _isLoadingWeather = true;
  Map<String, dynamic>? _weatherData;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
    _startTouristTrackingAndAttendance();

    // Live tick every second to keep countdown timers smooth
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _locationSubscription?.cancel();
    _participantStatusSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// Broadcasts the tourist's location and listens to their personal check-in status
  void _startTouristTrackingAndAttendance() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // 1. Listen to personal attendance flag in Firestore
    _participantStatusSubscription = FirebaseFirestore.instance
        .collection('tours')
        .doc(widget.tour.id)
        .collection('participants')
        .doc(currentUserId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>?;
        setState(() {
          _hasAttended = data?['hasAttended'] == true;
        });
      }
    });

    // 2. Stream tourist location so proximity logic can verify check-in
    _locationSubscription = _locationService.getPositionStream().listen((Position position) {
      if (!mounted) return;

      FirebaseFirestore.instance
          .collection('tours')
          .doc(widget.tour.id)
          .collection('locations')
          .doc(currentUserId)
          .set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'role': 'tourist',
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
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
        return ('Starts in ${difference.inDays}d ${difference.inHours % 24}h ${difference.inMinutes % 60}m', 0);
      } else if (difference.inHours > 0) {
        return ('Starts in ${difference.inHours}h ${difference.inMinutes % 60}m ${difference.inSeconds % 60}s', 0);
      } else if (difference.inMinutes > 0) {
        return ('Starts in ${difference.inMinutes}m ${difference.inSeconds % 60}s', 0);
      } else {
        return ('Starts in ${difference.inSeconds}s', 0);
      }
    }

    return ('Tour is ready or in progress', 1);
  }

  String _formatOriginalDate(DateTime? dt) {
    if (dt == null) return '';
    final hourStr = dt.hour.toString().padLeft(2, '0');
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} at $hourStr:$minuteStr';
  }

  Widget _buildWeatherCard() {
    if (!widget.tour.hasStartLocation) return const SizedBox.shrink();

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

    Color bannerBg = timingState == 0 ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);
    Color bannerText = timingState == 0 ? const Color(0xFFC62828) : const Color(0xFF2E7D32);
    IconData bannerIcon = timingState == 0 ? Icons.schedule : Icons.timer_outlined;

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
              // Timing Banner
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

              // Weather Card
              _buildWeatherCard(),

              // Map & Directions Preview
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
                          heroTag: 'tourist_recenter_map',
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

              // Description
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

              // Personal Status Cards (Check-In Status & Group Chat)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _hasAttended ? const Color(0xFFE8F5E9) : _kFieldFill,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _hasAttended ? Colors.green.shade300 : _kBorderGrey,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _hasAttended ? Icons.check_circle : Icons.info_outline,
                            size: 20,
                            color: _hasAttended ? Colors.green : _kBrandBlue,
                          ),
                          const SizedBox(height: 8),
                          const Text('Your Status', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 2),
                          Text(
                            _hasAttended ? 'Checked In ✓' : 'Head to Meeting Point',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _hasAttended ? Colors.green.shade800 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        // TODO: Navigate to group chat screen when ready
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Group chat coming up next!')),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
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
                            Text('Open Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kBrandBlue)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}