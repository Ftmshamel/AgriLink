import 'package:agrilink_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the AgriLink welcome screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: AuthWelcomePage()),
    );

    expect(find.text('Fresh harvests.\nSmarter deliveries.'), findsOneWidget);
    expect(find.text('Log in to AgriLink'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });
}
