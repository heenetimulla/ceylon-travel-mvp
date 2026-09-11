import 'package:flutter/material.dart';
import '../../app/app_colors.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.fullName, this.profilePhotoPath});
  final String fullName;
  final String? profilePhotoPath;
  @override
  Widget build(BuildContext context) {
    final names = fullName.trim().split(RegExp(r'\s+')).where((name) => name.isNotEmpty).toList();
    final initials = names.isEmpty ? '' : '${names.first.characters.first}${names.length > 1 ? names.last.characters.first : ''}'.toUpperCase();
    final fallback = initials.isEmpty ? const Icon(Icons.person_outline) : Text(initials);
    final uri = Uri.tryParse(profilePhotoPath ?? '');
    // Already-resolved public HTTPS photos only. Storage paths retain the fallback.
    final photo = uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? uri.toString() : null;
    return CircleAvatar(radius: 26, backgroundColor: AppColors.softBlue, foregroundColor: AppColors.ocean,
      child: photo == null ? fallback : ClipOval(child: Image.network(photo, width: 52, height: 52,
        fit: BoxFit.cover, errorBuilder: (_, error, stack) => fallback)));
  }
}
