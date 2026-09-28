// ============================================================
// tracking_screen.dart (Guide & Tourist Tracking View)
// ============================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/tour.dart';
import '../repositories/location_repository.dart';
import '../repositories/tour_repository.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/tour_navigation_service.dart';
import 'group_chat/group_chat_screen.dart';
import 'tourist_settings_screen.dart';
import 'tourist_home_screen.dart';
import 'guide_home_screen.dart';

const _kBrandBlue = Color(0xFF1F4E9E);
const _kBrandYellow = Color(0xFFFFDE59);
const _kDialogBg = Color(0xFFFFFDF5);

Future<void> _tryChatNotification(Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    debugPrint('Tour chat notification update failed: $error');
  }
}

enum TrackingRole { guide, tourist }

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({
    super.key,
    required this.tourId,
    required this.role,
    this.onGroupChatTap,
    this.initialPosition,
  });

  final String tourId;
  final TrackingRole role;
  final VoidCallback? onGroupChatTap;
  final LatLng? initialPosition;

  @override
  Widget build(BuildContext context) {
    switch (role) {
      case TrackingRole.guide:
        return _GuideTrackingView(
          key: ValueKey('guide:$tourId'),
          tourId: tourId,
          role: role,
          initialPosition: initialPosition,
        );
      case TrackingRole.tourist:
        return _TouristTrackingView(
          key: ValueKey('tourist:$tourId'),
          tourId: tourId,
          role: role,
          onGroupChatTap: onGroupChatTap,
          initialPosition: initialPosition,
        );
    }
  }
}

class TouristNode {
  final String id;
  final LatLng position;
  final String name;
  final double distance;
  final Color zoneColor;

  TouristNode({
    required this.id,
    required this.position,
    required this.name,
    required this.distance,
    required this.zoneColor,
  });
}

class TouristCluster {
  final LatLng center;
  final List<TouristNode> members;
  final Color worstColor;

  TouristCluster({
    required this.center,
    required this.members,
    required this.worstColor,
  });
}

// Guide's UI
class _GuideTrackingView extends StatefulWidget {
  const _GuideTrackingView({
    super.key,
    required this.tourId,
    required this.role,
    this.initialPosition,
  });

  final String tourId;
  final TrackingRole role;
  final LatLng? initialPosition;

  @override
  State<_GuideTrackingView> createState() => _GuideTrackingViewState();
}

class _GuideTrackingViewState extends State<_GuideTrackingView> {
  final LocationRepository _locationRepository = LocationRepository();
  final LocationService _locationService = LocationService();
  final TourRepository _tourRepository = TourRepository();
  final NotificationService _notificationService = NotificationService();
  Future<void> _chatNotifications = Future<void>.value();
  bool _canOpenChat = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _participantsSubscription;
  StreamSubscription<QuerySnapshot>? _attendanceSubscription;
  final Map<String, bool> _participantAttendanceMap = {};
  String? _guideDisplayName;
  Future<void> _participantNotifications = Future<void>.value();

  // Guard flag to prevent background GPS writes & setState during tour teardown
  bool _isEndingTour = false;

  void _queueParticipantNotification(Future<void> Function() action) {
    _participantNotifications = _participantNotifications.then((_) async {
      try {
        await action();
      } catch (error) {
        debugPrint('Participant notification failed: $error');
      }
    });
  }

  void _listenToParticipantCount() {
    _participantsSubscription = _tourRepository
        .getTourParticipants(widget.tourId)
        .listen(
          (snapshot) {
            if (!mounted || _isEndingTour) return;
            final count = snapshot.docs.length;
            _queueParticipantNotification(() async {
              if (!mounted || _isEndingTour) return;
              await LocalNotificationService.showParticipantCount(count: count);
            });
          },
          onError: (Object error) {
            debugPrint('Participant count failed to load: $error');
          },
        );
  }

