// ============================================================
// tour_repository.dart
// ============================================================

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tourtrack/models/tour.dart';

class JoinedTour {
  const JoinedTour({required this.id, required this.name});

  final String id;
  final String? name;
}

class TourRepository {
  final FirebaseFirestore _firestore;

  TourRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  // ---------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------
  Future<String> createTour({
    required String name,
    String? description,
    required String guideUid,
    DateTime? scheduledAt,
    String? startLocationName,
    double? startLocationLat,
    double? startLocationLng,
    int? expectedHeadcount,
    String? photoUrl,
    double? greenRadiusMeters,
    double? amberRadiusMeters,
    bool isPreset = false,
  }) async {
    final tourRef = _firestore.collection('tours').doc();
    final joinCode = await _generateUniqueJoinCode();

    await tourRef.set({
      'name': name,
      'description': description,
      'guideUid': guideUid,
      'joinCode': joinCode,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'scheduledAt': scheduledAt,
      'startLocationName': startLocationName,
      'startLocationLat': startLocationLat,
      'startLocationLng': startLocationLng,
      'expectedHeadcount': expectedHeadcount,
      'photoUrl': photoUrl,
      'greenRadiusMeters': greenRadiusMeters,
      'amberRadiusMeters': amberRadiusMeters,
      'isPreset': isPreset,
    });
    return tourRef.id;
  }

  Future<String> createTourFromPreset({
    required Tour preset,
    required DateTime scheduledAt,
    String? nameOverride,
  }) {
    return createTour(
      name: nameOverride ?? preset.name,
      description: preset.description,
      guideUid: preset.guideUid,
      scheduledAt: scheduledAt,
      startLocationName: preset.startLocationName,
      startLocationLat: preset.startLocationLat,
      startLocationLng: preset.startLocationLng,
      expectedHeadcount: preset.expectedHeadcount,
      photoUrl: preset.photoUrl,
      greenRadiusMeters: preset.greenRadiusMeters,
      amberRadiusMeters: preset.amberRadiusMeters,
      isPreset: false,
    );
  }

  // ---------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------
  static const _unset = Object();

  Future<void> updateTour(
    String tourId, {
    String? name,
    Object? description = _unset,
    Object? scheduledAt = _unset,
    Object? startLocationName = _unset,
    Object? startLocationLat = _unset,
    Object? startLocationLng = _unset,
    Object? expectedHeadcount = _unset,
    Object? photoUrl = _unset,
    Object? greenRadiusMeters = _unset,
    Object? amberRadiusMeters = _unset,
    Object? calendarEventId = _unset,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (!identical(description, _unset)) updates['description'] = description;
    if (!identical(scheduledAt, _unset)) updates['scheduledAt'] = scheduledAt;
    if (!identical(startLocationName, _unset)) {
      updates['startLocationName'] = startLocationName;
    }
    if (!identical(startLocationLat, _unset)) {
      updates['startLocationLat'] = startLocationLat;
    }
    if (!identical(startLocationLng, _unset)) {
      updates['startLocationLng'] = startLocationLng;
    }
    if (!identical(expectedHeadcount, _unset)) {
      updates['expectedHeadcount'] = expectedHeadcount;
    }
    if (!identical(photoUrl, _unset)) updates['photoUrl'] = photoUrl;
    if (!identical(greenRadiusMeters, _unset)) {
      updates['greenRadiusMeters'] = greenRadiusMeters;
    }
    if (!identical(amberRadiusMeters, _unset)) {
      updates['amberRadiusMeters'] = amberRadiusMeters;
    }
    if (!identical(calendarEventId, _unset)) {
      updates['calendarEventId'] = calendarEventId;
    }

    if (updates.isEmpty) return;
    await _firestore.collection('tours').doc(tourId).update(updates);
  }

  // ---------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------
  Future<void> deleteTour(String tourId) async {
    final tourRef = _firestore.collection('tours').doc(tourId);

    // Clean up subcollections to prevent orphaned documents
    final participantsDocs = await tourRef.collection('participants').get();
    for (var doc in participantsDocs.docs) {
      await doc.reference.delete();
    }

    final locationsDocs = await tourRef.collection('locations').get();
    for (var doc in locationsDocs.docs) {
      await doc.reference.delete();
    }

    final messagesDocs = await tourRef.collection('messages').get();
    for (var doc in messagesDocs.docs) {
      await doc.reference.delete();
    }

    await tourRef.delete();
  }

  // ---------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------
  Stream<List<Tour>> getScheduledToursForGuide(String guideUid) {
    return _firestore
        .collection('tours')
        .where('guideUid', isEqualTo: guideUid)
        .where('isPreset', isEqualTo: false)
        .orderBy('scheduledAt')
        .snapshots()
        .map((s) => s.docs.map(Tour.fromFirestore).toList());
  }

  Stream<List<Tour>> getPresetsForGuide(String guideUid) {
    return _firestore
        .collection('tours')
        .where('guideUid', isEqualTo: guideUid)
        .where('isPreset', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map(Tour.fromFirestore).toList());
  }

  /// Streams joined tours via the tourist's personal joined_tours subcollection
  Stream<List<Tour>> getJoinedToursForTourist(String touristUid) {
    return _firestore
        .collection('tourists')
        .doc(touristUid)
        .collection('joined_tours')
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) return <Tour>[];
      try {
        final futures = snapshot.docs.map(
          (doc) => _firestore.collection('tours').doc(doc.id).get(),
        );
        final tourDocs = await Future.wait(futures);
        return tourDocs
            .where((doc) => doc.exists)
            .map((doc) => Tour.fromFirestore(doc))
            .toList();
      } catch (_) {
        return <Tour>[];
      }
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getTourParticipants(
    String tourId,
  ) {
    return _firestore
        .collection('tours')
        .doc(tourId)
        .collection('participants')
        .snapshots();
  }

  Future<Tour?> getTour(String tourId) async {
    final doc = await _firestore.collection('tours').doc(tourId).get();
    if (!doc.exists) return null;
    return Tour.fromFirestore(doc);
  }

  // ---------------------------------------------------------------------
  // Join
  // ---------------------------------------------------------------------
  Future<JoinedTour> joinTour({
    required String joinCode,
    required String userUid,
  }) async {
    final snapshot = await _firestore
        .collection('tours')
        .where('joinCode', isEqualTo: joinCode)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      throw Exception('Tour Not Found!');
    }

    final tour = snapshot.docs.first;

    // Add participant record
    await tour.reference.collection('participants').doc(userUid).set({
      'joinAt': FieldValue.serverTimestamp(),
    });

    // Add to tourist's joined tours subcollection for instant, index-free queries
    await _firestore
        .collection('tourists')
        .doc(userUid)
        .collection('joined_tours')
        .doc(tour.id)
        .set({'joinedAt': FieldValue.serverTimestamp()});

    return JoinedTour(id: tour.id, name: tour.data()['name'] as String?);
  }

