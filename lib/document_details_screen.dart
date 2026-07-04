import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DocumentDetailScreen extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;

  const DocumentDetailScreen({
    super.key,
    required this.docId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(data['title'] ?? "Document"),
        backgroundColor: const Color(0xFF1F2D3D),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              data['title'] ?? "",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            Text(
              data['description'] ?? "No description",
              style: const TextStyle(fontSize: 16),
            ),

            const Divider(height: 30),

            Text(
              "File: ${data['fileName'] ?? ""}",
              style: const TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 20),

            
          ],
        ),
      ),
    );
  }
}
