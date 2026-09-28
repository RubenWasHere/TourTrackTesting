import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> initialise() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    // Request notification permission.
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // Allow notification messages to be displayed while the app
    // is in the foreground on iOS.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle FCM messages while the app is in the foreground.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;

      if (notification == null) {
        return;
      }

      LocalNotificationService.show(
        title: notification.title ?? 'TourTrack',
        body: notification.body ?? '',
      );
    });

    // Listen for FCM token updates and save them to Firestore first so
    // even if the initial token lookup fails we can still update the token later
    _messaging.onTokenRefresh.listen(
      (newToken) async {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) return;

        try {
          await _saveToken(currentUser.uid, newToken);
        } catch (error) {
          debugPrint('Could not save refreshed FCM token: $error');
        }
      },
      onError: (Object error) {
        debugPrint('FCM token refresh failed: $error');
      },
    );

    // Token registration must not hold up app startup
    unawaited(_registerInitialToken());
  }

  Future<void> _registerInitialToken() async {
    try {
      final isApple =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);

      if (isApple) {
        String? apnsToken;

        // Give Apple a short opportunity to finish registration
        // This runs independently of app startup
        for (var attempt = 0; attempt < 5; attempt++) {
          apnsToken = await _messaging.getAPNSToken();
          if (apnsToken != null) break;

          if (attempt < 4) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }

        if (apnsToken == null) {
          debugPrint(
            'APNs token unavailable; initial push registration deferred.',
          );
          return;
        }
      }

      final token = await _messaging.getToken();
      final currentUser = FirebaseAuth.instance.currentUser;

      if (token != null && currentUser != null) {
        await _saveToken(currentUser.uid, token);
      }
    } catch (error) {
      debugPrint('Initial push registration failed: $error');
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    await _firestore.collection('guides').doc(uid).set({
      'fcmToken': token,
    }, SetOptions(merge: true));
  }

  static const _messageNotificationsPrefKey = 'message_notifications_enabled';

  Future<void> subscribeToTour(String tourId) async {
    await _messaging.subscribeToTopic('tour_${tourId}_announcements');

    if (await areMessageNotificationsEnabled()) {
      await _messaging.subscribeToTopic('tour_${tourId}_messages');
    }
  }

  Future<void> unsubscribeFromTour(String tourId) async {
    await _messaging.unsubscribeFromTopic('tour_${tourId}_announcements');
    await _messaging.unsubscribeFromTopic('tour_${tourId}_messages');
  }

  Future<bool> areMessageNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_messageNotificationsPrefKey) ?? true;
  }

  Future<void> setMessageNotificationsEnabled(
    bool enabled, {
    String? currentTourId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_messageNotificationsPrefKey, enabled);

    if (currentTourId == null) return;

    if (enabled) {
      await _messaging.subscribeToTopic('tour_${currentTourId}_messages');
    } else {
      await _messaging.unsubscribeFromTopic('tour_${currentTourId}_messages');
    }
  }
}

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  static const int participantCountNotificationId = 1002;

  static Future<void> showParticipantCount({required int count}) async {
    const androidDetails = AndroidNotificationDetails(
      'tourtrack_participants',
      'Tour Participants',
      channelDescription: 'Current number of tourists on the tour',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await notifications.show(
      participantCountNotificationId,
      'TourTrack',
      '👥 $count ${count == 1 ? 'tourist' : 'tourists'} on tour',
      details,
    );
  }

  static Future<void> initialise() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    const ios = DarwinInitializationSettings();

    const settings = InitializationSettings(android: android, iOS: ios);

    await notifications.initialize(settings);
  }

  static Future<void> show({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'tourtrack_notifications',
      'TourTrack Notifications',
      channelDescription: 'Notifications from TourTrack',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
    );
  }

  static const int guideNavigationNotificationId = 1001;

  static String _navigationArrow(double relativeBearing) {
    if (relativeBearing < 22.5 || relativeBearing >= 337.5) {
      return '↑';
    } else if (relativeBearing < 67.5) {
      return '↗';
    } else if (relativeBearing < 112.5) {
      return '→';
    } else if (relativeBearing < 157.5) {
      return '↘';
    } else if (relativeBearing < 202.5) {
      return '↓';
    } else if (relativeBearing < 247.5) {
      return '↙';
    } else if (relativeBearing < 292.5) {
      return '←';
    } else {
      return '↖';
    }
  }

  static Future<void> showGuideNavigation({
    required double distance,
    required double relativeBearing,
  }) async {
    final arrow = _navigationArrow(relativeBearing);

    final distanceText = distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(1)} km'
        : '${distance.round()} m';

    const androidDetails = AndroidNotificationDetails(
      'tourtrack_navigation',
      'Tour Navigation',
      channelDescription: 'Live direction to your tour guide',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await notifications.show(
      guideNavigationNotificationId,
      'Guide',
      '$arrow  $distanceText',
      details,
    );
  }

  static Future<void> cancelGuideNavigation() async {
    await notifications.cancel(guideNavigationNotificationId);
  }

  static Future<void> cancelParticipantCount() async {
    await notifications.cancel(participantCountNotificationId);
  }
}
