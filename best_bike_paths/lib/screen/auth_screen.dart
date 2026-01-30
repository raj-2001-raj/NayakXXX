import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Toggle between Login and Sign Up
  bool _isLogin = true;
  bool _isLoading = false;

  // Controllers for text fields
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();

  // To store the actual date object
  DateTime? _selectedDate;

  // --- LOGIC: DATE PICKER ---
  Future<void> _pickDate() async {
    // Use a better initial date and allow easy year/month selection
    final initialDate =
        _selectedDate ??
        DateTime.now().subtract(
          const Duration(days: 365 * 20),
        ); // Default to 20 years ago

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year, // Start with year selection
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00FF00), // Neon Green headers
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: const Color(0xFF1E1E1E),
              headerBackgroundColor: const Color(0xFF00FF00),
              headerForegroundColor: Colors.black,
              yearStyle: const TextStyle(fontSize: 16),
              dayStyle: const TextStyle(fontSize: 14),
              // Make year/month selection more prominent
              yearOverlayColor: WidgetStateProperty.all(
                const Color(0xFF00FF00).withOpacity(0.2),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dobController.text =
            "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  // --- LOGIC: AUTHENTICATION ---
  Future<void> _authenticate() async {
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();
    final name = _nameController.text.trim();

    try {
      if (_isLogin) {
        // --- LOGIN FLOW ---
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } else {
        // --- SIGN UP FLOW ---
        // 1. Validation
        if (password != confirmPass) {
          throw const AuthException("Passwords do not match!");
        }
        if (name.isEmpty || _selectedDate == null) {
          throw const AuthException("Please fill in Name and DOB.");
        }

        // 2. Create Account with Extra Data (Name, DOB)
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': name, 'dob': _selectedDate!.toIso8601String()},
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Account created! Logging you in...")),
          );
        }
      }

      // Success -> Go to Dashboard
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        String errorMessage = e.message;

        // Handle email rate limit error with user-friendly message
        if (e.message.toLowerCase().contains('rate') ||
            e.message.toLowerCase().contains('limit') ||
            e.message.toLowerCase().contains('exceeded') ||
            e.statusCode == '429') {
          errorMessage =
              "Too many sign-up attempts. Please try again in a few minutes, or continue as guest for now.";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();

        // Handle rate limit errors from generic exceptions too
        if (errorMessage.toLowerCase().contains('rate') ||
            errorMessage.toLowerCase().contains('limit')) {
          errorMessage =
              "Too many sign-up attempts. Please try again in a few minutes, or continue as guest for now.";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LOGIC: GUEST MODE ---
  void _continueAsGuest() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  // --- LOGIC: PASSWORD RESET ---
  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your email address first"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Password reset link sent! Check your email."),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.directions_bike,
                size: 80,
                color: Color(0xFF00FF00),
              ),
              const SizedBox(height: 20),
              Text(
                _isLogin ? "Welcome Back" : "Create Account",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 40),

              // --- FORM FIELDS ---
              if (!_isLogin) ...[
                _buildTextField(_nameController, "Full Name", Icons.person),
                const SizedBox(height: 16),

                TextField(
                  controller: _dobController,
                  readOnly: true,
                  style: const TextStyle(color: Colors.white),
                  onTap: _pickDate,
                  decoration: InputDecoration(
                    labelText: "Date of Birth",
                    prefixIcon: const Icon(
                      Icons.calendar_today,
                      color: Colors.grey,
                    ),
                    labelStyle: const TextStyle(color: Colors.grey),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF00FF00)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              _buildTextField(_emailController, "Email Address", Icons.email),
              const SizedBox(height: 16),
              _buildTextField(
                _passwordController,
                "Password",
                Icons.lock,
                isPassword: true,
              ),

              // Forgot Password link (only visible on login)
              if (_isLogin) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(color: Color(0xFF00FF00), fontSize: 14),
                    ),
                  ),
                ),
              ],

              if (!_isLogin) ...[
                const SizedBox(height: 16),
                _buildTextField(
                  _confirmPasswordController,
                  "Confirm Password",
                  Icons.lock_outline,
                  isPassword: true,
                ),
              ],

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isLoading ? null : _authenticate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF00),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(
                        _isLogin ? "LOG IN" : "SIGN UP",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),

              const SizedBox(height: 16),

              if (_isLogin)
                OutlinedButton(
                  onPressed: _continueAsGuest,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.grey),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text("CONTINUE AS GUEST"),
                ),

              const SizedBox(height: 20),

              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _emailController.clear();
                    _passwordController.clear();
                    _confirmPasswordController.clear();
                    _nameController.clear();
                    _dobController.clear();
                  });
                },
                child: Text(
                  _isLogin
                      ? "New here? Create an Account"
                      : "Have an account? Log In",
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        labelStyle: const TextStyle(color: Colors.grey),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF00FF00)),
        ),
      ),
    );
  }
}