  void _startParticipantsStream() {
    _attendanceSubscription = FirebaseFirestore.instance
        .collection('tours')
        .doc(widget.tourId)
        .collection('participants')
        .snapshots()
        .listen((snapshot) {
      if (!mounted || _isEndingTour) return;
      setState(() {
        _participantAttendanceMap.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['hasAttended'] == true) {
            _participantAttendanceMap[doc.id] = true;
          }
        }
      });
    });
  }

  String? _locationError;
  GoogleMapController? _mapController;

  Tour? _tour;
  StreamSubscription<DocumentSnapshot>? _tourSubscription;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<QuerySnapshot>? _chatSubscription;

  LatLng? _guidePosition;
  Timer? _elapsedTimer;
  String _elapsedTimeString = "00:00";
  MapType _currentMapType = MapType.normal;
  int _unreadMessageCount = 0;

  BitmapDescriptor? _guideMarkerIcon;
  final Map<String, BitmapDescriptor> _clusterIconCache = {};
  final Map<String, BitmapDescriptor> _dotIconCache = {};
  bool _isLoadingPosition = true;

  int _recenterToggleState = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _guidePosition = widget.initialPosition;
      _isLoadingPosition = false;
    }
    _startTourStream();
    _startParticipantsStream();
    _startLocationTracking();
    _initGuideMarkerFallback();
    _loadGuideMarkerFromFirestore();
    _startChatStream();

    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateElapsedTime(),
    );
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _tourSubscription?.cancel();
    _positionStream?.cancel();
    _chatSubscription?.cancel();
    _participantsSubscription?.cancel();
    _attendanceSubscription?.cancel();
    if (_canOpenChat) {
      unawaited(
        _chatNotifications.then(
          (_) => _tryChatNotification(
            () => _notificationService.unsubscribeFromTour(widget.tourId),
          ),
        ),
      );
    }
    _queueParticipantNotification(
      () => LocalNotificationService.cancelParticipantCount(),
    );
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initGuideMarkerFallback() async {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'Guide';
    final icon = await _createAvatarMarker(null, name, _kBrandBlue);
    if (mounted && _guideMarkerIcon == null) {
      setState(() => _guideMarkerIcon = icon);
    }
  }

  Future<void> _loadGuideMarkerFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String? photoUrl;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('guides')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        photoUrl =
            data?['photoUrl'] as String? ??
            data?['imageUrl'] as String? ??
            data?['avatar'] as String?;
      }
    } catch (_) {}

    photoUrl ??= user.photoURL;

    final icon = await _createAvatarMarker(
      photoUrl,
      user.displayName ?? 'Guide',
      _kBrandBlue,
    );
    if (mounted) {
      setState(() => _guideMarkerIcon = icon);
    }
  }

  void _startTourStream() {
    _tourSubscription = FirebaseFirestore.instance
        .collection('tours')
        .doc(widget.tourId)
        .snapshots()
        .listen(
          (doc) {
            if (!doc.exists || _isEndingTour) return;
            if (mounted) {
              setState(() {
                _tour = Tour.fromFirestore(doc);
              });
            }
          },
          onError: (Object error) {
            debugPrint('Tour details failed to load: $error');
          },
        );
  }

  void _startChatStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _chatSubscription = FirebaseFirestore.instance
        .collection('tours')
        .doc(widget.tourId)
        .collection('messages')
        .snapshots()
        .listen((snapshot) {
      if (mounted && !_isEndingTour) {
        final unread = snapshot.docs.where((doc) {
          final data = doc.data();
          final senderId = data['senderId'] as String?;
          return senderId != user.uid;
        }).length;

        setState(() {
          _unreadMessageCount = unread;
        });
      }
    });
  }

  Future<void> _startLocationTracking() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('You must be signed in to share your location.');
      }
      setState(() => _canOpenChat = true);
      _chatNotifications = _tryChatNotification(
        () => _notificationService.subscribeToTour(widget.tourId),
      );
      _listenToParticipantCount();
      unawaited(_loadGuideDisplayName(user.uid));
      if (!mounted) return;

      final permission = await _locationService.requestLocationPermission();
      if (!mounted) return;
      if (permission != LocationPermissionResult.granted) {
        throw StateError('Location permission is required for guide tracking.');
      }

      if (_guidePosition == null) {
        final initial = await _locationService.getCurrentPosition().timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'No GPS position received within 20 seconds.',
          ),
        );

        if (!mounted) return;
        if (initial != null) await _recordGuidePosition(initial);
      }
      if (!mounted) return;

      _positionStream = _locationService.getPositionStream().listen(
        (position) => unawaited(_recordGuidePosition(position)),
        onError: (Object error) =>
            _showLocationError('Location updates failed: $error'),
      );
    } catch (error) {
      _showLocationError('Could not start tracking: $error');
    }
  }

  Future<void> _loadGuideDisplayName(String uid) async {
    try {
      final name = await _locationRepository
          .getGuideName(uid)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      _guideDisplayName = name;
    } catch (error) {
      debugPrint('Guide name unavailable; using fallback: $error');
    }
  }

  void _showLocationError(String message) {
    if (!mounted || _isEndingTour) return;
    setState(() {
      _locationError = message;
      _isLoadingPosition = false;
    });
  }

  Future<void> _recordGuidePosition(Position position) async {
    if (!mounted || _isEndingTour) return;
    setState(() {
      _guidePosition = LatLng(position.latitude, position.longitude);
      _isLoadingPosition = false;
    });
    final controller = _mapController;
    if (controller != null && _recenterToggleState == 1) {
      await controller.animateCamera(CameraUpdate.newLatLng(_guidePosition!));
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _isEndingTour) return;
      await _locationRepository.updateUserLocation(
        tourId: widget.tourId,
        userUid: user.uid,
        latitude: position.latitude,
        longitude: position.longitude,
        role: widget.role.name,
        displayName:
            _guideDisplayName ?? user.displayName ?? user.email ?? 'Guide',
      );
    } catch (error) {
      _showLocationError('Could not save your location: $error');
    }
  }

  Future<BitmapDescriptor> _createAvatarMarker(
    String? photoUrl,
    String name,
    Color ringColor,
  ) async {
    const int canvasSize = 120;
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final Paint borderPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final Paint whiteGapPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawCircle(const Offset(60, 60), 60, borderPaint);
    canvas.drawCircle(const Offset(60, 60), 52, whiteGapPaint);

    bool drawnImage = false;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(photoUrl));
        if (response.statusCode == 200) {
          final ui.Codec codec = await ui.instantiateImageCodec(
            response.bodyBytes,
            targetWidth: 100,
            targetHeight: 100,
          );
          final ui.FrameInfo frame = await codec.getNextFrame();

          final Path clipPath = Path()
            ..addOval(
              Rect.fromCircle(center: const Offset(60, 60), radius: 48),
            );
          canvas.clipPath(clipPath);

          canvas.drawImageRect(
            frame.image,
            Rect.fromLTWH(
              0,
              0,
              frame.image.width.toDouble(),
              frame.image.height.toDouble(),
            ),
            Rect.fromCircle(center: const Offset(60, 60), radius: 48),
            Paint()
              ..isAntiAlias = true
              ..filterQuality = ui.FilterQuality.high,
          );
          drawnImage = true;
        }
      } catch (_) {}
    }

    if (!drawnImage) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: _getInitials(name),
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.bold,
            color: ringColor == Colors.white ? _kBrandBlue : ringColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(60 - textPainter.width / 2, 60 - textPainter.height / 2),
      );
    }

    final ui.Image image = await pictureRecorder.endRecording().toImage(
      canvasSize,
      canvasSize,
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: 40,
      height: 40,
    );
  }

  Future<BitmapDescriptor> _getDotMarker(Color color) async {
    final key = 'dot_${color.toARGB32()}';
    if (_dotIconCache.containsKey(key)) return _dotIconCache[key]!;

    const int canvasSize = 60;
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final Paint stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..isAntiAlias = true;

    canvas.drawCircle(const Offset(30, 30), 22, fill);
    canvas.drawCircle(const Offset(30, 30), 22, stroke);

    final ui.Image image = await pictureRecorder.endRecording().toImage(
      canvasSize,
      canvasSize,
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final descriptor = BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: 22,
      height: 22,
    );
    _dotIconCache[key] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> _getClusterMarker(int count, Color color) async {
    final key = 'cluster_${count}_${color.toARGB32()}';
    if (_clusterIconCache.containsKey(key)) return _clusterIconCache[key]!;

    const int canvasSize = 90;
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final Paint stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..isAntiAlias = true;

    canvas.drawCircle(const Offset(45, 45), 36, fill);
    canvas.drawCircle(const Offset(45, 45), 36, stroke);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '$count',
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(45 - textPainter.width / 2, 45 - textPainter.height / 2),
    );

    final ui.Image image = await pictureRecorder.endRecording().toImage(
      canvasSize,
      canvasSize,
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final descriptor = BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: 34,
      height: 34,
    );
    _clusterIconCache[key] = descriptor;
    return descriptor;
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'U';
  }

  void _updateElapsedTime() {
    if (_tour?.scheduledAt == null || _isEndingTour) return;

    final elapsed = DateTime.now().difference(_tour!.scheduledAt!);
    if (elapsed.isNegative) return;

    final hours = elapsed.inHours;
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    if (mounted && !_isEndingTour) {
      setState(() {
        _elapsedTimeString = hours > 0
            ? '$hours:$minutes:$seconds'
            : '$minutes:$seconds';
      });
    }
  }

  void _recenterMap() {
    if (_guidePosition != null && _mapController != null && _tour != null) {
      final greenRadius = _tour!.greenRadiusMeters ?? 20.0;
      final amberRadius = _tour!.amberRadiusMeters ?? 60.0;

      double targetZoom;
      if (_recenterToggleState == 0) {
        targetZoom = 24.5 - (math.log(greenRadius) / math.ln2);
        targetZoom = targetZoom.clamp(15.0, 21.5);
        _recenterToggleState = 1;
      } else {
        targetZoom = 23.3 - (math.log(amberRadius) / math.ln2);
        targetZoom = targetZoom.clamp(14.5, 19.0);
        _recenterToggleState = 0;
      }

      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_guidePosition!, targetZoom),
      );
    }
  }

  void _openSettingsModal() {
    if (_isEndingTour) return;

    final parentContext = context; // Safely capture outer state context

    showModalBottomSheet(
      context: parentContext,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tour Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kBrandBlue,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.layers_outlined, color: _kBrandBlue),
                title: const Text('Change Map Style'),
                trailing: DropdownButton<MapType>(
                  value: _currentMapType,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: MapType.normal,
                      child: Text('Standard'),
                    ),
                    DropdownMenuItem(
                      value: MapType.satellite,
                      child: Text('Satellite'),
                    ),
                    DropdownMenuItem(
                      value: MapType.hybrid,
                      child: Text('Hybrid'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null && mounted) {
                      setState(() => _currentMapType = val);
                      Navigator.pop(sheetContext);
                    }
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.radar_outlined, color: _kBrandBlue),
                title: const Text('Edit Geofence Radii'),
                subtitle: const Text('Adjust green and amber zones live'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showEditRadiusModal();
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text(
                  'End Tour & Dismiss Everyone',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext); // Close bottom sheet using sheetContext
                  
                  final confirm = await showDialog<bool>(
                    context: parentContext,
                    builder: (ctx) => AlertDialog(
                      title: const Text('End Tour'),
                      content: const Text(
                        'This will end the tour, kick out all participants, and delete the session. Are you sure?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('End Tour'),
                        ),
                      ],
                    ),
                  );

                  if (!mounted || confirm != true) return;

                  // Immediately halt background streams & updates before deleting
                  setState(() {
                    _isEndingTour = true;
                  });

                  _tourSubscription?.cancel();
                  _positionStream?.cancel();
                  _chatSubscription?.cancel();
                  _participantsSubscription?.cancel();
                  _attendanceSubscription?.cancel();

                  showDialog(
                    context: parentContext,
                    barrierDismissible: false,
                    builder: (ctx) => const Center(
                      child: CircularProgressIndicator(color: _kBrandBlue),
                    ),
                  );

                  try {
                    await TourRepository().deleteTour(widget.tourId);

                    if (mounted) {
                      Navigator.of(parentContext).pop(); // Pop loading dialog
                      Navigator.of(parentContext).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const GuideHomeScreen()),
                        (_) => false,
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      Navigator.of(parentContext).pop(); // Pop loading dialog
                      setState(() {
                        _isEndingTour = false;
                      });
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(content: Text('Failed to end tour: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditRadiusModal() {
    final greenController = TextEditingController(
      text: (_tour?.greenRadiusMeters ?? 20.0).toString(),
    );
    final amberController = TextEditingController(
      text: (_tour?.amberRadiusMeters ?? 60.0).toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Geofence Radii'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: greenController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Green Zone Radius (meters)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amberController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amber Zone Radius (meters)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final g = double.tryParse(greenController.text);
              final a = double.tryParse(amberController.text);
              if (g != null && a != null) {
                await TourRepository().updateTour(
                  widget.tourId,
                  greenRadiusMeters: g,
                  amberRadiusMeters: a,
                );
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Set<Circle> _buildGeofenceCircles() {
    final center =
        _guidePosition ??
        LatLng(_tour?.startLocationLat ?? 0, _tour?.startLocationLng ?? 0);
    if (_tour == null) return {};

    final greenRadius = _tour!.greenRadiusMeters ?? 20.0;
    final amberRadius = _tour!.amberRadiusMeters ?? 60.0;

    return {
      Circle(
        circleId: const CircleId('amber_zone'),
        center: center,
        radius: amberRadius,
        fillColor: Colors.amber.withValues(alpha: 0.12),
        strokeColor: Colors.amber.withValues(alpha: 0.4),
        strokeWidth: 1,
      ),
      Circle(
        circleId: const CircleId('green_zone'),
        center: center,
        radius: greenRadius,
        fillColor: Colors.green.withValues(alpha: 0.12),
        strokeColor: Colors.green.withValues(alpha: 0.7),
        strokeWidth: 2,
      ),
    };
  }

  List<TouristCluster> _clusterTourists(List<TouristNode> tourists) {
    final List<TouristCluster> clusters = [];
    const double clusteringThresholdMeters = 15.0;

    for (var tourist in tourists) {
      bool addedToCluster = false;
      for (var cluster in clusters) {
        final dist = Geolocator.distanceBetween(
          cluster.center.latitude,
          cluster.center.longitude,
          tourist.position.latitude,
          tourist.position.longitude,
        );
        if (dist <= clusteringThresholdMeters) {
          cluster.members.add(tourist);
          addedToCluster = true;
          break;
        }
      }
      if (!addedToCluster) {
        clusters.add(
          TouristCluster(
            center: tourist.position,
            members: [tourist],
            worstColor: tourist.zoneColor,
          ),
        );
      }
    }
    return clusters;
  }

  Color _getWorstColor(List<TouristNode> members) {
    bool hasRed = members.any((m) => m.zoneColor == Colors.red);
    bool hasOrange = members.any((m) => m.zoneColor == Colors.orange);
    if (hasRed) return Colors.red;
    if (hasOrange) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    if (_locationError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('TourTrack')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_locationError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_tour == null || _isLoadingPosition || _guidePosition == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _kBrandBlue),
              SizedBox(height: 16),
              Text(
                'Acquiring GPS location...',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final greenRadius = _tour!.greenRadiusMeters ?? 20.0;
    final amberRadius = _tour!.amberRadiusMeters ?? 60.0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _locationRepository.getTourLocations(widget.tourId),
              builder: (context, snapshot) {
                if (_isEndingTour) return const SizedBox.shrink();
                final docs = snapshot.hasData ? snapshot.data!.docs : [];

                int greenCount = 0;
                int amberCount = 0;
                int redCount = 0;
                int totalTourists = 0;

                List<TouristNode> rawTourists = [];

                for (var doc in docs) {
                  final data = doc.data();
                  final role = data['role'] as String? ?? 'tourist';
                  final isGuide = role == TrackingRole.guide.name;
                  final lat = (data['latitude'] as num?)?.toDouble();
                  final lng = (data['longitude'] as num?)?.toDouble();
                  final name = data['displayName'] as String? ?? 'User';

                  if (lat == null || lng == null) continue;

                  if (!isGuide) {
                    final touristUid = doc.id;

                    double distance = 0;
                    if (_guidePosition != null) {
                      distance = Geolocator.distanceBetween(
                        _guidePosition!.latitude,
                        _guidePosition!.longitude,
                        lat,
                        lng,
                      );
                    }

                    final hasAttended =
                        _participantAttendanceMap[touristUid] == true;

                    if (!hasAttended &&
                        _guidePosition != null &&
                        distance <= greenRadius &&
                        !_isEndingTour) {
                      FirebaseFirestore.instance
                          .collection('tours')
                          .doc(widget.tourId)
                          .collection('participants')
                          .doc(touristUid)
                          .set({
                        'hasAttended': true,
                        'attendedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                      _participantAttendanceMap[touristUid] = true;
                    }

                    if (_participantAttendanceMap[touristUid] != true) {
                      continue;
                    }

                    totalTourists++;

                    Color zoneColor = Colors.green;
                    if (distance <= greenRadius) {
                      greenCount++;
                      zoneColor = Colors.green;
                    } else if (distance <= amberRadius) {
                      amberCount++;
                      zoneColor = Colors.orange;
                    } else {
                      redCount++;
                      zoneColor = Colors.red;
                    }

                    rawTourists.add(
                      TouristNode(
                        id: doc.id,
                        position: LatLng(lat, lng),
                        name: name,
                        distance: distance,
                        zoneColor: zoneColor,
                      ),
                    );
                  }
                }

                final clusters = _clusterTourists(rawTourists);
                Set<Marker> markers = {};

                if (_guidePosition != null && _guideMarkerIcon != null) {
                  markers.add(
                    Marker(
                      markerId: const MarkerId('guide_marker'),
                      position: _guidePosition!,
                      zIndexInt: 10,
                      anchor: const Offset(0.5, 0.5),
                      icon: _guideMarkerIcon!,
                      infoWindow: const InfoWindow(title: 'You (Guide)'),
                    ),
                  );
                }

                return FutureBuilder<Set<Marker>>(
                  future: _buildClusterMarkers(clusters),
                  builder: (context, clusterSnapshot) {
                    final clusterMarkers = clusterSnapshot.data ?? {};
                    markers.addAll(clusterMarkers);

                    return Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _guidePosition!,
                            zoom: 17.5,
                          ),
                          onMapCreated: (controller) =>
                              _mapController = controller,
                          markers: markers,
                          circles: _buildGeofenceCircles(),
                          zoomControlsEnabled: false,
                          myLocationEnabled: false,
                          myLocationButtonEnabled: false,
                          compassEnabled: false,
                          mapType: _currentMapType,
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.only(
                              top: 42,
                              bottom: 14,
                              left: 20,
                              right: 20,
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(24),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const SizedBox(width: 40),
                                    const Text(
                                      'TourTrack',
                                      style: TextStyle(
                                        color: _kBrandBlue,
                                        fontSize: 30,
                                        fontWeight: FontWeight.w900,
                                        fontFamily: 'Nunito',
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.settings,
                                        color: Colors.grey[800],
                                        size: 26,
                                      ),
                                      onPressed: _openSettingsModal,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_tour!.name} • $_elapsedTimeString',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _StatusPill(
                                      color: Colors.green,
                                      bgColor: Colors.green.shade50,
                                      count: greenCount.toString(),
                                      isWarning: false,
                                    ),
                                    const SizedBox(width: 10),
                                    _StatusPill(
                                      color: Colors.orange,
                                      bgColor: Colors.orange.shade50,
                                      count: amberCount > 0
                                          ? '$amberCount!'
                                          : '0',
                                      isWarning: amberCount > 0,
                                    ),
                                    const SizedBox(width: 10),
                                    _StatusPill(
                                      color: Colors.red,
                                      bgColor: Colors.red.shade50,
                                      count: redCount > 0 ? '$redCount!' : '0',
                                      isWarning: redCount > 0,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Zones: Green (${greenRadius.round()}m) • Amber (${amberRadius.round()}m)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _kBrandYellow,
                                      width: 2,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Image.asset(
                                        'assets/images/bird_logo.png',
                                        width: 13,
                                        height: 13,
                                        errorBuilder: (_, _, _) =>
                                            const Icon(Icons.people, size: 13),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Head Count: $totalTourists',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 30,
                          left: 20,
                          right: 20,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _FloatingActionButton(
                                icon: Icons.chat_bubble_outline,
                                badgeCount: _unreadMessageCount,
                                onTap: () {
                                  if (!_canOpenChat || _isEndingTour) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          GroupChatScreen(tourId: widget.tourId),
                                    ),
                                  );
                                },
                              ),
                              GestureDetector(
                                onTap: () async {
                                  if (_isEndingTour) return;
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => TourParticipantsScreen(
                                        tourId: widget.tourId,
                                        tourName: _tour?.name ?? 'Tour',
                                        elapsedTime: _elapsedTimeString,
                                        guidePosition: _guidePosition,
                                        greenRadius: greenRadius,
                                        amberRadius: amberRadius,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 26,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _kBrandYellow,
                                    borderRadius: BorderRadius.circular(30),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 6,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    children: [
                                      Text(
                                        'Participants',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.person_outline, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                              _FloatingActionButton(
                                icon: Icons.my_location,
                                onTap: _recenterMap,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<Set<Marker>> _buildClusterMarkers(
    List<TouristCluster> clusters,
  ) async {
    Set<Marker> markers = {};
    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      if (cluster.members.length == 1) {
        final member = cluster.members.first;
        final icon = await _getDotMarker(member.zoneColor);
        markers.add(
          Marker(
            markerId: MarkerId('tourist_${member.id}'),
            position: member.position,
            anchor: const Offset(0.5, 0.5),
            icon: icon,
            infoWindow: InfoWindow(
              title: member.name,
              snippet: '${member.distance.toStringAsFixed(0)}m away',
            ),
          ),
        );
      } else {
        final worstColor = _getWorstColor(cluster.members);
        final icon = await _getClusterMarker(
          cluster.members.length,
          worstColor,
        );
        markers.add(
          Marker(
            markerId: MarkerId('cluster_$i'),
            position: cluster.center,
            anchor: const Offset(0.5, 0.5),
            icon: icon,
            infoWindow: InfoWindow(
              title: '${cluster.members.length} Participants Grouped',
              snippet: 'Tap to inspect group',
            ),
          ),
        );
      }
    }
    return markers;
  }
}

// Full-screen participants dashboard for the guide
class TourParticipantsScreen extends StatefulWidget {
  const TourParticipantsScreen({
    super.key,
    required this.tourId,
    required this.tourName,
    required this.elapsedTime,
    required this.guidePosition,
    required this.greenRadius,
    required this.amberRadius,
  });

  final String tourId;
  final String tourName;
  final String elapsedTime;
  final LatLng? guidePosition;
  final double greenRadius;
  final double amberRadius;

  @override
  State<TourParticipantsScreen> createState() => _TourParticipantsScreenState();
}

class _TourParticipantsScreenState extends State<TourParticipantsScreen> {
  String _selectedFilter = 'all';

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'U';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: _kBrandBlue),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'TourTrack',
                    style: TextStyle(
                      color: _kBrandBlue,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Nunito',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: Colors.black87),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            Text(
              '${widget.tourName} • ${widget.elapsedTime}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('tours')
                    .doc(widget.tourId)
                    .collection('locations')
                    .snapshots(),
                builder: (context, locationSnapshot) {
                  final locDocs = locationSnapshot.hasData ? locationSnapshot.data!.docs : [];
                  final Map<String, Map<String, dynamic>> locationMap = {};
                  for (var doc in locDocs) {
                    if (doc.data()['role'] != 'guide') {
                      locationMap[doc.id] = doc.data();
                    }
                  }

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('tours')
                        .doc(widget.tourId)
                        .collection('participants')
                        .snapshots(),
                    builder: (context, participantSnapshot) {
                      if (!participantSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: _kBrandBlue));
                      }

                      final participantDocs = participantSnapshot.data!.docs;
                      int zoneCount = 0;
                      int outCount = 0;
                      int pacingCount = 0;

                      List<Map<String, dynamic>> processedParticipants = [];

                      for (var pDoc in participantDocs) {
                        final pData = pDoc.data();
                        final uid = pDoc.id;
                        final name = pData['name'] ?? pData['displayName'] ?? 'Tourist';
                        final locData = locationMap[uid];

                        double distance = 9999;
                        if (locData != null && widget.guidePosition != null) {
                          final lat = (locData['latitude'] as num?)?.toDouble() ?? 0;
                          final lng = (locData['longitude'] as num?)?.toDouble() ?? 0;
                          distance = Geolocator.distanceBetween(
                            widget.guidePosition!.latitude,
                            widget.guidePosition!.longitude,
                            lat,
                            lng,
                          );
                        }

                        String status = 'In zone';
                        Color statusColor = Colors.green;
                        bool isOut = false;
                        bool isPacing = false;
                        bool hasSos = pData['sos'] == true;

                        if (hasSos) {
                          status = 'Sent A SOS signal';
                          statusColor = Colors.red;
                          outCount++;
                          isOut = true;
                        } else if (distance > widget.amberRadius) {
                          status = 'Out of Zone';
                          statusColor = Colors.red;
                          outCount++;
                          isOut = true;
                        } else if (distance > widget.greenRadius) {
                          status = 'Amber Zone (Pacing)';
                          statusColor = Colors.orange;
                          pacingCount++;
                          isPacing = true;
                        } else {
                          zoneCount++;
                        }

                        processedParticipants.add({
                          'id': uid,
                          'name': name,
                          'status': status,
                          'statusColor': statusColor,
                          'isOut': isOut,
                          'isPacing': isPacing,
                          'hasSos': hasSos,
                          'distance': distance,
                        });
                      }

                      final filteredList = processedParticipants.where((p) {
                        if (_selectedFilter == 'zone') return !p['isOut'] && !p['isPacing'];
                        if (_selectedFilter == 'out') return p['isOut'] || p['hasSos'];
                        if (_selectedFilter == 'pacing') return p['isPacing'];
                        return true;
                      }).toList();

                      return Column(
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                const Text('Filters: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(width: 8),
                                _buildFilterChip('Zone: $zoneCount', 'zone', Colors.green),
                                const SizedBox(width: 8),
                                _buildFilterChip('Out: $outCount', 'out', Colors.red),
                                const SizedBox(width: 8),
                                _buildFilterChip('Pacing: $pacingCount', 'pacing', Colors.orange),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: filteredList.isEmpty
                                ? const Center(child: Text('No participants match this filter.', style: TextStyle(color: Colors.grey)))
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    itemCount: filteredList.length,
                                    itemBuilder: (context, index) {
                                      final p = filteredList[index];
                                      final bool isHighlighted = p['isOut'] || p['hasSos'];

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          border: isHighlighted
                                              ? Border.all(color: Colors.red.shade300, width: 2)
                                              : null,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.04),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Stack(
                                              children: [
                                                CircleAvatar(
                                                  radius: 24,
                                                  backgroundColor: _kBrandBlue.withValues(alpha: 0.15),
                                                  child: Text(
                                                    _getInitials(p['name']),
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: _kBrandBlue,
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  bottom: 0,
                                                  right: 0,
                                                  child: Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      color: p['statusColor'],
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: Colors.white, width: 2),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (p['hasSos'])
                                                    Row(
                                                      children: const [
                                                        Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                                                        SizedBox(width: 4),
                                                        Text('SOS Alert', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                                                      ],
                                                    ),
                                                  Text(
                                                    p['name'],
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 15,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    p['status'],
                                                    style: TextStyle(
                                                      color: p['statusColor'],
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              children: [
                                                Row(
                                                  children: [
                                                    _actionButton('Ping', Colors.amber.shade200, Colors.black, Icons.wifi_tethering, () {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('Pinged ${p['name']}!')),
                                                      );
                                                    }),
                                                    const SizedBox(width: 6),
                                                    _actionButton('Call', Colors.green.shade100, Colors.green.shade800, Icons.phone_outlined, () {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('Calling ${p['name']}...')),
                                                      );
                                                    }),
                                                  ],
                                                ),
                                                if (p['isOut'] || p['hasSos']) ...[
                                                  const SizedBox(height: 6),
                                                  SizedBox(
                                                    width: 126,
                                                    child: _actionButton('Track', Colors.red.shade100, Colors.red.shade800, Icons.location_on_outlined, () {
                                                      Navigator.of(context).pop(p['id']);
                                                    }),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterKey, Color color) {
    final bool isSelected = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = isSelected ? 'all' : filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color.withValues(alpha: 0.9) : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _actionButton(String label, Color bgColor, Color textColor, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.color,
    required this.bgColor,
    required this.count,
    required this.isWarning,
  });

  final Color color;
  final Color bgColor;
  final String count;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: isWarning
            ? Border.all(color: color.withValues(alpha: 0.5), width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            count,
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingActionButton extends StatelessWidget {
  const _FloatingActionButton({
    required this.icon,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: _kBrandYellow,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 26, color: Colors.black87),
          ),
          if (badgeCount != null && badgeCount! > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Tourist UI: full-screen map with tour-ending detection and tourist controls.
class _TouristTrackingView extends StatefulWidget {
  const _TouristTrackingView({
    super.key,
    required this.tourId,
    required this.role,
    this.onGroupChatTap,
    this.initialPosition,
  });

  final String tourId;
  final TrackingRole role;
  final VoidCallback? onGroupChatTap;
  final LatLng? initialPosition;
  static const LatLng _auckland = LatLng(-36.8485, 174.7633);

  @override
  State<_TouristTrackingView> createState() => _TouristTrackingViewState();
}

class _TouristTrackingViewState extends State<_TouristTrackingView> {
  final AuthService _authService = AuthService();
  final LocationService _locationService = LocationService();
  final LocationRepository _locationRepository = LocationRepository();
  final NotificationService _notificationService = NotificationService();
  Future<void> _chatNotifications = Future<void>.value();
  bool _canOpenChat = false;
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tourLocationsSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tourSubscription;
  Timer? _elapsedTimer;
  Tour? _tour;
  LatLng? _currentLocation;
  LatLng? _guidePosition;
  MapType _currentMapType = MapType.normal;
  String? _guideId;
  String? _locationError;
  String? _tourError;
  String? _displayName;
  double? _lastHeading;
  Future<void> _navigationNotifications = Future<void>.value();
  bool _isLeavingTour = false;
  final Set<Future<void>> _pendingLocationWrites = {};
  bool _hasCenteredOnTourist = false;
  bool _followTourist = false;

  void _queueNavigationNotification(Future<void> Function() action) {
    _navigationNotifications = _navigationNotifications.then((_) async {
      try {
        await action();
      } catch (error) {
        debugPrint('Guide navigation notification failed: $error');
      }
    });
  }

  void _updateGuideNavigation() {
    if (!mounted) return;
    final tourist = _currentLocation;
    final guide = _guidePosition;
    final distance = _guideDistance;
    if (tourist == null || guide == null || distance == null) {
      _queueNavigationNotification(
        () => LocalNotificationService.cancelGuideNavigation(),
      );
      return;
    }

    final bearing = TourNavigationService.calculateBearing(
      latitude1: tourist.latitude,
      longitude1: tourist.longitude,
      latitude2: guide.latitude,
      longitude2: guide.longitude,
    );
    final heading = _lastHeading;
    final relativeBearing = heading == null
        ? bearing
        : (bearing - heading + 360) % 360;

    _queueNavigationNotification(() async {
      if (!mounted) return;
      await LocalNotificationService.showGuideNavigation(
        distance: distance,
        relativeBearing: relativeBearing,
      );
    });
  }

  String _elapsedTimeString = '00:00';
  final Map<Color, BitmapDescriptor> _avatarIcons = {};
  Set<Polyline> _guideConnection = {};

  double get _greenRadius => _tour?.greenRadiusMeters ?? 20.0;
  double get _amberRadius => _tour?.amberRadiusMeters ?? 60.0;

  double? get _guideDistance {
    final tourist = _currentLocation;
    final guide = _guidePosition;
    if (tourist == null || guide == null) return null;
    return Geolocator.distanceBetween(
      tourist.latitude,
      tourist.longitude,
      guide.latitude,
      guide.longitude,
    );
  }

  Color get _zoneColor {
    final distance = _guideDistance;
    if (distance == null || _tour == null) return Colors.grey;
    if (distance <= _greenRadius) return Colors.green;
    if (distance <= _amberRadius) return Colors.orange;
    return Colors.red;
  }

  String get _zoneLabel {
    if (_tour == null) return 'Waiting for tour details';
    if (_currentLocation == null) return 'Waiting for your location';
    if (_guidePosition == null) return 'Waiting for guide location';
    return _guideDistance! <= _greenRadius
        ? 'You are in the zone'
        : 'You are outside the zone';
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _currentLocation = widget.initialPosition;
      _hasCenteredOnTourist = true;
    }

    unawaited(_startTrackingSafely());
    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateElapsedTime(),
    );
  }

  void _listenToTour() {
    _tourSubscription = FirebaseFirestore.instance
        .collection('tours')
        .doc(widget.tourId)
        .snapshots()
        .listen(
          (doc) {
            if (!mounted) return;
            if (!doc.exists) {
              _showTourEndedDialog();
              return;
            }
            try {
              final tour = Tour.fromFirestore(doc);
              setState(() {
                _tour = tour;
                _tourError = null;
              });
              _updateElapsedTime();
            } catch (_) {
              setState(() => _tourError = 'Could not read tour details.');
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(
                () => _tourError = 'Tour details failed to load: $error',
              );
            }
          },
        );
  }

  void _showTourEndedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Tour Ended',
          style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'The tour guide has ended this tour. Thank you for participating!',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBrandYellow,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const TouristHomeScreen()),
                (_) => false,
              );
            },
            child: const Text('Return Home', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _updateElapsedTime() {
    if (_tour?.scheduledAt == null) return;

    final elapsed = DateTime.now().difference(_tour!.scheduledAt!);
    if (elapsed.isNegative) return;

    final hours = elapsed.inHours;
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    setState(() {
      _elapsedTimeString = hours > 0
          ? '$hours:$minutes:$seconds'
          : '$minutes:$seconds';
    });
  }

  void _listenToTourLocations() {
    _tourLocationsSubscription = _locationRepository
        .getTourLocations(widget.tourId)
        .listen(
          (snapshot) {
            if (!mounted) return;
            LatLng? guide;
            String? guideId;
            for (final doc in snapshot.docs) {
              final data = doc.data();
              if (data['role'] != TrackingRole.guide.name) continue;
              final lat = (data['latitude'] as num?)?.toDouble();
              final lng = (data['longitude'] as num?)?.toDouble();
              if (lat == null ||
                  lng == null ||
                  !lat.isFinite ||
                  !lng.isFinite ||
                  lat.abs() > 90 ||
                  lng.abs() > 180) {
                continue;
              }
              guide = LatLng(lat, lng);
              guideId = doc.id;
              break;
            }
            setState(() {
              _guidePosition = guide;
              _guideId = guideId;
              _refreshGuideConnection();
            });
            _updateGuideNavigation();
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _guidePosition = null;
              _guideId = null;
              _guideConnection = {};
              _locationError = 'Tour locations failed to load: $error';
            });
            _updateGuideNavigation();
          },
        );
  }

  Future<void> _updateCurrentLocation(Position position) async {
    if (!mounted) return;
    final location = LatLng(position.latitude, position.longitude);
    setState(() {
      _currentLocation = location;
      _refreshGuideConnection();
    });
    if (_mapController != null) {
      if (!_hasCenteredOnTourist) {
        _hasCenteredOnTourist = true;
        unawaited(_moveCamera(location, zoom: 18));
      } else if (_followTourist) {
        unawaited(_moveCamera(location));
      }
    }
  }

  Future<void> _moveCamera(LatLng location, {double? zoom}) async {
    final controller = _mapController;
    if (!mounted || controller == null) return;
    try {
      await controller.animateCamera(
        zoom == null
            ? CameraUpdate.newLatLng(location)
            : CameraUpdate.newLatLngZoom(location, zoom),
      );
    } catch (_) {}
  }

  void _recenterOnTourist() {
    final location = _currentLocation;

    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for your location.')),
      );
      return;
    }

    setState(() {
      _followTourist = !_followTourist;
    });

    unawaited(_moveCamera(location, zoom: _followTourist ? 20 : 18));
  }

  void _refreshGuideConnection() {
    final from = _currentLocation;
    final to = _guidePosition;
    final distance = _guideDistance;
    if (from == null || to == null || distance == null || distance < 0.5) {
      _guideConnection = {};
      return;
    }
    _guideConnection = {
      Polyline(
        polylineId: const PolylineId('guide_connection'),
        points: [from, to],
        color: Colors.purple,
        width: 6,
        geodesic: false,
        zIndex: 20,
      ),
    };
  }

  Set<Marker> _buildMarkers() {
    final tourist = _currentLocation;
    final guide = _guidePosition;
    return {
      if (tourist != null)
        Marker(
          markerId: const MarkerId('tourist_self'),
          position: tourist,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 10,
          icon:
              _avatarIcons[_zoneColor] ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You'),
        ),
      if (guide != null)
        Marker(
          markerId: MarkerId('guide_${_guideId ?? "current"}'),
          position: guide,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Guide'),
        ),
    };
  }

  Set<Circle> _buildCircles() {
    final guide = _guidePosition;
    if (guide == null || _tour == null) return {};
    return {
      Circle(
        circleId: const CircleId('tourist_amber_zone'),
        center: guide,
        radius: _amberRadius,
        fillColor: Colors.amber.withValues(alpha: 0.10),
        strokeColor: Colors.amber.withValues(alpha: 0.4),
        strokeWidth: 1,
      ),
      Circle(
        circleId: const CircleId('tourist_green_zone'),
        center: guide,
        radius: _greenRadius,
        fillColor: Colors.green.withValues(alpha: 0.15),
        strokeColor: Colors.green.withValues(alpha: 0.7),
        strokeWidth: 2,
      ),
    };
  }

  Future<void> _loadTouristAvatar() async {
    final user = _authService.currentUser;
    if (user == null) return;
    var name = user.displayName ?? 'You';
    String? photoUrl = user.photoURL;
    ui.Image? photo;
    try {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('tourists')
            .doc(user.uid)
            .get();
        final data = doc.data();
        final value = data?['photoUrl'];
        if (value is String && value.trim().isNotEmpty) {
          photoUrl = value;
        }
        final profileName = data?['name'];
        if (profileName is String && profileName.trim().isNotEmpty) {
          name = profileName;
        }
      } catch (_) {}
      if (photoUrl != null && photoUrl.isNotEmpty) {
        try {
          final response = await http
              .get(Uri.parse(photoUrl))
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            final codec = await ui.instantiateImageCodec(
              response.bodyBytes,
              targetWidth: 120,
              targetHeight: 120,
            );
            try {
              photo = (await codec.getNextFrame()).image;
            } finally {
              codec.dispose();
            }
          }
        } catch (_) {}
      }
      if (!mounted) return;
      final icons = <Color, BitmapDescriptor>{};
      for (final color in [
        Colors.grey,
        Colors.green,
        Colors.orange,
        Colors.red,
      ]) {
        icons[color] = await _renderTouristAvatar(photo, name, color);
      }
      if (mounted) setState(() => _avatarIcons.addAll(icons));
    } catch (_) {} finally {
      photo?.dispose();
    }
  }

  Future<BitmapDescriptor> _renderTouristAvatar(
    ui.Image? photo,
    String name,
    Color ring,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(const Offset(72, 72), 70, Paint()..color = ring);
    canvas.drawCircle(const Offset(72, 72), 62, Paint()..color = Colors.white);
    if (photo != null) {
      canvas.save();
      canvas.clipPath(
        Path()
          ..addOval(Rect.fromCircle(center: const Offset(72, 72), radius: 58)),
      );
      final side = math.min(photo.width, photo.height).toDouble();
      canvas.drawImageRect(
        photo,
        Rect.fromLTWH(
          (photo.width - side) / 2,
          (photo.height - side) / 2,
          side,
          side,
        ),
        const Rect.fromLTWH(14, 14, 116, 116),
        Paint()..filterQuality = ui.FilterQuality.high,
      );
      canvas.restore();
    } else {
      final words = name
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .take(2);
      final initials = words.map((word) => word[0]).join().toUpperCase();
      final painter = TextPainter(
        text: TextSpan(
          text: initials.isEmpty ? 'U' : initials,
          style: const TextStyle(
            color: _kBrandBlue,
            fontSize: 44,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(72 - painter.width / 2, 72 - painter.height / 2),
      );
      painter.dispose();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(144, 144);
    picture.dispose();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.bytes(
        bytes!.buffer.asUint8List(),
        width: 54,
        height: 54,
      );
    } finally {
      image.dispose();
    }
  }

  String get _distanceLabel {
    final distance = _guideDistance;
    if (distance == null) return 'Guide: locating…';
    return distance < 1000
        ? 'Guide: ${distance.round()}m'
        : 'Guide: ${(distance / 1000).toStringAsFixed(1)}km';
  }

  void _openGroupChat() {
    if (!_canOpenChat) return;
    final callback = widget.onGroupChatTap;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupChatScreen(tourId: widget.tourId),
      ),
    );
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _tourSubscription?.cancel();
    _positionSubscription?.cancel();
    _tourLocationsSubscription?.cancel();
    if (_canOpenChat) {
      unawaited(
        _chatNotifications.then(
          (_) => _tryChatNotification(
            () => _notificationService.unsubscribeFromTour(widget.tourId),
          ),
        ),
      );
    }
    _mapController?.dispose();
    _queueNavigationNotification(
      () => LocalNotificationService.cancelGuideNavigation(),
    );
    super.dispose();
  }

  Future<void> _startTrackingSafely() async {
    try {
      await _startTracking();
    } catch (error) {
      if (!mounted) return;
      setState(() => _locationError = 'Could not start tracking: $error');
    }
  }

  Future<void> _startTracking() async {
    if (_authService.currentUser == null) {
      if (!mounted) return;
      setState(() {
        _locationError = 'You must be signed in to share your location.';
      });
      return;
    }

    final userId = _authService.currentUser!.uid;
    final isParticipant = await _locationRepository.isTourParticipant(
      tourId: widget.tourId,
      userUid: userId,
    );
    if (!mounted) return;
    if (!isParticipant) {
      if (!mounted) return;
      setState(() {
        _locationError = 'You are not a participant in this tour.';
      });
      return;
    }

    setState(() => _canOpenChat = true);
    _chatNotifications = _tryChatNotification(
      () => _notificationService.subscribeToTour(widget.tourId),
    );
    _listenToTourLocations();
    _listenToTour();
    unawaited(_loadTouristAvatar());

    final permissionResult = await _locationService.requestLocationPermission();

    if (!mounted) return;
    if (permissionResult != LocationPermissionResult.granted) {
      setState(
        () => _locationError =
            'Location permission is required to share your location.',
      );
      return;
    }

    _displayName = await _loadDisplayName();

    if (widget.initialPosition != null) {
      await _recordPositionImpl(
        Position(
          latitude: widget.initialPosition!.latitude,
          longitude: widget.initialPosition!.longitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
    } else {
      Position? initialPosition;
      try {
        initialPosition = await _locationService.getCurrentPosition();
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _locationError = 'Could not get your current location: $error';
        });
        return;
      }

      if (!mounted) return;

      if (initialPosition != null) {
        await _recordPosition(initialPosition);
      }
    }

    if (!mounted) return;
    _positionSubscription = _locationService.getPositionStream().listen(
      (position) {
        unawaited(_recordPosition(position));
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _locationError = 'Location updates failed: $error';
        });
      },
    );
  }

  Future<void> _recordPosition(Position position) async {
    if (!mounted || _isLeavingTour) return;

    final operation = _recordPositionImpl(position);
    _pendingLocationWrites.add(operation);

    try {
      await operation;
    } finally {
      _pendingLocationWrites.remove(operation);
    }
  }

  Future<void> _recordPositionImpl(Position position) async {
    if (!mounted) return;
    try {
      _lastHeading = position.heading.isFinite && position.heading >= 0
          ? position.heading % 360
          : null;
      await _updateCurrentLocation(position);
      _updateGuideNavigation();
      if (!mounted) return;
      final userId = _authService.currentUser?.uid;
      if (userId == null) {
        throw Exception('No authenticated user');
      }

      await _locationRepository.updateUserLocation(
        tourId: widget.tourId,
        userUid: userId,
        role: widget.role.name,
        displayName: _displayName,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationError = 'Could not save your location: $error';
      });
    }
  }

  Future<String?> _loadDisplayName() async {
    final user = _authService.currentUser;
    if (user == null) return null;

    if (widget.role == TrackingRole.tourist) {
      return _locationRepository.getTouristName(user.uid);
    }

    return user.displayName ?? user.email;
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TouristSettingsScreen.fromLiveTour(
          tourId: widget.tourId,
          onEditProfileTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Open profile editing flow here!')),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmLeaveTour() async {
    if (_isLeavingTour) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _kDialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Leave Tour',
          style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to leave the current tour? You will be returned to the home screen.',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Leave Tour',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted || _isLeavingTour) return;

    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are no longer signed in.')),
      );
      return;
    }

    setState(() => _isLeavingTour = true);

    try {
      await Future.wait(_pendingLocationWrites.toList());

      await TourRepository().leaveTour(
        tourId: widget.tourId,
        userUid: user.uid,
        displayName: _displayName ?? user.displayName ?? 'Tourist',
      );
    } catch (error) {
      if (!mounted) return;

      setState(() => _isLeavingTour = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to leave tour: $error')));
      return;
    }

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TouristHomeScreen()),
      (_) => false,
    );
  }

  Future<void> _openTourSettingsModal() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tour Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kBrandBlue,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.layers_outlined, color: _kBrandBlue),
                title: const Text('Change Map Style'),
                trailing: DropdownButton<MapType>(
                  value: _currentMapType,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: MapType.normal,
                      child: Text('Standard'),
                    ),
                    DropdownMenuItem(
                      value: MapType.satellite,
                      child: Text('Satellite'),
                    ),
                    DropdownMenuItem(
                      value: MapType.hybrid,
                      child: Text('Hybrid'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null || !mounted) return;
                    setState(() => _currentMapType = value);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline, color: _kBrandBlue),
                title: const Text('Profile & Account Settings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(sheetContext).pop('profile'),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text(
                  'Leave Tour',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop('leave'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;

    if (action == 'leave') {
      await _confirmLeaveTour();
    } else if (action == 'profile') {
      _openSettings(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final error = _locationError ?? _tourError;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialPosition ?? _currentLocation ?? _TouristTrackingView._auckland,
              zoom: 18,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              final location = widget.initialPosition ?? _currentLocation;
              if (location != null) {
                _hasCenteredOnTourist = true;
                unawaited(_moveCamera(location, zoom: 18));
              }
            },
            markers: _buildMarkers(),
            circles: _buildCircles(),
            polylines: _guideConnection,
            padding: EdgeInsets.only(
              top: topInset + 164,
              bottom: bottomInset + 116,
            ),
            zoomControlsEnabled: false,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            mapType: _currentMapType,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 48),
                          const Expanded(
                            child: Text(
                              'TourTrack',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _kBrandBlue,
                                fontFamily: 'Nunito',
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Tourist settings',
                            onPressed: _openTourSettingsModal,
                            icon: const Icon(
                              Icons.settings_outlined,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${_tour?.name ?? "Loading tour…"} • $_elapsedTimeString',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: _zoneColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: _zoneColor),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _zoneLabel,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: bottomInset + 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _kBrandYellow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    _distanceLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Material(
                        color: Colors.red,
                        shape: const CircleBorder(
                          side: BorderSide(color: Colors.white, width: 2),
                        ),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {},
                          child: Semantics(
                            button: true,
                            label: 'SOS (not implemented)',
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.priority_high,
                                  color: Colors.black,
                                  size: 22,
                                ),
                                Text(
                                  'SOS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed: _openGroupChat,
                          style: FilledButton.styleFrom(
                            backgroundColor: _kBrandYellow,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: const StadiumBorder(
                              side: BorderSide(color: Colors.white, width: 2),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  'Group Chat',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.chat_bubble_outline, size: 22),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton.filled(
                        tooltip: 'Centre and zoom in on your location',
                        onPressed: _recenterOnTourist,
                        style: IconButton.styleFrom(
                          backgroundColor: _kBrandYellow,
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.white, width: 2),
                        ),
                        icon: const Icon(Icons.my_location, size: 28),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}