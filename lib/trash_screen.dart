import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  Future<void> _openDocument(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final localPath = (data['localPath'] ?? '').toString();
    if (localPath.isEmpty || !File(localPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found on device')),
      );
      return;
    }

    final result = await OpenFilex.open(localPath);
    if (!context.mounted) return;
    if (result.type == ResultType.noAppToOpen || result.type == ResultType.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isEmpty ? 'No app found to open file' : result.message,
          ),
        ),
      );
    }
  }

  Future<void> _restoreDocument(BuildContext context, String docId) async {
    await FirebaseFirestore.instance.collection('documents').doc(docId).update({
      'isTrashed': false,
      'trashedAt': FieldValue.delete(),
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Document restored')),
    );
  }

  Future<void> _deletePermanently(BuildContext context, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Permanently'),
        content: const Text(
          'Are you sure you want to permanently delete this document?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await FirebaseFirestore.instance.collection('documents').doc(docId).delete();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Document permanently deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE8EFF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13233A),
        title: const Text('Trash'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('documents')
            .where('userId', isEqualTo: user.uid)
            .where('isTrashed', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Trash is empty'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  onTap: () => _openDocument(context, data),
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text(
                    (data['title'] ?? 'Untitled').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'File: ${(data['fileName'] ?? '').toString()}\n'
                    'Trashed: ${_formatDate(data['trashedAt'])}',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      _tinyButton(
                        label: 'Restore',
                        color: const Color(0xFF179A51),
                        onTap: () => _restoreDocument(context, doc.id),
                      ),
                      _tinyButton(
                        label: 'Delete',
                        color: const Color(0xFFDC2626),
                        onTap: () => _deletePermanently(context, doc.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static Widget _tinyButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

String _formatDate(dynamic ts) {
  if (ts == null) return '';
  final d = (ts as Timestamp).toDate();
  return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
