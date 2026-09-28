// ============================================================
// guide_account_service.dart
// ============================================================

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class GuideAccountService {
  GuideAccountService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  // Streams the current guide's profile data for real-time UI updates
  Stream<Map<String, dynamic>?> watchCurrentGuideProfile() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);

    return _firestore.collection('guides').doc(uid).snapshots().map((doc) {
      return doc.data();
    });
  }

  // Existing core method for handling initial auth login/creation
  Future<void> createOrUpdateGuideAccount(UserCredential credential) async {
    final user = credential.user;
    if (user == null) {
      throw StateError(
        'Guide account was created without an authenticated user.',
      );
    }

    final providerId = credential.additionalUserInfo?.providerId;
    final guideReference = _firestore.collection('guides').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(guideReference);
      final profile = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'role': 'guide',
        if (providerId != null) 'provider': providerId,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!snapshot.exists) {
        profile['createdAt'] = FieldValue.serverTimestamp();
      }
      transaction.set(guideReference, profile, SetOptions(merge: true));
    });
  }

  // Saves name, phone number, and optional profile picture from GuideSetupScreen
  Future<void> saveGuideProfile({
    required String name,
    required String fullPhoneNumber,
    File? photoFile,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found while saving guide profile.');
    }
    final uid = user.uid;

    String? photoUrl;
    if (photoFile != null) {
      final storageRef = _storage.ref().child('guide_photos/$uid.jpg');
      await storageRef.putFile(photoFile);
      photoUrl = await storageRef.getDownloadURL();
    }

    final guideReference = _firestore.collection('guides').doc(uid);

    await _firestore.runTransaction((transaction) async {
      final profile = <String, dynamic>{
        'name': name,
        'phoneNumber': fullPhoneNumber,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      transaction.set(guideReference, profile, SetOptions(merge: true));
    });
  }
}
