import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:provider/provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:mobile/widgets/primary_button.dart';
// import 'package:mobile/widgets/secondary_button.dart';
import 'package:mobile/widgets/primary_dialog.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/user_management_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/sync_provider.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/db/app_database.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  // Bulk selection state (mirrors store management bulky bar)
  final Set<int> _selectedAdminIds = {};
  bool _isBulkActionLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final userManagementProvider = context.read<UserManagementProvider>();
    final storeProvider = context.read<StoreProvider>();

    // Ensure store provider is initialized first so an explicit All Stores
    // context from the server is restored before we load stores/users.
    try {
      if (!storeProvider.isInitialized) {
        // Start initialization in background to avoid blocking the UI and to
        // prevent creating timeout timers that interfere with tests.
        unawaited(storeProvider.initialize());
      }
    } catch (e) {
      debugPrint('AdminManagement: store init skipped: $e');
    }

    // Set store provider reference for filtering
    userManagementProvider.setStoreProvider(storeProvider);

    // Load users and stores in background to avoid blocking initialization
    unawaited(userManagementProvider.loadUsers());
    unawaited(storeProvider.loadStores());
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userManagementProvider = context.watch<UserManagementProvider>();
    final storeProvider = context.watch<StoreProvider>();

    // Only superadmin can access this screen
    if (authProvider.role != UserRole.superadmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('You do not have permission to access this screen.'),
        ),
      );
    }

    final admins = userManagementProvider.admins
        .where(
            (admin) => admin['store_id'] == storeProvider.currentStore?['id'])
        .toList();
    final stores = storeProvider.stores;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Management'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StoreIndicator(
              store: storeProvider.currentStore,
            ),
          ),
        ),
        actions: [
          // Use the quick action button in the app bar for switching stores — prefer this placement
          if (authProvider.role == UserRole.superadmin ||
              authProvider.role == UserRole.admin)
            const StoreQuickAction(),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateAdminDialog(context, stores),
          ),
        ],
      ),
      body: userManagementProvider.isLoading || storeProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : admins.isEmpty
              ? const Center(
                  child: Text('No admins found. Create your first admin.'),
                )
              : Column(
                  children: [
                    // Bulk action bar (shows when one or more admins are selected)
                    if (_selectedAdminIds.isNotEmpty)
                      Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Wrap(
                              alignment: WrapAlignment.start,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxWidth: constraints.maxWidth * 0.22),
                                  child: Text(
                                    '${_selectedAdminIds.length} selected',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxWidth: constraints.maxWidth * 0.78),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.max,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: _isBulkActionLoading
                                              ? const CircularProgressIndicator(
                                                  strokeWidth: 2)
                                              : const SizedBox.shrink(),
                                        ),
                                        const SizedBox(width: 4),

                                        // Select-all button
                                        Builder(builder: (context) {
                                          final visibleIds = admins
                                              .where((a) => a['id'] != null)
                                              .map((a) => a['id'] as int)
                                              .toList();
                                          final allSelected =
                                              visibleIds.isNotEmpty &&
                                                  visibleIds.every((id) =>
                                                      _selectedAdminIds
                                                          .contains(id));

                                          return IconButton(
                                            tooltip: allSelected
                                                ? 'Clear selection'
                                                : 'Select all',
                                            onPressed: _isBulkActionLoading
                                                ? null
                                                : () {
                                                    setState(() {
                                                      if (allSelected) {
                                                        _selectedAdminIds
                                                            .clear();
                                                      } else {
                                                        _selectedAdminIds
                                                            .addAll(visibleIds);
                                                      }
                                                    });
                                                  },
                                            padding: const EdgeInsets.all(6),
                                            icon: Icon(allSelected
                                                ? Icons.check_box
                                                : Icons.select_all),
                                          );
                                        }),
                                        const SizedBox(width: 4),

                                        // Bulk toggle activation
                                        Builder(builder: (context) {
                                          final selectedAdmins = admins
                                              .where((a) =>
                                                  a['id'] != null &&
                                                  _selectedAdminIds
                                                      .contains(a['id']))
                                              .toList();
                                          final hasInactive =
                                              selectedAdmins.any((a) =>
                                                  a['is_active'] != true);
                                          final hasActive = selectedAdmins.any(
                                              (a) => a['is_active'] == true);

                                          IconData toggleIcon;
                                          Color? toggleColor;
                                          String tooltip;

                                          if (hasActive && hasInactive) {
                                            toggleIcon = Icons.sync;
                                            toggleColor = Colors.amber;
                                            tooltip =
                                                'Toggle activation (mixed)';
                                          } else if (hasInactive) {
                                            toggleIcon = Icons.toggle_on;
                                            toggleColor = Colors.green;
                                            tooltip = 'Activate selected';
                                          } else {
                                            toggleIcon = Icons.toggle_off;
                                            toggleColor = Colors.grey;
                                            tooltip = 'Deactivate selected';
                                          }

                                          final targetActivate = hasInactive;

                                          return AnimatedSwitcher(
                                            duration: const Duration(
                                                milliseconds: 220),
                                            transitionBuilder:
                                                (child, animation) =>
                                                    ScaleTransition(
                                              scale: animation,
                                              child: FadeTransition(
                                                  opacity: animation,
                                                  child: child),
                                            ),
                                            child: IconButton(
                                              key: ValueKey<int>(
                                                  toggleIcon.codePoint),
                                              tooltip: tooltip,
                                              onPressed: _isBulkActionLoading
                                                  ? null
                                                  : () =>
                                                      _confirmBulkToggleAdminStatus(
                                                          targetActivate),
                                              padding: const EdgeInsets.all(6),
                                              icon: Icon(toggleIcon,
                                                  color: toggleColor),
                                            ),
                                          );
                                        }),
                                        const SizedBox(width: 4),

                                        IconButton(
                                          tooltip: 'Delete',
                                          onPressed: _isBulkActionLoading
                                              ? null
                                              : () =>
                                                  _confirmBulkDeleteAdmins(),
                                          padding: const EdgeInsets.all(6),
                                          icon:
                                              const Icon(Icons.delete_forever),
                                          color: _isBulkActionLoading
                                              ? null
                                              : Colors.red,
                                        ),
                                        const SizedBox(width: 4),

                                        IconButton(
                                          tooltip: 'Clear',
                                          onPressed: _isBulkActionLoading
                                              ? null
                                              : _clearAdminSelection,
                                          padding: const EdgeInsets.all(6),
                                          icon: const Icon(Icons.clear),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                    Expanded(
                      child: ListView.builder(
                        itemCount: admins.length,
                        itemBuilder: (context, index) {
                          final admin = admins[index];
                          final assignedStore = stores.firstWhere(
                            (store) => store['id'] == admin['store_id'],
                            orElse: () => {
                              'id': -1,
                              'name': 'No Store Assigned',
                              'location': '',
                              'is_active': false,
                            },
                          );

                          final id = admin['id'] as int?;
                          final isSelected =
                              id != null && _selectedAdminIds.contains(id);

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: ListTile(
                              leading: id == null
                                  ? CircleAvatar(
                                      backgroundColor:
                                          admin['is_active'] == true
                                              ? Colors.green
                                              : Colors.grey,
                                      child: Icon(
                                        admin['is_active'] == true
                                            ? Icons.check
                                            : Icons.close,
                                        color: Colors.white,
                                      ),
                                    )
                                  : _selectedAdminIds.isNotEmpty
                                      ? Checkbox(
                                          value: isSelected,
                                          onChanged: (v) => setState(() {
                                            if (v == true) {
                                              _selectedAdminIds.add(id);
                                            } else {
                                              _selectedAdminIds.remove(id);
                                            }
                                          }),
                                        )
                                      : CircleAvatar(
                                          backgroundColor:
                                              admin['is_active'] == true
                                                  ? Colors.green
                                                  : Colors.grey,
                                          child: Icon(
                                            admin['is_active'] == true
                                                ? Icons.check
                                                : Icons.close,
                                            color: Colors.white,
                                          ),
                                        ),
                              title:
                                  Text(admin['full_name'] ?? admin['username']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Username: ${admin['username']}'),
                                  const SizedBox(height: 4),
                                  StoreBadge(
                                    store: assignedStore,
                                    showLocation: false,
                                    compact: true,
                                  ),
                                  Text(
                                      'Status: ${admin['is_active'] == true ? 'Active' : 'Inactive'}'),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) =>
                                    _handleAdminAction(value, admin, stores),
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit Admin'),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle_status',
                                    child: Text(
                                      admin['is_active'] == true
                                          ? 'Deactivate Admin'
                                          : 'Activate Admin',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'assign_store',
                                    child: Text('Assign to Store'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete Admin'),
                                  ),
                                ],
                              ),
                              onTap: () {
                                if (_selectedAdminIds.isNotEmpty &&
                                    id != null) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedAdminIds.remove(id);
                                    } else {
                                      _selectedAdminIds.add(id);
                                    }
                                  });
                                  return;
                                }

                                _showEditAdminDialog(context, admin, stores);
                              },
                              onLongPress: () {
                                // Long press activates selection mode and selects this item
                                if (id != null) {
                                  setState(() {
                                    _selectedAdminIds.add(id);
                                  });
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar:
          const AppBottomNav(currentRoute: '/admin_management'),
    );
  }

  void _showCreateAdminDialog(
      BuildContext context, List<Map<String, dynamic>> stores) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final fullNameController = TextEditingController();
    int? selectedStoreId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const PrimaryDialogTitle(title: 'Create New Admin'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrimaryTextField(
                  controller: usernameController,
                  label: 'Username',
                  hint: 'Enter admin username',
                ),
                const SizedBox(height: 16),
                PrimaryTextField(
                  controller: passwordController,
                  label: 'Password',
                  hint: 'Enter admin password',
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                PrimaryTextField(
                  controller: confirmPasswordController,
                  label: 'Confirm Password',
                  hint: 'Re-enter admin password',
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                PrimaryTextField(
                  controller: fullNameController,
                  label: 'Full Name',
                  hint: 'Enter admin full name',
                ),
                const SizedBox(height: 16),
                // For offline-first: show all active stores
                // ALWAYS use local id for database FK constraint
                // Store server_id separately for sync purposes
                DropdownButtonFormField<int>(
                  initialValue: selectedStoreId,
                  decoration: const InputDecoration(
                    labelText: 'Assign to Store',
                    hintText: 'Select a store',
                  ),
                  items: stores
                      .where((store) => store['is_active'] == true)
                      .map((store) {
                    final name = (store['name'] ?? 'Unnamed Store').toString();
                    final serverId = store['server_id'] as int?;
                    final localId = store['id'] as int;
                    // ALWAYS use local id for the value - needed for FK constraint
                    final isPending = serverId == null;
                    return DropdownMenuItem<int>(
                      value: localId, // Use LOCAL id for database FK
                      child: Row(
                        children: [
                          Text(name),
                          if (isPending) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Pending Sync',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.orange),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedStoreId = value);
                  },
                ),
                const SizedBox(height: 8),
                if (stores
                    .where((s) => s['is_active'] == true)
                    .where((s) => s['server_id'] == null)
                    .isNotEmpty)
                  const Text(
                    'Stores marked "Pending Sync" will sync before the admin. Both will be available once online.',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
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
                if (usernameController.text.isEmpty ||
                    passwordController.text.isEmpty ||
                    confirmPasswordController.text.isEmpty ||
                    fullNameController.text.isEmpty ||
                    selectedStoreId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill all fields'),
                    ),
                  );
                  return;
                }

                if (passwordController.text != confirmPasswordController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Passwords do not match'),
                    ),
                  );
                  return;
                }

                try {
                  debugPrint('🔵 Admin creation button pressed');
                  debugPrint('   username: ${usernameController.text}');
                  debugPrint('   fullName: ${fullNameController.text}');
                  debugPrint('   store_id: $selectedStoreId');

                  await context.read<UserManagementProvider>().createUser({
                    'username': usernameController.text,
                    'password': passwordController.text,
                    'full_name': fullNameController.text,
                    'role': 'admin',
                    'store_id': selectedStoreId,
                  });

                  // Trigger immediate sync after creating user
                  debugPrint(
                      '🔄 User created locally, triggering immediate sync...');
                  if (context.mounted) {
                    context.read<SyncProvider>().sync();
                  }

                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Admin created successfully'),
                      ),
                    );
                  }
                } catch (e, stackTrace) {
                  debugPrint('❌ Error creating admin: $e');
                  debugPrint('Stack trace: $stackTrace');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAdminAction(String action, Map<String, dynamic> admin,
      List<Map<String, dynamic>> stores) {
    switch (action) {
      case 'edit':
        _showEditAdminDialog(context, admin, stores);
        break;
      case 'toggle_status':
        _toggleAdminStatus(context, admin);
        break;
      case 'assign_store':
        _showAssignStoreDialog(context, admin, stores);
        break;
      case 'delete':
        _showDeleteAdminDialog(context, admin);
        break;
    }
  }

  void _showEditAdminDialog(BuildContext context, Map<String, dynamic> admin,
      List<Map<String, dynamic>> stores) {
    final fullNameController =
        TextEditingController(text: admin['full_name'] as String?);
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Edit Admin'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryTextField(
                controller: fullNameController,
                label: 'Full Name',
                hint: 'Enter admin full name',
              ),
              const SizedBox(height: 16),
              PrimaryTextField(
                controller: passwordController,
                label: 'New Password (optional)',
                hint: 'Leave empty to keep current password',
                obscureText: true,
              ),
              const SizedBox(height: 16),
              PrimaryTextField(
                controller: confirmPasswordController,
                label: 'Confirm New Password',
                hint: 'Re-enter new password',
                obscureText: true,
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
              if (fullNameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Full name cannot be empty'),
                  ),
                );
                return;
              }

              // Check password confirmation if password is provided
              if (passwordController.text.isNotEmpty) {
                if (passwordController.text != confirmPasswordController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Passwords do not match'),
                    ),
                  );
                  return;
                }
              }

              try {
                await context.read<UserManagementProvider>().updateUser(
                  admin['id'],
                  {
                    'full_name': fullNameController.text,
                    if (passwordController.text.isNotEmpty)
                      'password': passwordController.text,
                  },
                );

                // Trigger sync after update
                if (context.mounted) {
                  context.read<SyncProvider>().sync();
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Admin updated successfully'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _toggleAdminStatus(
      BuildContext context, Map<String, dynamic> admin) async {
    final userManagementProvider = context.read<UserManagementProvider>();
    try {
      await userManagementProvider.updateUser(
        admin['id'],
        {'is_active': !(admin['is_active'] ?? true)},
      );

      // Trigger sync after toggle
      if (context.mounted) {
        context.read<SyncProvider>().sync();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Admin ${(admin['is_active'] ?? true) ? 'deactivated' : 'activated'} successfully',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showAssignStoreDialog(BuildContext context, Map<String, dynamic> admin,
      List<Map<String, dynamic>> stores) {
    int? selectedStoreId = admin['store_id'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const PrimaryDialogTitle(
              title: 'Assign Admin to Store',
              textColor: AppColors.primaryBrand),
          content: DropdownButtonFormField<int>(
            initialValue: selectedStoreId,
            decoration: const InputDecoration(
              labelText: 'Select Store',
            ),
            items: stores
                .where((store) => store['is_active'] == true)
                .map((store) => DropdownMenuItem<int>(
                      value: store['id'] as int,
                      child:
                          Text((store['name'] ?? 'Unnamed Store').toString()),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() => selectedStoreId = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            PrimaryButton(
              onPressed: () async {
                if (selectedStoreId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a store'),
                    ),
                  );
                  return;
                }

                try {
                  await context
                      .read<UserManagementProvider>()
                      .assignUserToStore(
                        admin['id'],
                        selectedStoreId!,
                      );

                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Admin assigned to store successfully'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAdminDialog(
      BuildContext context, Map<String, dynamic> admin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Delete Admin'),
        content: Text(
          'Are you sure you want to permanently delete admin "${admin['full_name'] ?? admin['username']}"? This action cannot be undone and will completely remove the admin account from the system.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await context
                    .read<UserManagementProvider>()
                    .hardDeleteUser(admin['id']);

                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Admin permanently deleted'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBulkToggleAdminStatus(bool activate) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Change Admin Status'),
        content: Text(
            'Are you sure you want to ${activate ? 'activate' : 'deactivate'} ${_selectedAdminIds.length} selected admins?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );

    if (ok != true) return;

    final userManagementProvider = context.read<UserManagementProvider>();
    setState(() => _isBulkActionLoading = true);
    try {
      for (final id in _selectedAdminIds.toList()) {
        await userManagementProvider.updateUser(id, {'is_active': activate});
      }
      // Trigger sync after bulk update
      if (context.mounted) {
        context.read<SyncProvider>().sync();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bulk status update completed')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error performing bulk update: $e')));
      }
    } finally {
      setState(() {
        _isBulkActionLoading = false;
        _selectedAdminIds.clear();
      });
    }
  }

  Future<void> _confirmBulkDeleteAdmins() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Delete Admins'),
        content: Text(
            'Are you sure you want to permanently delete ${_selectedAdminIds.length} selected admins? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;
    final userManagementProvider = context.read<UserManagementProvider>();
    setState(() => _isBulkActionLoading = true);
    try {
      for (final id in _selectedAdminIds.toList()) {
        await userManagementProvider.hardDeleteUser(id);
      }
      // Trigger sync after bulk delete
      if (context.mounted) {
        context.read<SyncProvider>().sync();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected admins deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error deleting admins: $e')));
      }
    } finally {
      setState(() {
        _isBulkActionLoading = false;
        _selectedAdminIds.clear();
      });
    }
  }

  void _clearAdminSelection() {
    setState(() => _selectedAdminIds.clear());
  }
}
