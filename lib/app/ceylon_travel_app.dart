import 'package:flutter/material.dart';

import '../screens/splash_screen.dart';
import 'app_theme.dart';
import '../core/widgets/fcm_navigation_host.dart';

class CeylonTravelApp extends StatelessWidget {
  const CeylonTravelApp({super.key, this.resolveSession, this.notifications = false});

  final Future<Widget> Function()? resolveSession;
  final bool notifications;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ceylon Travel',
      navigatorKey: notifications ? notificationNavigatorKey : null,
      builder: notifications ? (_, child) => FcmNavigationHost(child: child ?? const SizedBox.shrink()) : null,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: SplashScreen(resolveSession: resolveSession),
    );
  }
}