  Future<String?> getTouristName(String userUid) async {
    final snapshot = await _firestore.collection('tourists').doc(userUid).get();
    return snapshot.data()?['name'] as String?;
  }

  // ---------------------------------------------------------------------
  // Join code generation
  // ---------------------------------------------------------------------
  Future<String> _generateUniqueJoinCode() async {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ23456789';
    final random = Random();

    for (var attempt = 0; attempt < 10; attempt++) {
      final code = List.generate(
        6,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
      final existing = await _firestore
          .collection('tours')
          .where('joinCode', isEqualTo: code)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) return code;
    }
    throw Exception('Could not generate a unique join code, try again.');
  }

  // ---------------------------------------------------------------------
  // Participants
  // ---------------------------------------------------------------------

  Future<void> leaveTour({
    required String tourId,
    required String userUid,
    String? displayName,
  }) async {
    final tourRef = _firestore.collection('tours').doc(tourId);
    final participantRef = tourRef.collection('participants').doc(userUid);
    final touristJoinedTourRef = _firestore
        .collection('tourists')
        .doc(userUid)
        .collection('joined_tours')
        .doc(tourId);

    await _firestore.runTransaction((transaction) async {
      final tourSnapshot = await transaction.get(tourRef);

      if (!tourSnapshot.exists) {
        throw Exception('Tour not found.');
      }

      final tourData = tourSnapshot.data();
      if (tourData == null) {
        throw Exception('Tour data is unavailable.');
      }

      final guideUid = tourData['guideUid'] as String?;
      if (guideUid == null || guideUid.isEmpty) {
        throw Exception('Tour has no guide.');
      }

      final participantSnapshot = await transaction.get(participantRef);
      if (!participantSnapshot.exists) {
        throw Exception('You are no longer a participant in this tour.');
      }

      final notificationRef = _firestore
          .collection('guides')
          .doc(guideUid)
          .collection('notifications')
          .doc();

      transaction.set(notificationRef, {
        'type': 'participant_left',
        'tourId': tourId,
        'userUid': userUid,
        'displayName': displayName,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.delete(participantRef);
      transaction.delete(tourRef.collection('locations').doc(userUid));
      transaction.delete(touristJoinedTourRef);
    });
  }

  Future<void> removeParticipant({
    required String tourId,
    required String userUid,
  }) async {
    await _firestore
        .collection('tours')
        .doc(tourId)
        .collection('participants')
        .doc(userUid)
        .delete();
    await _firestore
        .collection('tourists')
        .doc(userUid)
        .collection('joined_tours')
        .doc(tourId)
        .delete();
  }
}