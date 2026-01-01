import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:mobile/widgets/primary_button.dart';
// import 'package:mobile/widgets/secondary_button.dart';
import 'package:mobile/widgets/primary_dialog.dart';
import '../providers/store_provider.dart';
import '../services/store_service.dart';
import '../providers/auth_provider.dart';
import '../providers/user_management_provider.dart';
import 'store_users_screen.dart';

class StoreManagementScreen extends StatefulWidget {
  const StoreManagementScreen({super.key});

  @override
  State<StoreManagementScreen> createState() => _StoreManagementScreenState();
}

class _StoreManagementScreenState extends State<StoreManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();

  // Bulk selection state
  final Set<int> _selectedStoreIds = {};
  bool _isBulkActionLoading = false;

  @override
  void initState() {
    super.initState();
    // Load stores when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('StoreManagementScreen.initState: requesting loadStores');
      try {
        context.read<StoreProvider>().loadStores();
      } catch (e) {
        debugPrint(
            'StoreManagementScreen.initState: StoreProvider missing: $e');
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Defensive: provider lookup may fail if the caller didn't wrap app with required providers.
    late final AuthProvider authProvider;
    late final StoreProvider storeProvider;
    try {
      authProvider = Provider.of<AuthProvider>(context);
      storeProvider = Provider.of<StoreProvider>(context);
    } catch (e) {
      debugPrint('StoreManagementScreen.build: required provider missing: $e');
      return Scaffold(
        appBar: AppBar(title: const Text('Store Management')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Internal error: required app providers are not available.\nPlease restart the app or contact support.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    // Debug: log build state so we can trace why UI gets stuck
    debugPrint(
        'StoreManagementScreen.build: isLoading=${storeProvider.isLoading}, stores=${storeProvider.stores.length}, error=${storeProvider.errorMessage}');

    // Only superadmins can access this screen
    // If role is not yet available, show a loading indicator to avoid a false deny
    if (authProvider.role == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Use case-insensitive check to be resilient to role string variations
    if ((authProvider.role ?? '').toLowerCase() != 'superadmin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('You do not have permission to access this screen.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateStoreDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => storeProvider.loadStores(),
          ),
        ],
      ),
      body: Consumer<StoreProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${provider.errorMessage}'),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    onPressed: () => provider.loadStores(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final stores = provider.stores;

          if (stores.isEmpty) {
            return const Center(
              child: Text('No stores found. Create your first store.'),
            );
          }

          return Column(
            children: [
              // Bulk action bar (responsive: wraps to new line on narrow screens)
              if (_selectedStoreIds.isNotEmpty)
                Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Wrap(
                        alignment: WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ConstrainedBox(
                            // Reduce selected-label width so icons get more room
                            constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * 0.22),
                            child: Text(
                              '${_selectedStoreIds.length} selected',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Actions: give more width to the icons area so they fit horizontally
                          ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * 0.78),
                            // Keep icons in a single horizontal row; allow horizontal scroll on narrow screens
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Reserve space for a small loading indicator (keeps layout stable)
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: _isBulkActionLoading
                                        ? const CircularProgressIndicator(
                                            strokeWidth: 2)
                                        : const SizedBox.shrink(),
                                  ),
                                  const SizedBox(width: 4),

                                  // Select-all button (toggles all visible stores)
                                  Builder(builder: (context) {
                                    final visibleIds = storeProvider.stores
                                        .where((s) => s['id'] != null)
                                        .map((s) => s['id'] as int)
                                        .toList();
                                    final allSelected = visibleIds.isNotEmpty &&
                                        visibleIds.every((id) =>
                                            _selectedStoreIds.contains(id));

                                    return IconButton(
                                      tooltip: allSelected
                                          ? 'Clear selection'
                                          : 'Select all',
                                      onPressed: _isBulkActionLoading
                                          ? null
                                          : () {
                                              setState(() {
                                                if (allSelected) {
                                                  _selectedStoreIds.clear();
                                                } else {
                                                  _selectedStoreIds
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

                                  // Single toggle: displays on/off/mixed and toggles selected stores
                                  Builder(builder: (context) {
                                    final selectedStores = storeProvider.stores
                                        .where((s) =>
                                            s['id'] != null &&
                                            _selectedStoreIds.contains(s['id']))
                                        .toList();
                                    final hasInactive = selectedStores
                                        .any((s) => s['is_active'] != true);
                                    final hasActive = selectedStores
                                        .any((s) => s['is_active'] == true);

                                    // Determine icon and tooltip
                                    IconData toggleIcon;
                                    Color? toggleColor;
                                    String tooltip;

                                    if (hasActive && hasInactive) {
                                      toggleIcon = Icons.sync; // mixed state
                                      toggleColor = Colors.amber;
                                      tooltip = 'Toggle activation (mixed)';
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

                                    // Debug state for testing
                                    debugPrint(
                                        'StoreManagementScreen.bulkToggle: selected=${_selectedStoreIds.length}, hasActive=$hasActive, hasInactive=$hasInactive, icon=$toggleIcon, tooltip=$tooltip');

                                    // AnimatedSwitcher to smoothly transition between icon states
                                    return AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      transitionBuilder: (child, animation) =>
                                          ScaleTransition(
                                        scale: animation,
                                        child: FadeTransition(
                                            opacity: animation, child: child),
                                      ),
                                      child: IconButton(
                                        key:
                                            ValueKey<int>(toggleIcon.codePoint),
                                        tooltip: tooltip,
                                        onPressed: _isBulkActionLoading
                                            ? null
                                            : () => _confirmBulkToggleStatus(
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
                                        : () => _confirmBulkDelete(),
                                    padding: const EdgeInsets.all(6),
                                    icon: const Icon(Icons.delete_forever),
                                    color: _isBulkActionLoading
                                        ? null
                                        : Colors.red,
                                  ),
                                  const SizedBox(width: 4),

                                  IconButton(
                                    tooltip: 'Clear',
                                    onPressed: _isBulkActionLoading
                                        ? null
                                        : _clearSelection,
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
                  itemCount: stores.length,
                  itemBuilder: (context, index) {
                    final store = stores[index];
                    final id = store['id'] as int?;
                    final isSelected =
                        id != null && _selectedStoreIds.contains(id);
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: id == null
                            ? null
                            : _selectedStoreIds.isNotEmpty
                                ? Checkbox(
                                    value: isSelected,
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selectedStoreIds.add(id);
                                      } else {
                                        _selectedStoreIds.remove(id);
                                      }
                                    }),
                                  )
                                : null,
                        title: Text(
                          store['name'] ?? 'Unnamed Store',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: store['is_active'] == true
                                ? Colors.black
                                : Colors.grey,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(store['location'] ?? 'No location'),
                            Text(
                              'Status: ${store['is_active'] == true ? 'Active' : 'Inactive'}',
                              style: TextStyle(
                                color: store['is_active'] == true
                                    ? Colors.green
                                    : Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) =>
                              _handleStoreAction(value, store),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit Store'),
                            ),
                            const PopupMenuItem(
                              value: 'users',
                              child: Text('View Users'),
                            ),
                            const PopupMenuItem(
                              value: 'assign_admin',
                              child: Text('Assign Admin'),
                            ),
                            const PopupMenuItem(
                              value: 'toggle_status',
                              child: Text('Toggle Status'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete Store'),
                            ),
                          ],
                        ),
                        onTap: () {
                          // If user taps while in selection mode, toggle selection
                          if (_selectedStoreIds.isNotEmpty && id != null) {
                            setState(() {
                              if (isSelected) {
                                _selectedStoreIds.remove(id);
                              } else {
                                _selectedStoreIds.add(id);
                              }
                            });
                            return;
                          }
                          _showStoreDetails(context, store);
                        },
                        onLongPress: () {
                          // Long press activates selection mode and selects this item
                          if (id != null) {
                            setState(() {
                              _selectedStoreIds.add(id);
                            });
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar:
          const AppBottomNav(currentRoute: '/store_management'),
    );
  }

  void _showCreateStoreDialog(BuildContext context) {
    _nameController.clear();
    _locationController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Create New Store'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryTextField(
                controller: _nameController,
                label: 'Store Name',
                hint: 'Enter store name',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a store name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              PrimaryTextField(
                controller: _locationController,
                label: 'Location (Optional)',
                hint: 'Enter store location',
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
            onPressed: () => _createStore(context),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _createStore(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final storeData = {
      'name': _nameController.text.trim(),
      'location': _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
    };

    try {
      await context.read<StoreProvider>().createStore(storeData);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Store created successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating store: $e')),
        );
      }
    }
  }

  void _handleStoreAction(String action, Map<String, dynamic> store) {
    switch (action) {
      case 'edit':
        _showEditStoreDialog(context, store);
        break;
      case 'users':
        _navigateToStoreUsers(store);
        break;
      case 'assign_admin':
        _showAssignAdminDialog(context, store);
        break;
      case 'toggle_status':
        _toggleStoreStatus(store);
        break;
      case 'delete':
        _showDeleteConfirmation(context, store);
        break;
    }
  }

  void _showEditStoreDialog(BuildContext context, Map<String, dynamic> store) {
    _nameController.text = store['name'] ?? '';
    _locationController.text = store['location'] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Edit Store'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryTextField(
                controller: _nameController,
                label: 'Store Name',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a store name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              PrimaryTextField(
                controller: _locationController,
                label: 'Location',
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
            onPressed: () => _updateStore(context, store['id']),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _updateStore(BuildContext context, int storeId) async {
    if (!_formKey.currentState!.validate()) return;

    final storeData = {
      'name': _nameController.text.trim(),
      'location': _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
    };

    try {
      await context.read<StoreProvider>().updateStore(storeId, storeData);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Store updated successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating store: $e')),
        );
      }
    }
  }

  void _showStoreDetails(BuildContext context, Map<String, dynamic> store) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(store['name'] ?? 'Store Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Location: ${store['location'] ?? 'Not specified'}'),
            Text(
                'Status: ${store['is_active'] == true ? 'Active' : 'Inactive'}'),
            Text('Created: ${store['created_at'] ?? 'Unknown'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _navigateToStoreUsers(Map<String, dynamic> store) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StoreUsersScreen(store: store),
      ),
    );
  }

  void _showAssignAdminDialog(
      BuildContext context, Map<String, dynamic> store) async {
    final userManagementProvider = context.read<UserManagementProvider>();
    final storeProvider = context.read<StoreProvider>();

    // Load fresh data
    await userManagementProvider.loadUsers();
    await storeProvider.loadStores();

    final availableAdmins = userManagementProvider.admins
        .where((admin) => admin['is_active'] == true)
        .toList();

    if (availableAdmins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active admins available to assign')),
      );
      return;
    }

    Map<String, dynamic>? selectedAdmin;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: PrimaryDialogTitle(title: 'Assign Admin to ${store['name']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select an admin to assign to this store:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableAdmins.length,
                    itemBuilder: (context, index) {
                      final admin = availableAdmins[index];
                      final isSelected = selectedAdmin?['id'] == admin['id'];

                      return Card(
                        color: isSelected ? Colors.blue.shade50 : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Text(
                              (admin['full_name'] ?? admin['username'])
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(admin['full_name'] ?? admin['username']),
                          subtitle: Text('Username: ${admin['username']}'),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle,
                                  color: Colors.blue)
                              : const Icon(Icons.radio_button_unchecked),
                          onTap: () {
                            setState(() {
                              selectedAdmin = isSelected ? null : admin;
                            });
                          },
                        ),
                      );
                    },
                  ),
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
              onPressed: selectedAdmin == null
                  ? null
                  : () async {
                      try {
                        await userManagementProvider.assignUserToStore(
                          selectedAdmin!['id'],
                          store['id'],
                        );
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${selectedAdmin!['full_name'] ?? selectedAdmin!['username']} assigned to ${store['name']} successfully',
                            ),
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error assigning admin: $e')),
                        );
                      }
                    },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleStoreStatus(Map<String, dynamic> store) async {
    final newStatus = !(store['is_active'] ?? true);
    try {
      await context.read<StoreProvider>().updateStore(
        store['id'],
        {'is_active': newStatus},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Store ${newStatus ? 'activated' : 'deactivated'} successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating store status: $e')),
      );
    }
  }

  Future<void> _confirmBulkToggleStatus(bool activate) async {
    final action = activate ? 'activate' : 'deactivate';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: PrimaryDialogTitle(
            title: '${action[0].toUpperCase()}${action.substring(1)} Stores'),
        content: Text(
            'Are you sure you want to $action ${_selectedStoreIds.length} selected stores?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          PrimaryButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _isBulkActionLoading = true);
    try {
      for (final id in _selectedStoreIds.toList()) {
        await context
            .read<StoreProvider>()
            .updateStore(id, {'is_active': activate});
      }
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bulk status update completed')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error performing bulk update: $e')));
    } finally {
      setState(() {
        _isBulkActionLoading = false;
        _selectedStoreIds.clear();
      });
    }
  }

  Future<void> _confirmBulkDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Delete Stores'),
        content: Text(
            'Are you sure you want to permanently delete ${_selectedStoreIds.length} selected stores? This action cannot be undone.'),
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
    setState(() => _isBulkActionLoading = true);
    try {
      for (final id in _selectedStoreIds.toList()) {
        await context.read<StoreProvider>().deleteStore(id);
      }
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected stores deleted')));
    } on UnauthorizedException catch (_) {
      // Session expired or invalid credentials — clear session and force login
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Session expired. Please sign in again.')));
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      return; // user redirected; skip final clearing
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error deleting stores: $e')));
    } finally {
      setState(() {
        _isBulkActionLoading = false;
        _selectedStoreIds.clear();
      });
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedStoreIds.clear();
    });
  }

  void _showDeleteConfirmation(
      BuildContext context, Map<String, dynamic> store) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Delete Store'),
        content: Text(
            'Are you sure you want to delete "${store['name']}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _deleteStore(context, store),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteStore(BuildContext context, Map<String, dynamic> store) async {
    try {
      await context.read<StoreProvider>().deleteStore(store['id']);
      Navigator.of(context).pop(); // Close confirmation dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Store deleted successfully')),
      );
    } on UnauthorizedException catch (_) {
      // Session expired or invalid credentials — clear session and force login
      Navigator.of(context).pop(); // Close confirmation dialog
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Session expired. Please sign in again.')));
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting store: $e')),
      );
    }
  }
}
