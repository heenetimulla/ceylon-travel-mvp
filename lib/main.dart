import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/services/fcm_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/ceylon_travel_app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (FcmService.supported) {
    FirebaseMessaging.onBackgroundMessage(tripChatMessagingBackground);
  }
  runApp(const CeylonTravelApp(notifications: true));
  unawaited(FcmService.instance.initialize());
}
