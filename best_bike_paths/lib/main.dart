import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'screen/auth_screen.dart';
import 'screen/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConstants.url,
    anonKey: SupabaseConstants.anonKey,
  );

  runApp(const BBPApp());
}

class BBPApp extends StatelessWidget {
  const BBPApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Best Bike Paths',
      theme: ThemeData(
        useMaterial3: true,
        
        primaryColor: const Color(0xFF00FF00),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: Supabase.instance.client.auth.currentUser == null
          ? const AuthScreen()
          : const DashboardScreen(),
    );
  }
}
