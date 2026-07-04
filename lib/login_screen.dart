import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_dashboard.dart';
import 'dashboard_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool loggingIn = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<String> _resolveEmailForLogin(String input) async {
    final value = input.trim();
    if (value.contains('@')) {
      return value.toLowerCase();
    }

    final lowerValue = value.toLowerCase();

    final userByUsername = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: value)
        .limit(1)
        .get();

    if (userByUsername.docs.isNotEmpty) {
      final email =
          (userByUsername.docs.first.data()['email'] ?? '').toString().trim();
      if (email.isNotEmpty) {
        return email.toLowerCase();
      }
    }

    final userByLowerUsername = await FirebaseFirestore.instance
        .collection('users')
        .where('usernameLower', isEqualTo: lowerValue)
        .limit(1)
        .get();

    if (userByLowerUsername.docs.isNotEmpty) {
      final email =
          (userByLowerUsername.docs.first.data()['email'] ?? '')
              .toString()
              .trim();
      if (email.isNotEmpty) {
        return email.toLowerCase();
      }
    }

    final allUsers = await FirebaseFirestore.instance.collection('users').get();
    for (final doc in allUsers.docs) {
      final data = doc.data();
      final username = (data['username'] ?? '').toString().trim().toLowerCase();
      final email = (data['email'] ?? '').toString().trim();
      if (username == lowerValue && email.isNotEmpty) {
        return email.toLowerCase();
      }
    }

    throw FirebaseAuthException(code: 'user-not-found');
  }

  Future<void> _login() async {
    final loginInput = emailController.text.trim();
    final passwordInput = passwordController.text.trim();

    if (loginInput.isEmpty || passwordInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter username/email and password'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      setState(() => loggingIn = true);

      final emailForLogin = await _resolveEmailForLogin(loginInput);

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailForLogin,
        password: passwordInput,
      );

      final user = credential.user!;
      final uid = user.uid;

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final role = userDoc.data()?['role'] ?? 'user';

      if (!mounted) return;

      if (role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DashboardScreen(email: user.email ?? emailForLogin),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'This account does not exist. Please register first.';
          break;
        case 'wrong-password':
          message = 'Incorrect password. Please try again.';
          break;
        case 'invalid-credential':
          message = 'Incorrect username/email or password.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email or username.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        default:
          message = 'Login failed. Please try again.';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Try again later.'),
          backgroundColor: Color(0xFF5F3DC4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => loggingIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFE6EBF5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: screenWidth > 420 ? 380 : screenWidth * 0.95,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 15,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Login',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email or Username',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F2D3D),
                      ),
                      onPressed: loggingIn ? null : _login,
                      child: loggingIn
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RegisterScreen()),
                      );
                    },
                    child: const Text(
                      'Do not have an account? Register',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
