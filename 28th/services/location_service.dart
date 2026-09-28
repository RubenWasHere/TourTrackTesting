// ============================================================
// location_service.dart
// ============================================================
// This service handles device location permissions and GPS readings,
// including foreground/background stream configurations for reliable tracking.
// ============================================================

import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

enum LocationPermissionResult {
  granted,
  serviceDisabled,
  denied,
  deniedForever,
}

class LocationService {
  Future<LocationPermissionResult> requestLocationPermission() async {
    // Check whether location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return LocationPermissionResult.serviceDisabled;
    }

    // Check existing permission
    LocationPermission permission = await Geolocator.checkPermission();

    // Ask for permission if it hasn't been granted
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        return LocationPermissionResult.denied;
      }
    }

    // User has permanently denied location access
    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionResult.deniedForever;
    }

    // Permission is either whileInUse or always
    return LocationPermissionResult.granted;
  }

  Future<Position?> getCurrentPosition() async {
    // Request location permission
    final permissionResult = await requestLocationPermission();

    if (permissionResult != LocationPermissionResult.granted) {
      return null;
    }

    // Get the current position with high accuracy for better precision
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2, // Updated to 2 meters for faster single-shot reads
    );

    // Get the current position
    return await Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );
  }

  Stream<Position> getPositionStream() {
    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // 2 meters prevents jitter while staying snappy
        intervalDuration: const Duration(seconds: 2), // 2-second check interval
        // Keeps GPS alive in the background when the phone is locked or in a pocket
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "TourTrack is active",
          notificationText: "Sharing your location to keep the tour group connected.",
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // 2 meters
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );
    }

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}