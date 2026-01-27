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

class BBPApp extends StatefulWidget {
  const BBPApp({super.key});

  @override
  State<BBPApp> createState() => _BBPAppState();
}

class _BBPAppState extends State<BBPApp> {
  late final Stream<AuthState> _authStateStream;

  @override
  void initState() {
    super.initState();
    _authStateStream = Supabase.instance.client.auth.onAuthStateChange;
  }

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
      home: StreamBuilder<AuthState>(
        stream: _authStateStream,
        builder: (context, snapshot) {
          // Check current auth state
          final session = Supabase.instance.client.auth.currentSession;
          if (session != null) {
            return const DashboardScreen();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}
