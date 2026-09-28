import 'package:cloud_firestore/cloud_firestore.dart';

class LocationRepository {
  final FirebaseFirestore _firestore;

  LocationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<String?> getTouristName(String userUid) async {
    final snapshot = await _firestore.collection('tourists').doc(userUid).get();
    return snapshot.data()?['name'] as String?;
  }

  Future<bool> isTourParticipant({
    required String tourId,
    required String userUid,
  }) async {
    final tourSnapshot = await _firestore.collection('tours').doc(tourId).get();
    if (tourSnapshot.data()?['guideUid'] == userUid) return true;

    final participants = _firestore
        .collection('tours')
        .doc(tourId)
        .collection('participants');

    final uidDocument = await participants.doc(userUid).get();
    if (uidDocument.exists) return true;

    final userIdQuery = await participants
        .where('userId', isEqualTo: userUid)
        .limit(1)
        .get();
    return userIdQuery.docs.isNotEmpty;
  }

  Future<String?> getGuideName(String userUid) async {
    final snapshot = await _firestore.collection('guides').doc(userUid).get();

    return snapshot.data()?['name'] as String?;
  }

  Future<void> updateUserLocation({
    required String tourId,
    required String userUid,
    required String role,
    String? displayName,
    required double latitude,
    required double longitude,
  }) async {
    await _firestore
        .collection('tours')
        .doc(tourId)
        .collection('locations')
        .doc(userUid)
        .set({
          'latitude': latitude,
          'longitude': longitude,
          'role': role,
          'displayName': ?displayName,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getTourLocations(String tourId) {
    return _firestore
        .collection('tours')
        .doc(tourId)
        .collection('locations')
        .snapshots();
  }

  Future<void> removeUserLocation({
    required String tourId,
    required String userUid,
  }) async {
    await _firestore
        .collection('tours')
        .doc(tourId)
        .collection('locations')
        .doc(userUid)
        .delete();
  }
}
