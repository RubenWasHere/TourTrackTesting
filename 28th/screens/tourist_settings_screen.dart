// ============================================================
// tourist_settings_screen.dart
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/tour_repository.dart';
import '../models/tourist_profile.dart';
import '../services/tourist_account_service.dart';
import '../services/notification_service.dart';
import 'role_selection_screen.dart';
import 'tourist_home_screen.dart';

const _kBrandBlue = Color(0xFF1F4E9E);
const _kBrandYellow = Color(0xFFFFDE59);
const _kFieldFill = Color(0xFFF3F3F3);
const _kBorderGrey = Color(0xFFE0E0E0);
const _kDialogBg = Color(0xFFFFFDF5);

class TouristSettingsScreen extends StatelessWidget {
  const TouristSettingsScreen({
    super.key,
    required this.onEditProfileTap,
    required this.isInLiveTour,
    this.tourId,
  });

  const TouristSettingsScreen.fromTouristHome({
    Key? key,
    required VoidCallback onEditProfileTap,
  }) : this(key: key, onEditProfileTap: onEditProfileTap, isInLiveTour: false);

  // tourId is required here (not optional) since the notification
  // toggle below needs to know which tour's message topic to
  // subscribe/unsubscribe from immediately when it's flipped.
  const TouristSettingsScreen.fromLiveTour({
    Key? key,
    required VoidCallback onEditProfileTap,
    required String tourId,
  }) : this(
         key: key,
         onEditProfileTap: onEditProfileTap,
         isInLiveTour: true,
         tourId: tourId,
       );

  final VoidCallback onEditProfileTap;
  final bool isInLiveTour;
  final String? tourId;

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kDialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Session Data',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'This will remove your tourist session and account data. Are you sure?',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await TouristAccountService().deleteTouristAccount();
        if (!context.mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
          (_) => false,
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete account: $e')));
      }
    }
  }

  Future<void> _confirmLeaveTour(
    BuildContext context,
    String touristName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kDialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Leave Tour',
          style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to leave the current tour? You will be returned to the home screen.',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Leave Tour',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null || tourId == null) {
      return;
    }

    try {
      await TourRepository().leaveTour(
        tourId: tourId!,
        userUid: user.uid,
        displayName: touristName,
      );

      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const TouristHomeScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to leave tour: $e')));
    }
  }

  void _showEditProfileBottomSheet(
    BuildContext context,
    String currentName,
    String currentPhone,
    String? currentPhotoUrl,
  ) {
    final nameController = TextEditingController(text: currentName);
    final phoneController = TextEditingController(text: currentPhone);
    File? newPhotoFile;
    final touristService = TouristAccountService();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kBrandBlue,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final pickedFile = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 512,
                      imageQuality: 85,
                    );
                    if (pickedFile != null) {
                      setModalState(() {
                        newPhotoFile = File(pickedFile.path);
                      });
                    }
                  },
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: _kBrandBlue,
                        backgroundImage: newPhotoFile != null
                            ? FileImage(newPhotoFile!) as ImageProvider
                            : (currentPhotoUrl != null &&
                                      currentPhotoUrl.isNotEmpty
                                  ? NetworkImage(currentPhotoUrl)
                                        as ImageProvider
                                  : null),
                        child:
                            (newPhotoFile == null &&
                                (currentPhotoUrl == null ||
                                    currentPhotoUrl.isEmpty))
                            ? const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 44,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: _kBrandYellow,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Display Name',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _kFieldFill,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Phone Number',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _kFieldFill,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrandBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final newName = nameController.text.trim();
                    final newPhone = phoneController.text.trim();
                    if (newName.isNotEmpty) {
                      await touristService.updateTouristProfile(
                        name: newName,
                        fullPhoneNumber: newPhone,
                        photoFile: newPhotoFile,
                      );
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated successfully!'),
                      ),
                    );
                  },
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final touristService = TouristAccountService();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'Settings',
          style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<TouristProfile?>(
          stream: touristService.watchCurrentTouristProfile(),
          builder: (context, snapshot) {
            final profile = snapshot.data;
            final touristName = profile?.name ?? 'Tourist';
            final touristPhone = profile?.phoneNumber ?? '';
            final photoUrl = profile?.photoUrl;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Interactive Account Info Card
                InkWell(
                  onTap: () => _showEditProfileBottomSheet(
                    context,
                    touristName,
                    touristPhone,
                    photoUrl,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kFieldFill,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kBorderGrey),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: _kBrandBlue,
                          backgroundImage:
                              (photoUrl != null && photoUrl.isNotEmpty)
                              ? NetworkImage(photoUrl)
                              : null,
                          child: (photoUrl == null || photoUrl.isEmpty)
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 32,
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                touristName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                touristPhone.isNotEmpty
                                    ? touristPhone
                                    : 'Tourist Account',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: _kBrandBlue,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Preferences & Support',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 10),

                // Announcements always notify and can't be turned off here
                // this only controls regular chat messages.
                _MessageNotificationsTile(tourId: tourId),
                const SizedBox(height: 12),

                _SettingsTile(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  subtitle: 'FAQs and contacting TourTrack team',
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: _kDialogBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Text(
                          'Help & Support',
                          style: TextStyle(
                            color: _kBrandBlue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: const Text(
                          'Need assistance with your tour? Reach out to support@tourtrack.app',
                          style: TextStyle(color: Colors.black87),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'Close',
                              style: TextStyle(
                                color: _kBrandBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),

                if (!isInLiveTour) ...[
                  const Text(
                    'Session & Danger Zone',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),

                  _SettingsTile(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete Session Data',
                    subtitle: 'Permanently remove your profile and tour data',
                    textColor: Colors.redAccent,
                    iconColor: Colors.redAccent,
                    onTap: () => _confirmDeleteAccount(context),
                  ),
                ],

                if (isInLiveTour) ...[
                  const SizedBox(height: 28),

                  _SettingsTile(
                    icon: Icons.exit_to_app_outlined,
                    title: 'Leave Tour',
                    subtitle: 'Leave this tour and return to the home screen',
                    textColor: Colors.redAccent,
                    iconColor: Colors.redAccent,
                    onTap: () => _confirmLeaveTour(context, touristName),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// _MessageNotificationsTile — toggle for regular chat message
// notifications (announcements always notify regardless of this
// setting). Needs its own state since it loads the current value
// asynchronously from SharedPreferences on first build.
// ============================================================
class _MessageNotificationsTile extends StatefulWidget {
  final String? tourId;

  const _MessageNotificationsTile({required this.tourId});

  @override
  State<_MessageNotificationsTile> createState() =>
      _MessageNotificationsTileState();
}

class _MessageNotificationsTileState extends State<_MessageNotificationsTile> {
  final _notificationService = NotificationService();
  bool _enabled = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _notificationService.areMessageNotificationsEnabled().then((value) {
      if (!mounted) return;
      setState(() {
        _enabled = value;
        _loaded = true;
      });
    });
  }

  Future<void> _onChanged(bool value) async {
    setState(() => _enabled = value); // update UI immediately, don't wait
    await _notificationService.setMessageNotificationsEnabled(
      value,
      currentTourId: widget.tourId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _kFieldFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderGrey),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kBrandBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              color: _kBrandBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Message Notifications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Announcements always notify you',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled,
            onChanged: _loaded ? _onChanged : null,
            activeColor: _kBrandBlue,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.textColor = Colors.black87,
    this.iconColor = _kBrandBlue,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color textColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kFieldFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorderGrey),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
