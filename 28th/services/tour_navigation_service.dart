import 'dart:math';

class TourNavigationService {
  static double calculateDistance({
    required double latitude1,
    required double longitude1,
    required double latitude2,
    required double longitude2,
  }) {
    const earthRadius = 6371000.0;

    final lat1 = _degreesToRadians(latitude1);
    final lat2 = _degreesToRadians(latitude2);

    final deltaLat = _degreesToRadians(latitude2 - latitude1);
    final deltaLon = _degreesToRadians(longitude2 - longitude1);

    final a =
        sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  static double calculateBearing({
    required double latitude1,
    required double longitude1,
    required double latitude2,
    required double longitude2,
  }) {
    final lat1 = _degreesToRadians(latitude1);
    final lat2 = _degreesToRadians(latitude2);
    final deltaLon = _degreesToRadians(longitude2 - longitude1);

    final y = sin(deltaLon) * cos(lat2);

    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon);

    final bearing = atan2(y, x) * 180 / pi;

    return (bearing + 360) % 360;
  }

  /// Converts a bearing into a human-readable compass direction.
  static String bearingToDirection(double bearing) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

    final index = ((bearing + 22.5) / 45).floor() % 8;

    return directions[index];
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }
}
