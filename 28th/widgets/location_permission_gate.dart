import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';

const _kBrandYellow = Color(0xFFFFDE59);

class LocationPermissionGate extends StatefulWidget {
  const LocationPermissionGate({required this.child, super.key});

  final Widget child;

  @override
  State<LocationPermissionGate> createState() => _LocationPermissionGateState();
}

class _LocationPermissionGateState extends State<LocationPermissionGate>
    with WidgetsBindingObserver {
  final LocationService _locationService = LocationService();
  LocationPermissionResult? _result;
  bool _isChecking = true;
  bool _isOpeningSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    setState(() => _isChecking = true);
    final result = await _locationService.requestLocationPermission();
    if (!mounted) return;
    setState(() {
      _result = result;
      _isChecking = false;
      _isOpeningSettings = false;
    });
  }

  Future<void> _openSettings() async {
    setState(() {
      _isOpeningSettings = true;
      _isChecking = false;
    });

    if (_result == LocationPermissionResult.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking ||
        _isOpeningSettings ||
        _result == LocationPermissionResult.granted) {
      return widget.child;
    }

    final isServiceDisabled =
        _result == LocationPermissionResult.serviceDisabled;
    final isPermanentlyDenied =
        _result == LocationPermissionResult.deniedForever;
    final message = switch (_result) {
      LocationPermissionResult.serviceDisabled =>
        'Turn on location services so TourTrack can show your position during a tour.',
      LocationPermissionResult.denied =>
        'Location permission is needed to show your position to your tour group.',
      LocationPermissionResult.deniedForever =>
        'Location permission is blocked. Open settings to allow TourTrack to use your location.',
      _ => 'Location permission is required for live tour tracking.',
    };

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_outlined, size: 56),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              // make button wider so text doesn't wrap
              SizedBox(
                width: 200,
                child: FilledButton(
                  onPressed: isServiceDisabled || isPermanentlyDenied
                      ? _openSettings
                      : _checkPermission,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kBrandYellow,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isServiceDisabled || isPermanentlyDenied
                        ? 'Open Settings'
                        : 'Try Again',
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
