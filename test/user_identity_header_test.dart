import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/widgets/user_identity_header.dart';

void main() {
  testWidgets('Identity shows local loading then full name and initials', (
    tester,
  ) async {
    final profile = Completer<Map<String, dynamic>?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserIdentityHeader(loadProfile: () => profile.future),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading profile...'), findsOneWidget);

    profile.complete({'fullName': 'Test Driver', 'profilePhotoPath': null});
    await tester.pumpAndSettle();

    expect(find.text('Test Driver'), findsOneWidget);
    expect(find.text('TD'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final entry in {'John Silva': 'JS', '  John  ': 'J'}.entries) {
    testWidgets('Identity generates initials for ${entry.key}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserIdentityHeader(
              loadProfile: () async => {
                'fullName': entry.key,
                'profilePhotoPath': 'unresolved/profile/photo',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(entry.key.trim()), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
        isNull,
      );
      expect(find.byType(Image), findsNothing);
    });
  }

  testWidgets('Missing or malformed names use a generic identity', (
    tester,
  ) async {
    for (final profile in <Map<String, dynamic>?>[
      null,
      {},
      {'fullName': '   '},
      {'fullName': 42},
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserIdentityHeader(
              key: UniqueKey(),
              loadProfile: () async => profile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('User'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    }
  });

  testWidgets('Profile errors show no technical details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserIdentityHeader(
            loadProfile: () async =>
                throw Exception('technical Firebase error'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('User'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.textContaining('technical Firebase error'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
