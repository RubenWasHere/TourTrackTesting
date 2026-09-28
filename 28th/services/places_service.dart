// ============================================================
// places_service.dart
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class PlaceSuggestion {
  final String placeId;
  final String description;

  const PlaceSuggestion({required this.placeId, required this.description});
}

class PlaceLocation {
  final String name;
  final double latitude;
  final double longitude;

  const PlaceLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class PlacesService {
  static String get _apiKey {
    if (kIsWeb) {
      throw UnsupportedError('Places API is not configured for web.');
    }

    final keyName = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'PLACES_ANDROID_API_KEY',
      TargetPlatform.iOS => 'PLACES_IOS_API_KEY',
      _ => throw UnsupportedError(
        'Places API is only configured for Android and iOS.',
      ),
    };

    final key = dotenv.env[keyName] ?? '';
    if (key.isEmpty) {
      throw StateError(
        '$keyName is missing from .env.',
      );
    }
    return key;
  }

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': _apiKey,
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
      'X-Ios-Bundle-Identifier': 'com.example.tourtrack',
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...{
      'X-Android-Package': 'com.example.tourtrack',
      // SHA-1 for the shared debug signing certificate
      'X-Android-Cert': '15D22AB2665C4971E8965DDA2A49882ED2E77A35',
    },
  };

  String? _sessionToken;
  String _ensureSession() => _sessionToken ??= DateTime.now().microsecondsSinceEpoch.toString();

  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    double? guideLatitude,
    double? guideLongitude,
  }) async {
    if (input.trim().isEmpty) return [];

    final uri = Uri.https('places.googleapis.com', '/v1/places:autocomplete');

    final Map<String, dynamic> requestBody = {
      'input': input,
      'sessionToken': _ensureSession(),
    };

    if (guideLatitude != null && guideLongitude != null) {
      requestBody['locationRestriction'] = {
        'circle': {
          'center': {
            'latitude': guideLatitude,
            'longitude': guideLongitude,
          },
          'radius': 50000.0,
        }
      };
    }

    final response = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      throw Exception('Place search failed (${response.statusCode}): ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final suggestions = (body['suggestions'] as List<dynamic>?) ?? [];
    
    return suggestions
        .where((s) => s['placePrediction'] != null)
        .map(
          (s) {
            final prediction = s['placePrediction'];
            return PlaceSuggestion(
              placeId: prediction['placeId'] as String,
              description: prediction['text']['text'] as String,
            );
          },
        )
        .toList();
  }

  Future<PlaceLocation> getLocation(PlaceSuggestion suggestion) async {
    final uri = Uri.https(
      'places.googleapis.com',
      '/v1/places/${suggestion.placeId}',
      {
        'sessionToken': _ensureSession(),
      }
    );
    
    final response = await http.get(
      uri,
      headers: {
        ..._headers,
        'X-Goog-FieldMask': 'displayName,location',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Could not look up that place (${response.statusCode}): ${response.body}',
      );
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    
    final location = result['location'] as Map<String, dynamic>?;
    if (location == null) {
      throw Exception('Place has no location coordinates.');
    }

    final displayName = result['displayName'] as Map<String, dynamic>?;
    _sessionToken = null;

    return PlaceLocation(
      name: (displayName != null && displayName['text'] != null)
          ? displayName['text'] as String
          : suggestion.description,
      latitude: (location['latitude'] as num).toDouble(),
      longitude: (location['longitude'] as num).toDouble(),
    );
  }
}
