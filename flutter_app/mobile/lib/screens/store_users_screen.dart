import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_management_provider.dart';
import '../providers/auth_provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/widgets/primary_dialog.dart';

class StoreUsersScreen extends StatefulWidget {
  final Map<String, dynamic> store;

  const StoreUsersScreen({super.key, required this.store});

  @override
  State<StoreUsersScreen> createState() => _StoreUsersScreenState();
}

class _StoreUsersScreenState extends State<StoreUsersScreen> {
  List<Map<String, dynamic>> _storeUsers = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStoreUsers();
    });
  }

  Future<void> _loadStoreUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final users = await context
          .read<UserManagementProvider>()
          .getUsersByStore(widget.store['id']);
      setState(() {
        _storeUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load users: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Users - ${widget.store['name'] ?? 'Store'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStoreUsers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_errorMessage'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadStoreUsers,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _storeUsers.isEmpty
                  ? const Center(
                      child: Text('No users assigned to this store.'),
                    )
                  : ListView.builder(
                      itemCount: _storeUsers.length,
                      itemBuilder: (context, index) {
                        final user = _storeUsers[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: user['is_active'] == true
                                  ? _getRoleColor(user['role'])
                                  : Colors.grey,
                              child: Icon(
                                _getRoleIcon(user['role']),
                                color: Colors.white,
                              ),
                            ),
                            title: Text(user['full_name'] ?? user['username']),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Username: ${user['username']}'),
                                Text('Role: ${user['role']}'),
                                Text(
                                  'Status: ${user['is_active'] == true ? 'Active' : 'Inactive'}',
                                  style: TextStyle(
                                    color: user['is_active'] == true
                                        ? Colors.green
                                        : Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            trailing: authProvider.role == 'superadmin'
                                ? PopupMenuButton<String>(
                                    onSelected: (value) =>
                                        _handleUserAction(value, user),
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit User'),
                                      ),
                                      PopupMenuItem(
                                        value: 'toggle_status',
                                        child: Text(
                                          user['is_active'] == true
                                              ? 'Deactivate User'
                                              : 'Activate User',
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'remove_from_store',
                                        child: Text('Remove from Store'),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/store_users'),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'superadmin':
        return Colors.purple;
      case 'admin':
        return Colors.blue;
      case 'cashier':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'superadmin':
        return Icons.admin_panel_settings;
      case 'admin':
        return Icons.admin_panel_settings;
      case 'cashier':
        return Icons.person;
      default:
        return Icons.person;
    }
  }

  void _handleUserAction(String action, Map<String, dynamic> user) {
    switch (action) {
      case 'edit':
        _showEditUserDialog(context, user);
        break;
      case 'toggle_status':
        _toggleUserStatus(user);
        break;
      case 'remove_from_store':
        _showRemoveFromStoreDialog(context, user);
        break;
    }
  }

  void _showEditUserDialog(BuildContext context, Map<String, dynamic> user) {
    final fullNameController =
        TextEditingController(text: user['full_name'] as String?);
    final formKey = GlobalKey<FormState>();
    final fullNameFocus = FocusNode();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Edit User'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryTextField(
                controller: fullNameController,
                label: 'Full Name',
                autofocus: true,
                focusNode: fullNameFocus,
                semanticLabel: 'Edit user full name',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter full name';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          PrimaryButton(
            onPressed: () async {
              final valid = formKey.currentState?.validate() ?? false;
              if (!valid) {
                fullNameFocus.requestFocus();
                return;
              }

              try {
                await context.read<UserManagementProvider>().updateUser(
                  user['id'],
                  {'full_name': fullNameController.text},
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                  _loadStoreUsers(); // Refresh the list
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User updated successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating user: $e')),
                  );
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    ).then((_) {
      fullNameFocus.dispose();
    });
  }

  void _toggleUserStatus(Map<String, dynamic> user) async {
    try {
      await context.read<UserManagementProvider>().updateUser(
        user['id'],
        {'is_active': !(user['is_active'] ?? true)},
      );
      _loadStoreUsers(); // Refresh the list
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'User ${(user['is_active'] ?? true) ? 'deactivated' : 'activated'} successfully',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating user status: $e')),
      );
    }
  }

  void _showRemoveFromStoreDialog(
      BuildContext context, Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove User from Store'),
        content: Text(
          'Are you sure you want to remove "${user['full_name'] ?? user['username']}" from this store? The user will remain in the system but will not be assigned to any store.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await context.read<UserManagementProvider>().updateUser(
                  user['id'],
                  {'store_id': null}, // Remove from store
                );
                Navigator.of(context).pop();
                _loadStoreUsers(); // Refresh the list
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('User removed from store successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error removing user from store: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
