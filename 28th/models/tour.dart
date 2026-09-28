// ============================================================
// models/tour.dart
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';

/// A single tour created by a guide.
class Tour {
  final String id;
  final String name;
  final String guideUid;
  final String joinCode;
  final String status;
  final DateTime createdAt;

  // ---- Scheduling ----
  final DateTime? scheduledAt;

  // ---- Meeting point ----
  final String? startLocationName;
  final double? startLocationLat;
  final double? startLocationLng;

  // ---- Extra config ----
  final int? expectedHeadcount;
  final String? photoUrl;
  final String? description;
  final String? calendarEventId; // <-- Tracks the native device calendar event ID

  // ---- Radius zones ----
  final double? greenRadiusMeters;
  final double? amberRadiusMeters;

  // ---- Presets ----
  final bool isPreset;

  const Tour({
    required this.id,
    required this.name,
    required this.guideUid,
    required this.joinCode,
    required this.status,
    required this.createdAt,
    this.scheduledAt,
    this.startLocationName,
    this.startLocationLat,
    this.startLocationLng,
    this.expectedHeadcount,
    this.photoUrl,
    this.description,
    this.calendarEventId, // <-- Added here
    this.greenRadiusMeters,
    this.amberRadiusMeters,
    this.isPreset = false,
  });

  bool get hasStartLocation =>
      startLocationLat != null && startLocationLng != null;

  factory Tour.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Tour(
      id: doc.id,
      name: data['name'] as String,
      guideUid: data['guideUid'] as String,
      joinCode: data['joinCode'] as String,
      status: data['status'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      scheduledAt: (data['scheduledAt'] as Timestamp?)?.toDate(),
      startLocationName: data['startLocationName'] as String?,
      startLocationLat: (data['startLocationLat'] as num?)?.toDouble(),
      startLocationLng: (data['startLocationLng'] as num?)?.toDouble(),
      expectedHeadcount: (data['expectedHeadcount'] as num?)?.toInt(),
      photoUrl: data['photoUrl'] as String?,
      description: data['description'] as String?,
      calendarEventId: data['calendarEventId'] as String?, // <-- Parsed here
      greenRadiusMeters: (data['greenRadiusMeters'] as num?)?.toDouble(),
      amberRadiusMeters: (data['amberRadiusMeters'] as num?)?.toDouble(),
      isPreset: data['isPreset'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'guideUid': guideUid,
      'joinCode': joinCode,
      'status': status,
      'createdAt': createdAt,
      'scheduledAt': scheduledAt,
      'startLocationName': startLocationName,
      'startLocationLat': startLocationLat,
      'startLocationLng': startLocationLng,
      'expectedHeadcount': expectedHeadcount,
      'photoUrl': photoUrl,
      'description': description,
      'calendarEventId': calendarEventId, // <-- Serialized here
      'greenRadiusMeters': greenRadiusMeters,
      'amberRadiusMeters': amberRadiusMeters,
      'isPreset': isPreset,
    };
  }
}
