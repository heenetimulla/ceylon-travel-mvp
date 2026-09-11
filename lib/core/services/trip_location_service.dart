import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/trip_chat_message.dart';

class TripCoordinates {
  const TripCoordinates(this.latitude, this.longitude);
  final double latitude, longitude;
  Uri get mapsUri {
    TripChatMessage.validateLocation(latitude, longitude);
    return Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$latitude,$longitude'});
  }
}
class TripLocationException implements Exception {
  const TripLocationException(this.message);
  final String message;
  @override
  String toString() => message;
}
class TripLocationService {
  TripLocationService({Future<bool> Function()? servicesEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<TripCoordinates> Function()? locate, Future<bool> Function(Uri)? launch})
    : _servicesEnabled = servicesEnabled ?? Geolocator.isLocationServiceEnabled,
      _checkPermission = checkPermission ?? Geolocator.checkPermission,
      _requestPermission = requestPermission ?? Geolocator.requestPermission,
      _locate = locate ?? _currentPosition,
      _launch = launch ?? ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));
  final Future<bool> Function() _servicesEnabled;
  final Future<LocationPermission> Function() _checkPermission, _requestPermission;
  final Future<TripCoordinates> Function() _locate;
  final Future<bool> Function(Uri) _launch;
  bool _permissionRequested = false;
  static Future<TripCoordinates> _currentPosition() async {
    final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)));
    return TripCoordinates(position.latitude, position.longitude);
  }
  Future<TripCoordinates> currentCoordinates() async {
    if (!kIsWeb && [TargetPlatform.macOS, TargetPlatform.linux, TargetPlatform.fuchsia].contains(defaultTargetPlatform)) {
      throw const TripLocationException('Location sharing is not available on this platform.');
    }
    try {
      if (!await _servicesEnabled().timeout(const Duration(seconds: 10))) {
        throw const TripLocationException('Location services are disabled. Turn them on and try again.');
      }
      var permission = await _checkPermission().timeout(const Duration(seconds: 10));
      if (permission == LocationPermission.denied && !_permissionRequested) {
        _permissionRequested = true;
        permission = await _requestPermission().timeout(const Duration(seconds: 30));
      }
      if (permission == LocationPermission.deniedForever) {
        throw const TripLocationException('Location permission is blocked. Enable it in your device or browser settings.');
      }
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        throw const TripLocationException('Location permission was denied. Allow it in settings to share your location.');
      }
      final coordinates = await _locate().timeout(const Duration(seconds: 30));
      TripChatMessage.validateLocation(coordinates.latitude, coordinates.longitude);
      return coordinates;
    } on TripLocationException { rethrow;
    } on TimeoutException {
      throw const TripLocationException('Location lookup timed out. Please try again.');
    } on LocationServiceDisabledException {
      throw const TripLocationException('Location services are disabled. Turn them on and try again.');
    } on PermissionDeniedException {
      throw const TripLocationException('Location permission was denied. Check your device or browser settings.');
    } catch (_) {
      throw const TripLocationException('Could not get your location. Check location settings and try again.');
    }
  }
  Future<void> openMaps(TripCoordinates coordinates) async {
    try {
      // Launch immediately from the user gesture; no canLaunch preflight on web.
      if (!await _launch(coordinates.mapsUri)) throw StateError('No map handler.');
    } catch (_) {
      throw const TripLocationException('Could not open Maps. Check your browser or installed map app.');
    }
  }
}
