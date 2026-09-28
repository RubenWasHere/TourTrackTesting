import 'package:cloud_firestore/cloud_firestore.dart';

class TourInvite {
  final String id;
  final String tourId;
  final String joinCode;

  const TourInvite({
    required this.id,
    required this.tourId,
    required this.joinCode,
  });

  factory TourInvite.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;

    return TourInvite(
      id: doc.id,
      tourId: data['tourId'] as String,
      joinCode: data['joinCode'] as String,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {'tourId': tourId, 'joinCode': joinCode};
  }
}
