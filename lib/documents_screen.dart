import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'folder_documents_screen.dart';
import 'trash_screen.dart';

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  static const List<String> _fixedFolders = [
    "Personal Documents",
    "Business Documents",
    "Marksheets",
    "Family Documents",
    "Other",
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE8EFF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13233A),
        title: const Row(
          children: [
            Icon(Icons.folder, size: 20, color: Color(0xFFFFCC66)),
            SizedBox(width: 10),
            Text("My Documents"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrashScreen()),
              );
            },
            child: const Text(
              "Trash",
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            child: const Text(
              "Back",
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("documents")
            .where("userId", isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          final folderCount = <String, int>{
            for (final folder in _fixedFolders) folder: 0,
          };

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['isTrashed'] == true) {
              continue;
            }
            final normalized = _normalizeCategory(
              (data["category"] ?? "").toString(),
            );
            folderCount[normalized] = (folderCount[normalized] ?? 0) + 1;
          }

          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F7FC),
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
                      children: [
                        const Text(
                          "My Document Folders",
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF121D34),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: _fixedFolders.map((folderName) {
                            return _folderCard(
                              title: folderName,
                              count: folderCount[folderName] ?? 0,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FolderDocumentsScreen(
                                      category: folderName,
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _folderCard({
    required String title,
    required int count,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 220,
        height: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD3E0F2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.folder_copy_outlined, color: Color(0xFF1D4F8E)),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFF121D34),
              ),
            ),
            Text(
              "$count documents",
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4B5A73),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _normalizeCategory(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.contains("family")) return "Family Documents";
  if (value.contains("personal")) return "Personal Documents";
  if (value.contains("business") ||
      value.contains("bill") ||
      value.contains("finance") ||
      value.contains("work") ||
      value.contains("intern")) {
    return "Business Documents";
  }
  if (value.contains("marksheet") ||
      value.contains("college") ||
      value.contains("certificate")) {
    return "Marksheets";
  }
  return "Other";
}
