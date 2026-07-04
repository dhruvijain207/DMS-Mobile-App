import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'document_upload_screen.dart';
import 'documents_screen.dart';
import 'login_screen.dart';
import 'private_key_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String email;

  const DashboardScreen({
    super.key,
    required this.email,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool loadingSecurityInfo = true;
  bool hasPrivateKey = false;
  String privateKeyHint = "";

  @override
  void initState() {
    super.initState();
    _loadSecurityInfo();
  }

  Future<void> _loadSecurityInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();
      final data = userDoc.data() ?? {};
      final savedHash = (data["privateKeyHash"] ?? "").toString().trim();

      if (!mounted) return;
      setState(() {
        hasPrivateKey = data["hasPrivateKey"] == true && savedHash.isNotEmpty;
        privateKeyHint = (data["privateKeyHint"] ?? "").toString();
      });
    } finally {
      if (mounted) {
        setState(() => loadingSecurityInfo = false);
      }
    }
  }

  Future<void> _openPrivateKeyScreen() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateKeyScreen(
          hasPrivateKey: hasPrivateKey,
          initialHint: privateKeyHint,
          fallbackEmail: widget.email,
        ),
      ),
    );

    if (updated == true && mounted) {
      await _loadSecurityInfo();
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    var displayName = widget.email.split('@')[0];
    displayName = displayName[0].toUpperCase() + displayName.substring(1);

    return Scaffold(
      backgroundColor: const Color(0xFFE8EFF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13233A),
        titleSpacing: 18,
        title: const Row(
          children: [
            Icon(Icons.folder, size: 20, color: Color(0xFFFFCC66)),
            SizedBox(width: 10),
            Text(
              "Document Management System",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          _headerButton(
            label: "Profile",
            color: const Color(0xFF0B8DD9),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          _headerButton(
            label: hasPrivateKey ? "Update Key" : "Private Key",
            color: const Color(0xFF415A9C),
            onTap: _openPrivateKeyScreen,
          ),
          _headerButton(
            label: "Logout",
            color: const Color(0xFFFF7A1A),
            onTap: _logout,
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F7FC),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4E6F8),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        "SECURE WORKSPACE",
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C5A93),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "Welcome, $displayName",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111C33),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Manage, upload, and access documents with confidence.",
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF35435B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (loadingSecurityInfo)
                      const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _featureCard(
                          width: screenWidth > 900 ? 340 : screenWidth * 0.85,
                          icon: Icons.cloud_upload_outlined,
                          iconBg: const Color(0xFF0B8DD9),
                          title: "Upload Documents",
                          subtitle: "Add your files to secure folders",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const UploadScreen(),
                              ),
                            );
                          },
                        ),
                        _featureCard(
                          width: screenWidth > 900 ? 340 : screenWidth * 0.85,
                          icon: Icons.description_outlined,
                          iconBg: const Color(0xFFFF7A1A),
                          title: "View Documents",
                          subtitle: "Browse and manage all saved files",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DocumentsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
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

  static Widget _headerButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  static Widget _featureCard({
    required double width,
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: width,
        constraints: const BoxConstraints(minHeight: 140),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD3E0F2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: iconBg,
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: Color(0xFF121D34),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF47526A),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
