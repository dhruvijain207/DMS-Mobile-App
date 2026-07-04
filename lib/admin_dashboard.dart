import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'login_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final docSearchCtrl = TextEditingController();
  final ownerSearchCtrl = TextEditingController();
  final userSearchCtrl = TextEditingController();

  String docCategoryFilter = 'All';
  String docPrivacyFilter = 'All';
  bool sortDocNewestFirst = true;

  String userRoleFilter = 'All';
  String userKeyFilter = 'All';

  @override
  void dispose() {
    docSearchCtrl.dispose();
    ownerSearchCtrl.dispose();
    userSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openDocument(Map<String, dynamic> data) async {
    final localPath = (data['localPath'] ?? '').toString();
    if (localPath.isEmpty || !File(localPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found on this device')),
      );
      return;
    }

    final result = await OpenFilex.open(localPath);
    if (!mounted) return;
    if (result.type == ResultType.noAppToOpen || result.type == ResultType.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isEmpty
                ? 'No compatible app found to open this file'
                : result.message,
          ),
        ),
      );
    }
  }

  Future<void> _deleteDocument(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text('Are you sure you want to delete this document?'),
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Document deleted')),
    );
  }

  Future<void> _updateUserRole(String userId, String newRole) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'role': newRole,
      'updatedAt': Timestamp.now(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Role updated to $newRole')),
    );
  }

  List<QueryDocumentSnapshot> _filterDocuments(List<QueryDocumentSnapshot> docs) {
    final search = docSearchCtrl.text.trim().toLowerCase();
    final owner = ownerSearchCtrl.text.trim().toLowerCase();

    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final title = (data['title'] ?? '').toString().toLowerCase();
      final description = (data['description'] ?? '').toString().toLowerCase();
      final fileName = (data['fileName'] ?? '').toString().toLowerCase();
      final userId = (data['userId'] ?? '').toString().toLowerCase();
      final category = _normalizeCategory((data['category'] ?? '').toString());
      final isLocked = data['isLocked'] == true;

      final matchSearch = search.isEmpty ||
          title.contains(search) ||
          description.contains(search) ||
          fileName.contains(search);
      final matchOwner = owner.isEmpty || userId.contains(owner);
      final matchCategory =
          docCategoryFilter == 'All' || category == docCategoryFilter;
      final matchPrivacy = docPrivacyFilter == 'All' ||
          (docPrivacyFilter == 'Locked' && isLocked) ||
          (docPrivacyFilter == 'Public' && !isLocked);

      return matchSearch && matchOwner && matchCategory && matchPrivacy;
    }).toList();

    filtered.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      final aTime = (aData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final bTime = (bData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      return sortDocNewestFirst ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
    });

    return filtered;
  }

  List<QueryDocumentSnapshot> _filterUsers(List<QueryDocumentSnapshot> users) {
    final search = userSearchCtrl.text.trim().toLowerCase();

    return users.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final username = (data['username'] ?? '').toString().toLowerCase();
      final email = (data['email'] ?? '').toString().toLowerCase();
      final phone = (data['phone'] ?? '').toString().toLowerCase();
      final role = (data['role'] ?? 'user').toString().toLowerCase();
      final hasKey = data['hasPrivateKey'] == true;

      final matchSearch = search.isEmpty ||
          username.contains(search) ||
          email.contains(search) ||
          phone.contains(search);
      final matchRole = userRoleFilter == 'All' || role == userRoleFilter.toLowerCase();
      final matchKey = userKeyFilter == 'All' ||
          (userKeyFilter == 'With Key' && hasKey) ||
          (userKeyFilter == 'Without Key' && !hasKey);

      return matchSearch && matchRole && matchKey;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFEAF0FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF13233A),
          title: const Text('Admin Panel'),
          actions: [
            TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text('Logout', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.description_outlined), text: 'Documents'),
              Tab(icon: Icon(Icons.people_outline), text: 'Users'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDocumentsTab(),
            _buildUsersTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('documents').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final filteredDocs = _filterDocuments(docs);
        final isMobile = MediaQuery.of(context).size.width < 900;

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD3DEEF)),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: docSearchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Search title/description/file',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: ownerSearchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Filter by User ID',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_search),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      initialValue: docCategoryFilter,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(
                          value: 'Personal Documents',
                          child: Text('Personal'),
                        ),
                        DropdownMenuItem(
                          value: 'Business Documents',
                          child: Text('Business'),
                        ),
                        DropdownMenuItem(
                          value: 'Marksheets',
                          child: Text('Marksheets'),
                        ),
                        DropdownMenuItem(
                          value: 'Family Documents',
                          child: Text('Family'),
                        ),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          docCategoryFilter = value ?? 'All';
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      initialValue: docPrivacyFilter,
                      decoration: const InputDecoration(
                        labelText: 'Privacy',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(value: 'Public', child: Text('Public')),
                        DropdownMenuItem(value: 'Locked', child: Text('Locked')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          docPrivacyFilter = value ?? 'All';
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      initialValue: sortDocNewestFirst ? 'Newest' : 'Oldest',
                      decoration: const InputDecoration(
                        labelText: 'Sort',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Newest', child: Text('Newest')),
                        DropdownMenuItem(value: 'Oldest', child: Text('Oldest')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          sortDocNewestFirst = value != 'Oldest';
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filtered Documents: ${filteredDocs.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF33435E),
                  ),
                ),
              ),
            ),
            Expanded(
              child: filteredDocs.isEmpty
                  ? const Center(child: Text('No documents match selected filters'))
                  : isMobile
                      ? ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          itemCount: filteredDocs.length,
                          itemBuilder: (context, index) {
                            final doc = filteredDocs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final isLocked = data['isLocked'] == true;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                onTap: () => _openDocument(data),
                                leading: Icon(
                                  isLocked ? Icons.lock_outline : Icons.description_outlined,
                                  color: isLocked ? Colors.redAccent : Colors.blue,
                                ),
                                title: Text(
                                  (data['title'] ?? 'Untitled').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  'Category: ${_normalizeCategory((data['category'] ?? '').toString())}\n'
                                  'Owner: ${(data['userId'] ?? '').toString().substring(0, ((data['userId'] ?? '').toString().length > 8) ? 8 : (data['userId'] ?? '').toString().length)}...\n'
                                  'Privacy: ${isLocked ? 'Locked' : 'Public'}',
                                ),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'open') {
                                      _openDocument(data);
                                    } else if (value == 'delete') {
                                      _deleteDocument(doc.id);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'open',
                                      child: Text('Open'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFF1F3553),
                            ),
                            headingTextStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            columns: const [
                              DataColumn(label: Text('Title')),
                              DataColumn(label: Text('Category')),
                              DataColumn(label: Text('Privacy')),
                              DataColumn(label: Text('Owner')),
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: filteredDocs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final isLocked = data['isLocked'] == true;

                              return DataRow(
                                cells: [
                                  DataCell(
                                    InkWell(
                                      onTap: () => _openDocument(data),
                                      child: Text(
                                        (data['title'] ?? 'Untitled').toString(),
                                        style: const TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(_normalizeCategory((data['category'] ?? '').toString())),
                                  ),
                                  DataCell(Text(isLocked ? 'Locked' : 'Public')),
                                  DataCell(
                                    SizedBox(
                                      width: 130,
                                      child: Text(
                                        (data['userId'] ?? '').toString(),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(_formatDate(data['createdAt']))),
                                  DataCell(
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        _tinyButton(
                                          label: 'Open',
                                          color: const Color(0xFF179A51),
                                          onTap: () => _openDocument(data),
                                        ),
                                        _tinyButton(
                                          label: 'Delete',
                                          color: const Color(0xFFDC2626),
                                          onTap: () => _deleteDocument(doc.id),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUsersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data?.docs ?? [];
        final filteredUsers = _filterUsers(users);

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD3DEEF)),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      controller: userSearchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Search username/email/phone',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      initialValue: userRoleFilter,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                        DropdownMenuItem(value: 'user', child: Text('User')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          userRoleFilter = value ?? 'All';
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: userKeyFilter,
                      decoration: const InputDecoration(
                        labelText: 'Private Key',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(
                          value: 'With Key',
                          child: Text('With Key'),
                        ),
                        DropdownMenuItem(
                          value: 'Without Key',
                          child: Text('Without Key'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          userKeyFilter = value ?? 'All';
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filtered Users: ${filteredUsers.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF33435E),
                  ),
                ),
              ),
            ),
            Expanded(
              child: filteredUsers.isEmpty
                  ? const Center(child: Text('No users match selected filters'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final userDoc = filteredUsers[index];
                        final data = userDoc.data() as Map<String, dynamic>;
                        final role = (data['role'] ?? 'user').toString();
                        final hasKey = data['hasPrivateKey'] == true;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  role == 'admin' ? Colors.orange : Colors.blueGrey,
                              child: Icon(
                                role == 'admin' ? Icons.shield : Icons.person,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              (data['username'] ?? 'Unknown').toString(),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Email: ${(data['email'] ?? '').toString()}\n'
                              'Phone: ${(data['phone'] ?? '').toString()}\n'
                              'Role: $role | Private Key: ${hasKey ? 'Yes' : 'No'}',
                            ),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'make_admin') {
                                  _updateUserRole(userDoc.id, 'admin');
                                } else if (value == 'make_user') {
                                  _updateUserRole(userDoc.id, 'user');
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'make_admin',
                                  child: Text('Make Admin'),
                                ),
                                PopupMenuItem(
                                  value: 'make_user',
                                  child: Text('Make User'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  static Widget _tinyButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 30,
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

String _normalizeCategory(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.contains('family')) return 'Family Documents';
  if (value.contains('personal')) return 'Personal Documents';
  if (value.contains('business') ||
      value.contains('bill') ||
      value.contains('finance') ||
      value.contains('work') ||
      value.contains('intern')) {
    return 'Business Documents';
  }
  if (value.contains('marksheet') ||
      value.contains('college') ||
      value.contains('certificate')) {
    return 'Marksheets';
  }
  return 'Other';
}

String _formatDate(dynamic ts) {
  if (ts == null) return '';
  final d = (ts as Timestamp).toDate();
  return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
