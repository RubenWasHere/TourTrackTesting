import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum MessageType { message, announcement, help }

enum HelpSeverity { question, assistance, emergency }

class ChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final MessageType type;
  final HelpSeverity? severity;
  final DateTime? timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.senderPhotoUrl,
    required this.type,
    required this.severity,
    required this.timestamp,
  });

  bool get isAnnouncement => type == MessageType.announcement;
  bool get isHelp => type == MessageType.help;

  factory ChatMessage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final rawType = data['type'] as String?;
    final type = rawType != null
        ? MessageType.values.firstWhere(
            (t) => t.name == rawType,
            orElse: () => MessageType.message,
          )
        : (data['isAnnouncement'] == true
              ? MessageType.announcement
              : MessageType.message);

    final rawSeverity = data['severity'] as String?;
    final severity = rawSeverity != null
        ? HelpSeverity.values.firstWhere(
            (s) => s.name == rawSeverity,
            orElse: () => HelpSeverity.question,
          )
        : null;

    return ChatMessage(
      id: doc.id,
      text: data['text'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      type: type,
      severity: severity,
      // Null until the write round-trips to Firestore's servers.
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
    );
  }
}

class ChatService {
  ChatService({required this.tourId});

  // Which tour's chat this instance talks to. Every message lives under
  // tours/{tourId}/messages instead of one shared top-level collection,
  // so different tours don't see each other's chat.
  final String tourId;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _firestore.collection('tours').doc(tourId).collection('messages');

  Stream<List<ChatMessage>> messagesStream() {
    return _messagesRef
        .orderBy('timestamp')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ChatMessage.fromDoc).toList());
  }

  Stream<List<ChatMessage>> latestAnnouncementStream() {
    return _messagesRef
        .where('type', isEqualTo: MessageType.announcement.name)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ChatMessage.fromDoc).toList());
  }

  // Looks up the current user's display name + photo.
  //
  // Neither tourists nor guides have this set on FirebaseAuth directly —
  // tourists sign in anonymously, and guides sign up with just
  // email/password. Both store their real profile (name, phone, photoUrl)
  // in Firestore instead: tourists under tourists/{uid}, guides under
  // guides/{uid}. We check both, then fall back to whatever FirebaseAuth
  // has directly as a last resort
  Future<({String name, String? photoUrl})> _resolveSenderProfile(
    User user,
  ) async {
    final touristDoc = await _firestore
        .collection('tourists')
        .doc(user.uid)
        .get();

    if (touristDoc.exists) {
      final data = touristDoc.data()!;
      return (
        name: data['name'] as String? ?? 'Unknown',
        photoUrl: data['photoUrl'] as String?,
      );
    }

    final guideDoc = await _firestore.collection('guides').doc(user.uid).get();
    if (guideDoc.exists) {
      final data = guideDoc.data()!;
      final name = data['name'] as String?;
      if (name != null && name.isNotEmpty) {
        return (name: name, photoUrl: data['photoUrl'] as String?);
      }
    }

    return (name: user.displayName ?? 'Unknown', photoUrl: user.photoURL);
  }

  Future<bool> isCurrentUserGuide() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final guideDoc = await _firestore.collection('guides').doc(user.uid).get();
    return guideDoc.exists;
  }

  Future<void> sendMessage(String text) async {
    await _send(text, type: MessageType.message);
  }

  Future<void> sendAnnouncement(String text) async {
    final isGuide = await isCurrentUserGuide();
    if (!isGuide) {
      throw StateError('Only guides can send announcements.');
    }
    await _send(text, type: MessageType.announcement);
  }

  // Text can be empty here — a tourist might just tap "Emergency" with
  // no message, and that alone should still notify the guide.
  //
  // Restricted to tourists (not guides) — mirrors sendAnnouncement's
  // guide-only check, just inverted.
  Future<void> sendHelpRequest(String text, HelpSeverity severity) async {
    final isGuide = await isCurrentUserGuide();
    if (isGuide) {
      throw StateError('Only tourists can send help requests.');
    }
    await _send(
      text,
      type: MessageType.help,
      severity: severity,
      allowEmpty: true,
    );
  }

  Future<void> _send(
    String text, {
    required MessageType type,
    HelpSeverity? severity,
    bool allowEmpty = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && !allowEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Cannot send a message: no user is logged in.');
    }

    final profile = await _resolveSenderProfile(user);

    await _messagesRef.add({
      'text': trimmed,
      'senderId': user.uid,
      'senderName': profile.name,
      'senderPhotoUrl': profile.photoUrl,
      'type': type.name,
      if (severity != null) 'severity': severity.name,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
