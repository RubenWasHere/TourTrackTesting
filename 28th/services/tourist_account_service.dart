// ============================================================
// tourist_account_service.dart
// ============================================================

import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/tourist_profile.dart';

class TouristAccountService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Streams the CURRENTLY signed-in tourist's own profile (name, phone, photo)
  // straight from Firestore. Using a Stream means the UI updates instantly
  // whenever the document changes.
  Stream<TouristProfile?> watchCurrentTouristProfile() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Stream.value(null);
    }

    return _firestore.collection('tourists').doc(uid).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return TouristProfile.fromMap(data);
    });
  }

  // Primary method supporting both names to prevent missing method errors
  Future<void> createTouristAccount({
    required String name,
    required String fullPhoneNumber,
    File? photoFile,
  }) async {
    return createOrLinkTouristAccount(
      name: name,
      fullPhoneNumber: fullPhoneNumber,
      photoFile: photoFile,
    );
  }

  Future<void> createOrLinkTouristAccount({
    required String name,
    required String fullPhoneNumber,
    File? photoFile,
  }) async {
    User? user = _auth.currentUser;
    if (user == null) {
      final userCredential = await _auth.signInAnonymously();
      user = userCredential.user;
    }
    final uid = user!.uid;

    String? photoUrl;
    if (photoFile != null) {
      final storageRef = _storage.ref().child('tourist_photos/$uid.jpg');
      await storageRef.putFile(photoFile);
      photoUrl = await storageRef.getDownloadURL();
    }

    final data = <String, dynamic>{
      'name': name,
      'phoneNumber': fullPhoneNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (photoUrl != null) {
      data['photoUrl'] = photoUrl;
    }

    await _firestore
        .collection('tourists')
        .doc(uid)
        .set(data, SetOptions(merge: true));
  }

  // Updates tourist profile details cleanly from the settings screen
  Future<void> updateTouristProfile({
    required String name,
    required String fullPhoneNumber,
    File? photoFile,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError(
        'No authenticated user found while saving tourist profile.',
      );
    }
    final uid = user.uid;

    String? photoUrl;
    if (photoFile != null) {
      final storageRef = _storage.ref().child('tourist_photos/$uid.jpg');
      await storageRef.putFile(photoFile);
      photoUrl = await storageRef.getDownloadURL();
    }

    final data = <String, dynamic>{
      'name': name,
      'phoneNumber': fullPhoneNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (photoUrl != null) {
      data['photoUrl'] = photoUrl;
    }

    await _firestore
        .collection('tourists')
        .doc(uid)
        .set(data, SetOptions(merge: true));
  }

  Future<void> deleteTouristAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (!user.isAnonymous) {
      throw StateError(
        'This session belongs to a registered account. Account deletion stopped.',
      );
    }

    final uid = user.uid;

    try {
      await _storage.ref().child('tourist_photos/$uid.jpg').delete();
    } catch (_) {}

    try {
      await _firestore.collection('tourists').doc(uid).delete();
    } catch (_) {}

    await user.delete();
  }
}
