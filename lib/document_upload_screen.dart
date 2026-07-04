import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'utils/security_utils.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final privateKeyCtrl = TextEditingController();
  final privateKeyHintCtrl = TextEditingController();

  File? selectedFile;
  int? fileSizeKB;
  bool uploading = false;

  bool lockDocument = false;
  bool useRegisteredPrivateKey = true;

  String? userPrivateKeyHash;
  String? userPrivateKeyHint;
  bool loadingPrivateKey = true;

  String selectedCategory = "College Documents";

  final List<String> categories = [
    "College Documents",
    "Personal Documents",
    "Family Documents",
    "Certificates",
    "Bills & Finance",
    "Work / Internship",
    "Other",
  ];

  bool get hasRegisteredPrivateKey =>
      (userPrivateKeyHash ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadPrivateKeyFromProfile();
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    descCtrl.dispose();
    privateKeyCtrl.dispose();
    privateKeyHintCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrivateKeyFromProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data();
      if (!mounted || data == null) return;

      setState(() {
        userPrivateKeyHash = (data['privateKeyHash'] ?? '').toString();
        userPrivateKeyHint = (data['privateKeyHint'] ?? '').toString();
      });
    } finally {
      if (mounted) {
        setState(() => loadingPrivateKey = false);
      }
    }
  }

  Future<void> pickFile() async {
    const XTypeGroup docTypes = XTypeGroup(
      label: 'Documents',
      extensions: ['pdf', 'doc', 'docx', 'txt', 'ppt', 'pptx', 'xls', 'xlsx'],
    );

    final XFile? file = await openFile(
      acceptedTypeGroups: [docTypes],
    );

    if (file != null) {
      final f = File(file.path);
      final sizeKB = (await f.length() / 1024).round();

      setState(() {
        selectedFile = f;
        fileSizeKB = sizeKB;
      });
    }
  }

  Future<Directory> _getLocalDocsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final docsDir = Directory('${dir.path}/documents');

    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }

    return docsDir;
  }

  Future<void> uploadDocument() async {
    if (titleCtrl.text.trim().isEmpty || selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Title and document required")),
      );
      return;
    }

    String? finalPrivateKeyHash;
    String? finalPrivateKeyHint;

    if (lockDocument) {
      if (useRegisteredPrivateKey && hasRegisteredPrivateKey) {
        finalPrivateKeyHash = userPrivateKeyHash;
        if ((userPrivateKeyHint ?? '').trim().isNotEmpty) {
          finalPrivateKeyHint = userPrivateKeyHint!.trim();
        }
      } else {
        final customKey = privateKeyCtrl.text.trim();
        if (customKey.length < 4) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Enter a private key of at least 4 characters"),
            ),
          );
          return;
        }
        finalPrivateKeyHash = hashPrivateKey(customKey);

        if (privateKeyHintCtrl.text.trim().isNotEmpty) {
          finalPrivateKeyHint = privateKeyHintCtrl.text.trim();
        }
      }
    }

    try {
      setState(() => uploading = true);

      final user = FirebaseAuth.instance.currentUser!;
      final docsDir = await _getLocalDocsDir();

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(selectedFile!.path)}';

      final savedFile = await selectedFile!.copy('${docsDir.path}/$fileName');

      await FirebaseFirestore.instance.collection("documents").add({
        "title": titleCtrl.text.trim(),
        "description": descCtrl.text.trim(),
        "localPath": savedFile.path,
        "fileName": fileName,
        "fileSizeKB": fileSizeKB,
        "category": selectedCategory,
        "userId": user.uid,
        "isLocked": lockDocument,
        if (finalPrivateKeyHash case final keyHash) "privateKeyHash": keyHash,
        if ((finalPrivateKeyHint ?? '').isNotEmpty)
          "privateKeyHint": finalPrivateKeyHint,
        "createdAt": Timestamp.now(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lockDocument
                ? "Document uploaded and locked successfully"
                : "Document uploaded successfully",
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Upload failed: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xfff5f6f8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2D3D),
        title: const Text("Upload Document"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 15),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1F2D3D), Color(0xFF36577A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Upload New Document",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Organize and protect sensitive files with a private key",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: "Document Title",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: "Select Folder",
                    prefixIcon: Icon(Icons.folder),
                    border: OutlineInputBorder(),
                  ),
                  items: categories.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(cat),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCategory = value!;
                    });
                  },
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    selectedFile == null
                        ? "Choose Document"
                        : "${path.basename(selectedFile!.path)}${fileSizeKB != null ? ' - $fileSizeKB KB' : ''}",
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: uploading ? null : pickFile,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6FAFF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD8E5F8)),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          "Lock this document",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          "Only private key holders can open this file",
                          style: TextStyle(fontSize: 12),
                        ),
                        value: lockDocument,
                        onChanged: uploading
                            ? null
                            : (v) {
                                setState(() {
                                  lockDocument = v;
                                  if (!hasRegisteredPrivateKey) {
                                    useRegisteredPrivateKey = false;
                                  }
                                });
                              },
                      ),
                      if (lockDocument) ...[
                        const SizedBox(height: 8),
                        if (loadingPrivateKey)
                          const LinearProgressIndicator(minHeight: 2),
                        if (!loadingPrivateKey && hasRegisteredPrivateKey) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label:
                                      const Text("Use registered private key"),
                                  selected: useRegisteredPrivateKey,
                                  onSelected: uploading
                                      ? null
                                      : (_) {
                                          setState(() {
                                            useRegisteredPrivateKey = true;
                                          });
                                        },
                                ),
                                ChoiceChip(
                                  label: const Text(
                                    "Use custom private key for this file",
                                  ),
                                  selected: !useRegisteredPrivateKey,
                                  onSelected: uploading
                                      ? null
                                      : (_) {
                                          setState(() {
                                            useRegisteredPrivateKey = false;
                                          });
                                        },
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (!loadingPrivateKey && !hasRegisteredPrivateKey)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "No registered private key found. Add custom key below.",
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ),
                        if (!useRegisteredPrivateKey || !hasRegisteredPrivateKey) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: privateKeyCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: "Enter Private Key",
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: privateKeyHintCtrl,
                            decoration: const InputDecoration(
                              labelText: "Key Hint (Optional)",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: width,
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.cloud_upload_outlined),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2D3D),
                    ),
                    onPressed: uploading ? null : uploadDocument,
                    label: uploading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text("Upload"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

