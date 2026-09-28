// ============================================================
// tourist_profile.dart
// A read-only view of the data saved in Firestore under
// tourists/{uid} — used to show the signed-in tourist's own name,
// phone number, and photo back to them.
// ============================================================

class TouristProfile {
  final String name;
  final String phoneNumber;
  final String? photoUrl; // null if they never added a photo

  const TouristProfile({
    required this.name,
    required this.phoneNumber,
    this.photoUrl,
  });

  // Builds a TouristProfile from a Firestore document's data map.
  factory TouristProfile.fromMap(Map<String, dynamic> data) {
    return TouristProfile(
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? data['name'] as String
          : 'Tourist',
      phoneNumber: (data['phoneNumber'] as String?) ?? '',
      photoUrl: data['photoUrl'] as String?,
    );
  }
}