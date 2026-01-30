// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:best_bike_paths/core/constants.dart';
import 'package:best_bike_paths/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: SupabaseConstants.url,
      anonKey: SupabaseConstants.anonKey,
    );
  });

  testWidgets('shows auth screen on launch when no user is logged in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BBPApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget);
  });
}
