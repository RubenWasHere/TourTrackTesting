import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tourtrack/models/tour_invite.dart';

abstract class TourInviteRepository {
  Future<void> createInvite(TourInvite instance);
  Future<TourInvite?> getInviteByCode(String code);
  Future<TourInvite?> getInviteById(String id);
}

class FirestoreTourInviteRepository implements TourInviteRepository {
  final FirebaseFirestore firestore;

  FirestoreTourInviteRepository({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<void> createInvite(TourInvite invite) async {
    await firestore
        .collection('tourInvites')
        .doc(invite.id)
        .set(invite.toFirestore());
  }

  @override
  Future<TourInvite?> getInviteById(String id) async {
    final doc = await firestore.collection('tourInvites').doc(id).get();

    if (!doc.exists) {
      return null;
    }

    return TourInvite.fromFirestore(doc);
  }

  @override
  Future<TourInvite?> getInviteByCode(String code) async {
    final snapshot = await firestore
        .collection('tourInvites')
        .where('joinCode', isEqualTo: code)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    return TourInvite.fromFirestore(snapshot.docs.first);
  }
}
