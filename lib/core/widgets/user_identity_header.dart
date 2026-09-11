import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'profile_avatar.dart';

class UserIdentityHeader extends StatefulWidget {
  const UserIdentityHeader({super.key, this.loadProfile});

  final Future<Map<String, dynamic>?> Function()? loadProfile;

  @override
  State<UserIdentityHeader> createState() => _UserIdentityHeaderState();
}

class _UserIdentityHeaderState extends State<UserIdentityHeader> {
  late final Future<Map<String, dynamic>?> _profile;

  @override
  void initState() {
    super.initState();
    _profile = Future<Map<String, dynamic>?>.sync(
      widget.loadProfile ?? _loadCurrentProfile,
    );
  }

  Future<Map<String, dynamic>?> _loadCurrentProfile() async {
    final authService = AuthService();
    final user = authService.currentUser;
    if (user == null) return null;

    final document = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get()
        .timeout(const Duration(seconds: 15));
    if (authService.currentUser?.uid != user.uid) return null;
    return document.data();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profile,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState != ConnectionState.done;
        final value = snapshot.hasError ? null : snapshot.data?['fullName'];
        final fullName = value is String ? value.trim() : '';

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
          children: [
            if (isLoading) CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.softBlue,
              foregroundColor: AppColors.ocean,
              child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Loading profile',
                      ),
                    ),
            ) else ProfileAvatar(fullName: fullName,
              profilePhotoPath: snapshot.data?['profilePhotoPath'] is String ? snapshot.data!['profilePhotoPath'] as String : null),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CEYLON TRAVEL', style: AppTextStyles.caption),
                  const SizedBox(height: 4),
                  Text(
                    isLoading
                        ? 'Loading profile...'
                        : fullName.isEmpty
                        ? 'User'
                        : fullName,
                    style: AppTextStyles.section,
                  ),
                ],
              ),
            ),
          ],
          ),
        );
      },
    );
  }
}
