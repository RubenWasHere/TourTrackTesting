// Centralizes Firebase authentication operations so UI screens stay focused
// on presentation and user interaction.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

// Represents user-friendly authentication failures for the UI layer.
class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}

// Wraps FirebaseAuth calls for signup, login, logout, and auth-state access.
class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _firebaseAuth.signOut(),
      GoogleSignIn.instance.signOut(),
      FacebookAuth.instance.logOut(),
    ]);
  }

  Future<void> resetPassword({required String email}) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw const AuthException('Google did not return an ID token.');
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      return await _firebaseAuth.signInWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    } on AuthException {
      rethrow;
    } on GoogleSignInException catch (error) {
      debugPrint(
        'Google sign-in exception caught: ${error.code} - ${error.description}',
      );
      if (error.description?.contains('No credential available') ?? false) {
        throw const AuthException(
          'Credential validation failed. Make sure your SHA-1 key matches your Firebase project setup.',
        );
      }
      throw AuthException(
        error.description ?? 'Google sign-in could not be completed.',
      );
    } catch (e) {
      debugPrint('Google sign-in unexpected error: $e');
      throw const AuthException('Google sign-in could not be completed.');
    }
  }

  Future<UserCredential> signInWithFacebook() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final trackingStatus =
            await AppTrackingTransparency.trackingAuthorizationStatus;
        if (trackingStatus == TrackingStatus.notDetermined) {
          await AppTrackingTransparency.requestTrackingAuthorization();
        }
      }

      final LoginResult result = await FacebookAuth.instance.login(
        loginTracking: LoginTracking.enabled,
      );
      if (result.status != LoginStatus.success || result.accessToken == null) {
        throw const AuthException('Facebook sign-in was cancelled.');
      }
      if (result.accessToken!.type != AccessTokenType.classic) {
        throw const AuthException(
          'Facebook login needs tracking permission to continue.',
        );
      }

      final OAuthCredential credential = FacebookAuthProvider.credential(
        result.accessToken!.tokenString,
      );
      return await _firebaseAuth.signInWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    } on AuthException {
      rethrow;
    } on PlatformException catch (error) {
      debugPrint('Facebook sign-in platform exception: $error');
      if (error.code == 'channel-error') {
        throw const AuthException(
          'Facebook sign-in setup is not loaded. Stop and rebuild the app.',
        );
      }
      throw AuthException(
        error.message ?? 'Facebook sign-in could not be completed.',
      );
    } catch (e) {
      debugPrint('Facebook sign-in unexpected error: $e');
      throw const AuthException('Facebook sign-in could not be completed.');
    }
  }

  String _messageFor(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'The email or password is incorrect.';
      case 'network-request-failed':
        return 'Check your internet connection and try again.';
      case 'missing-android-pkg-name':
      case 'missing-continue-uri':
      case 'missing-ios-bundle-id':
      case 'invalid-continue-uri':
      case 'unauthorized-continue-uri':
        return 'Password reset is not configured correctly. Please contact support.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with a different sign-in method.';
      case 'credential-already-in-use':
        return 'This account is already linked to another user.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled. Please contact support.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
