import 'package:flutter/material.dart';

import '../screens/splash_screen.dart';
import 'app_theme.dart';

class CeylonTravelApp extends StatelessWidget {
  const CeylonTravelApp({super.key, this.resolveSession});

  final Future<Widget> Function()? resolveSession;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ceylon Travel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: SplashScreen(resolveSession: resolveSession),
    );
  }
}
