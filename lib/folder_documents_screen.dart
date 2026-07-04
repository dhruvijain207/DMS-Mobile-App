import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'utils/security_utils.dart';

class FolderDocumentsScreen extends StatefulWidget {
  final String category;

  const FolderDocumentsScreen({super.key, required this.category});

  @override
  State<FolderDocumentsScreen> createState() => _FolderDocumentsScreenState();
}

class _FolderDocumentsScreenState extends State<FolderDocumentsScreen> {
  String searchQuery = "";

  Future<File?> _pickReplacementFile() async {
    const XTypeGroup docTypes = XTypeGroup(
      label: 'Documents',
      extensions: ['pdf', 'doc', 'docx', 'txt', 'ppt', 'pptx', 'xls', 'xlsx'],
    );

    final XFile? file = await openFile(
      acceptedTypeGroups: [docTypes],
    );

    if (file == null) {
      return null;
    }

    return File(file.path);
  }

  Future<Directory> _getLocalDocsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final docsDir = Directory('${dir.path}/documents');

    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }

    return docsDir;
  }

  void _handleBack() {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openDocument(Map<String, dynamic> data) async {
    final localPath = (data['localPath'] ?? '').toString();
    if (localPath.isEmpty || !File(localPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("File not found on device")),
      );
      return;
    }

    final isLocked = data['isLocked'] == true;
    if (isLocked) {
      final unlocked = await _verifyPrivateKey(
        data,
        actionLabel: "Unlock",
        operationName: "open",
      );
      if (!unlocked) return;
    }

    final result = await OpenFilex.open(localPath);
    if (!mounted) return;
    if (result.type == ResultType.noAppToOpen ||
        result.type == ResultType.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Document open nahi hua: ${result.message.isEmpty ? 'No app found' : result.message}",
          ),
        ),
      );
    }
  }

  Future<void> _openEditDocument(String docId, Map<String, dynamic> data) async {
    final isLocked = data['isLocked'] == true;
    if (isLocked) {
      final unlocked = await _verifyPrivateKey(
        data,
        actionLabel: "Unlock for Edit",
        operationName: "edit",
      );
      if (!unlocked) return;
    }

    if (!mounted) return;
    _showEditDialog(context, docId, data);
  }

  Future<bool> _verifyPrivateKey(
    Map<String, dynamic> data, {
    required String actionLabel,
    required String operationName,
  }) async {
    final expectedHash = (data['privateKeyHash'] ?? '').toString();
    if (expectedHash.isEmpty) {
      return true;
    }

    final keyCtrl = TextEditingController();
    String? error;
    final hint = (data['privateKeyHint'] ?? '').toString();

    final unlocked = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: const Row(
                    children: [
                      Icon(Icons.lock_outline),
                      SizedBox(width: 8),
                      Text("Private Document"),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Enter private key to $operationName '${data['title'] ?? 'document'}'",
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (hint.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          "Hint: $hint",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: keyCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: "Private Key",
                          errorText: error,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) {
                          final entered = keyCtrl.text.trim();
                          if (entered.isEmpty) {
                            setDialogState(
                              () => error = "Please enter private key",
                            );
                            return;
                          }

                          if (hashPrivateKey(entered) != expectedHash) {
                            setDialogState(
                              () => error = "Incorrect private key",
                            );
                            return;
                          }

                          Navigator.pop(dialogContext, true);
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text("Cancel"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F2946),
                      ),
                      onPressed: () {
                        final entered = keyCtrl.text.trim();
                        if (entered.isEmpty) {
                          setDialogState(
                            () => error = "Please enter private key",
                          );
                          return;
                        }

                        if (hashPrivateKey(entered) != expectedHash) {
                          setDialogState(
                            () => error = "Incorrect private key",
                          );
                          return;
                        }

                        Navigator.pop(dialogContext, true);
                      },
                      child: Text(actionLabel),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    keyCtrl.dispose();
    return unlocked;
  }

  void _showEditDialog(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) {
    final titleCtrl = TextEditingController(text: data['title'] ?? "");
    final descCtrl = TextEditingController(text: data['description'] ?? "");
    final privateKeyCtrl = TextEditingController();
    final keyHintCtrl = TextEditingController(
      text: (data['privateKeyHint'] ?? "").toString(),
    );

    var isLocked = data['isLocked'] == true;
    var obscuredPrivateKey = true;
    File? replacementFile;
    int? replacementFileSizeKB;
    String? errorText;
    final existingPrivateHash = (data['privateKeyHash'] ?? "").toString();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Edit Document"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: "Title",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Description",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Replace File",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final pickedFile = await _pickReplacementFile();
                        if (pickedFile == null) return;
                        final sizeKB = (await pickedFile.length() / 1024).round();
                        setDialogState(() {
                          replacementFile = pickedFile;
                          replacementFileSizeKB = sizeKB;
                        });
                      },
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(
                        replacementFile == null ? "Choose New File" : "Change File",
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      replacementFile == null
                          ? "Current file: ${(data['fileName'] ?? 'No file').toString()}"
                          : "Selected: ${path.basename(replacementFile!.path)}${replacementFileSizeKB != null ? ' - $replacementFileSizeKB KB' : ''}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF52627A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Lock this document"),
                      subtitle: const Text(
                        "Keep this on to protect the document",
                      ),
                      value: isLocked,
                      onChanged: (value) {
                        setDialogState(() {
                          isLocked = value;
                        });
                      },
                    ),
                    if (isLocked) ...[
                      const SizedBox(height: 6),
                      TextField(
                        controller: privateKeyCtrl,
                        obscureText: obscuredPrivateKey,
                        decoration: InputDecoration(
                          labelText: existingPrivateHash.isEmpty
                              ? "Set Private Key"
                              : "Enter Private Key",
                          border: const OutlineInputBorder(),
                          errorText: errorText,
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscuredPrivateKey
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                obscuredPrivateKey = !obscuredPrivateKey;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyHintCtrl,
                        decoration: const InputDecoration(
                          labelText: "Key Hint (Optional)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      "Created: ${_formatDate(data['createdAt'])}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final confirm = await _confirmDelete(context);
                    if (confirm != true) return;
                    await FirebaseFirestore.instance
                        .collection("documents")
                        .doc(docId)
                        .update({
                      'isTrashed': true,
                      'trashedAt': Timestamp.now(),
                    });
                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Document moved to trash")),
                      );
                    }
                  },
                  child: const Text(
                    "Move To Trash",
                    style: TextStyle(color: Color(0xFFDC2626)),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F2946),
                  ),
                  onPressed: () async {
                    final updateData = <String, dynamic>{
                      "title": titleCtrl.text.trim(),
                      "description": descCtrl.text.trim(),
                      "isLocked": isLocked,
                      "updatedAt": Timestamp.now(),
                    };

                    if (isLocked) {
                      final enteredKey = privateKeyCtrl.text.trim();

                      if (existingPrivateHash.isNotEmpty) {
                        if (enteredKey.isEmpty) {
                          setDialogState(() {
                            errorText =
                                "Save karne ke liye private key enter karo";
                          });
                          return;
                        }
                        if (hashPrivateKey(enteredKey) != existingPrivateHash) {
                          setDialogState(() {
                            errorText = "Incorrect private key";
                          });
                          return;
                        }
                        updateData["privateKeyHash"] = existingPrivateHash;
                      } else {
                        if (enteredKey.length < 4) {
                          setDialogState(() {
                            errorText = "Private key must be at least 4 characters";
                          });
                          return;
                        }
                        updateData["privateKeyHash"] = hashPrivateKey(enteredKey);
                      }

                      final hint = keyHintCtrl.text.trim();
                      if (hint.isNotEmpty) {
                        updateData["privateKeyHint"] = hint;
                      } else {
                        updateData["privateKeyHint"] = FieldValue.delete();
                      }
                    } else {
                      updateData["privateKeyHash"] = FieldValue.delete();
                      updateData["privateKeyHint"] = FieldValue.delete();
                    }

                    if (replacementFile != null) {
                      final docsDir = await _getLocalDocsDir();
                      final fileName =
                          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(replacementFile!.path)}';
                      final savedFile =
                          await replacementFile!.copy('${docsDir.path}/$fileName');

                      updateData["localPath"] = savedFile.path;
                      updateData["fileName"] = fileName;
                      updateData["fileSizeKB"] = replacementFileSizeKB;

                      final oldPath = (data['localPath'] ?? '').toString();
                      if (oldPath.isNotEmpty && oldPath != savedFile.path) {
                        final oldFile = File(oldPath);
                        if (await oldFile.exists()) {
                          await oldFile.delete();
                        }
                      }
                    }

                    await FirebaseFirestore.instance
                        .collection("documents")
                        .doc(docId)
                        .update(updateData);

                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      backgroundColor: const Color(0xFFE8EFF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13233A),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.folder, size: 20, color: Color(0xFFFFCC66)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "My Documents",
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _handleBack,
            child: const Text(
              "Back",
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F7FC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD4DFEE)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 700;
                  if (isMobile) {
                    return Column(
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            hintText: "Search title, description, category",
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            isDense: true,
                          ),
                          onChanged: (v) {
                            setState(() {
                              searchQuery = v.toLowerCase();
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF179A51),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {},
                            child: const Text("Apply"),
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: "Search title, description, category",
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            isDense: true,
                          ),
                          onChanged: (v) {
                            setState(() {
                              searchQuery = v.toLowerCase();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF179A51),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {},
                          child: const Text("Apply"),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("documents")
                  .where("userId", isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No documents in this folder"));
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['isTrashed'] == true) {
                    return false;
                  }
                  final normalizedCategory = _normalizeCategory(
                    (data['category'] ?? '').toString(),
                  );
                  if (normalizedCategory != widget.category) {
                    return false;
                  }

                  return (data['title'] ?? '')
                              .toString()
                              .toLowerCase()
                              .contains(searchQuery) ||
                      (data['description'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(searchQuery) ||
                      (data['fileName'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(searchQuery) ||
                      widget.category.toLowerCase().contains(searchQuery);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text("No matching document found"));
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 18, 10, 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F7FC),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 18,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Text(
                                widget.category,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111C33),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isMobile = constraints.maxWidth < 760;

                                if (isMobile) {
                                  return Column(
                                    children: List.generate(docs.length, (index) {
                                      final docSnap = docs[index];
                                      final data =
                                          docSnap.data() as Map<String, dynamic>;
                                      return _mobileDocCard(
                                        index: index,
                                        docId: docSnap.id,
                                        data: data,
                                      );
                                    }),
                                  );
                                }

                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(
                                      const Color(0xFF21344E),
                                    ),
                                    dataRowColor: WidgetStateProperty.resolveWith(
                                      (states) => Colors.white,
                                    ),
                                    columnSpacing: 20,
                                    horizontalMargin: 12,
                                    columns: const [
                                      DataColumn(
                                        label: Text(
                                          "Index",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          "Title",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          "Description",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          "Privacy",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          "Upload Date",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          "File",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                    rows: List.generate(docs.length, (index) {
                                      final docSnap = docs[index];
                                      final data =
                                          docSnap.data() as Map<String, dynamic>;
                                      final isLocked = data['isLocked'] == true;

                                      return DataRow(
                                        cells: [
                                          DataCell(Text("${index + 1}")),
                                          DataCell(
                                            InkWell(
                                              onTap: () => _openDocument(data),
                                              child: Text(
                                                (data['title'] ?? "Untitled")
                                                    .toString(),
                                                style: const TextStyle(
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            SizedBox(
                                              width: 180,
                                              child: Text(
                                                (data['description'] ?? "")
                                                    .toString(),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              isLocked
                                                  ? "Locked (Private)"
                                                  : "Public",
                                              style: TextStyle(
                                                color: isLocked
                                                    ? Colors.redAccent
                                                    : Colors.green,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(_formatDate(data['createdAt'])),
                                          ),
                                          DataCell(
                                            SizedBox(
                                              width: 260,
                                              child: Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  _actionButton(
                                                    "Download",
                                                    const Color(0xFF179A51),
                                                    () => _openDocument(data),
                                                  ),
                                                  _actionButton(
                                                    "Edit",
                                                    const Color(0xFF15803D),
                                                    () => _openEditDocument(
                                                      docSnap.id,
                                                      data,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Total ${docs.length} documents",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF35435B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileDocCard({
    required int index,
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final isLocked = data['isLocked'] == true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDocument(data),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD5E1F2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFFE8F1FF),
                    child: Text(
                      "${index + 1}",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => _openDocument(data),
                      child: Text(
                        (data['title'] ?? "Untitled").toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isLocked
                          ? const Color(0xFFFDECEC)
                          : const Color(0xFFEAF9EE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isLocked ? "Locked" : "Public",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isLocked ? Colors.redAccent : Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if ((data['description'] ?? "").toString().trim().isNotEmpty)
                Text(
                  (data['description'] ?? "").toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF46556E)),
                ),
              const SizedBox(height: 8),
              Text(
                "Uploaded: ${_formatDate(data['createdAt'])}",
                style: const TextStyle(
                  color: Color(0xFF52627A),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _actionButton(
                    "Download",
                    const Color(0xFF179A51),
                    () => _openDocument(data),
                  ),
                  _actionButton(
                    "Edit",
                    const Color(0xFF15803D),
                    () => _openEditDocument(docId, data),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _actionButton(
    String label,
    Color color,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      height: 34,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete Document"),
        content: const Text("Are you sure you want to delete this document?"),
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

String _formatDate(dynamic ts) {
  if (ts == null) return "";
  final d = (ts as Timestamp).toDate();
  return "${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} "
      "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
}
