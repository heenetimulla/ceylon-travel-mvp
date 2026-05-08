import 'package:flutter/material.dart';

import '../screens/splash_screen.dart';
import 'app_theme.dart';

class CeylonTravelApp extends StatelessWidget {
  const CeylonTravelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ceylon Travel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
