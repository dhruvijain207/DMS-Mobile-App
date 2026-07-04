import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'utils/security_utils.dart';

class PrivateKeyScreen extends StatefulWidget {
  final bool hasPrivateKey;
  final String initialHint;
  final String fallbackEmail;

  const PrivateKeyScreen({
    super.key,
    required this.hasPrivateKey,
    required this.initialHint,
    required this.fallbackEmail,
  });

  @override
  State<PrivateKeyScreen> createState() => _PrivateKeyScreenState();
}

class _PrivateKeyScreenState extends State<PrivateKeyScreen> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _hintCtrl;
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _obscureKey = true;
  bool _obscurePassword = true;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController();
    _hintCtrl = TextEditingController(text: widget.initialHint);
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _hintCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final key = _keyCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (key.length < 4) {
      setState(() {
        _errorText = 'Private key must be at least 4 characters.';
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _errorText = 'Enter your login password to continue.';
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _errorText = 'User session expired. Please login again.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email ?? widget.fallbackEmail,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'hasPrivateKey': true,
        'privateKeyHash': hashPrivateKey(key),
        'privateKeyHint': _hintCtrl.text.trim(),
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.hasPrivateKey
                ? 'Private key updated successfully'
                : 'Private key saved successfully',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = 'Login password is incorrect.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = 'Private key update failed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EFF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13233A),
        foregroundColor: Colors.white,
        title: Text(widget.hasPrivateKey ? 'Update Private Key' : 'Set Private Key'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.hasPrivateKey
                          ? 'Enter a new private key and verify with your login password.'
                          : 'Set a private key for locked documents and verify with your login password.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF44526A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _keyCtrl,
                      enabled: !_saving,
                      obscureText: _obscureKey,
                      decoration: InputDecoration(
                        labelText: 'Private Key',
                        errorText: _errorText,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscureKey = !_obscureKey;
                            });
                          },
                          icon: Icon(
                            _obscureKey ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _hintCtrl,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Key Hint (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      enabled: !_saving,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Login Password',
                        helperText: 'Account verification is required before saving.',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F2946),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _saving ? null : _saveKey,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save Key'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
