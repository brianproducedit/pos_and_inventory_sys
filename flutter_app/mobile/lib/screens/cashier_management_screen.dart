import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/user_management_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/widgets/primary_dialog.dart';

class CashierManagementScreen extends StatefulWidget {
  const CashierManagementScreen({super.key});

  @override
  State<CashierManagementScreen> createState() =>
      _CashierManagementScreenState();
}

class _CashierManagementScreenState extends State<CashierManagementScreen> {
  // Bulk selection state for cashiers
  final Set<int> _selectedCashierIds = {};
  bool _isBulkActionLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    debugPrint('CashierManagementScreen: _loadData start');
    final userManagementProvider = context.read<UserManagementProvider>();
    final storeProvider = context.read<StoreProvider>();

    // Ensure store provider is initialized first so server-declared "All Stores"
    // selection is restored before we load users/stores.
    try {
      if (!storeProvider.isInitialized) {
        unawaited(storeProvider.initialize());
      }
    } catch (e) {
      debugPrint('CashierManagement: store init skipped: $e');
    }

    // Provide store provider to user management so it can filter and listen
    userManagementProvider.setStoreProvider(storeProvider);

    // Load users in background to avoid blocking UI init; tests often don't
    // need synchronous completion and this avoids pumpAndSettle hanging.
    unawaited(userManagementProvider.loadUsers());

    // Load stores for superadmin to show store names (background)
    if (context.read<AuthProvider>().role == 'superadmin') {
      unawaited(storeProvider.loadStores());
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userManagementProvider = context.watch<UserManagementProvider>();
    final storeProvider = context.watch<StoreProvider>();

    // Only admin and superadmin can access this screen
    if (authProvider.role != 'admin' && authProvider.role != 'superadmin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('You do not have permission to access this screen.'),
        ),
      );
    }

    // Filter cashiers based on role
    final cashiers = authProvider.role == 'superadmin'
        ? userManagementProvider.cashiers // Superadmin sees all cashiers
        : userManagementProvider.cashiers
            .where((cashier) => cashier['store_id'] == authProvider.storeId)
            .toList(); // Admin sees only cashiers from their store

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashier Management'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StoreIndicator(store: storeProvider.currentStore),
          ),
        ),
        actions: [
          // Mirror Admin screen: use quick action for switching stores
          if (authProvider.role == 'superadmin' || authProvider.role == 'admin')
            const StoreQuickAction(),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateCashierDialog(context),
          ),
        ],
      ),
      bottomNavigationBar:
          const AppBottomNav(currentRoute: '/cashier_management'),
      body: userManagementProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : cashiers.isEmpty
              ? const Center(
                  child: Text('No cashiers found. Create your first cashier.'),
                )
              : Column(
                  children: [
                    // Bulk action bar (shows when one or more cashiers selected)
                    if (_selectedCashierIds.isNotEmpty)
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
                                    '${_selectedCashierIds.length} selected',
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

                                        // Select-all
                                        Builder(builder: (context) {
                                          final visibleIds = cashiers
                                              .where((c) => c['id'] != null)
                                              .map((c) => c['id'] as int)
                                              .toList();
                                          final allSelected =
                                              visibleIds.isNotEmpty &&
                                                  visibleIds.every((id) =>
                                                      _selectedCashierIds
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
                                                        _selectedCashierIds
                                                            .clear();
                                                      } else {
                                                        _selectedCashierIds
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
                                          final selected = cashiers
                                              .where((c) =>
                                                  c['id'] != null &&
                                                  _selectedCashierIds
                                                      .contains(c['id']))
                                              .toList();
                                          final hasInactive = selected.any(
                                              (c) => c['is_active'] != true);
                                          final hasActive = selected.any(
                                              (c) => c['is_active'] == true);

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
                                            transitionBuilder: (child,
                                                    animation) =>
                                                ScaleTransition(
                                                    scale: animation,
                                                    child: FadeTransition(
                                                        opacity: animation,
                                                        child: child)),
                                            child: IconButton(
                                              key: ValueKey<int>(
                                                  toggleIcon.codePoint),
                                              tooltip: tooltip,
                                              onPressed: _isBulkActionLoading
                                                  ? null
                                                  : () =>
                                                      _confirmBulkToggleCashierStatus(
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
                                                  _confirmBulkDeleteCashiers(),
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
                                              : _clearCashierSelection,
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
                        itemCount: cashiers.length,
                        itemBuilder: (context, index) {
                          final cashier = cashiers[index];
                          final id = cashier['id'] as int?;
                          final isSelected =
                              id != null && _selectedCashierIds.contains(id);

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: id == null
                                  ? CircleAvatar(
                                      backgroundColor:
                                          cashier['is_active'] == true
                                              ? Colors.green
                                              : Colors.grey,
                                      child: Icon(
                                          cashier['is_active'] == true
                                              ? Icons.check
                                              : Icons.close,
                                          color: Colors.white),
                                    )
                                  : Checkbox(
                                      value: isSelected,
                                      onChanged: (v) => setState(() {
                                        if (v == true) {
                                          _selectedCashierIds.add(id);
                                        } else {
                                          _selectedCashierIds.remove(id);
                                        }
                                      }),
                                    ),
                              title: Text(
                                  cashier['full_name'] ?? cashier['username']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Username: ${cashier['username']}'),
                                  Text(
                                      'Status: ${cashier['is_active'] == true ? 'Active' : 'Inactive'}'),
                                  if (authProvider.role == 'superadmin') ...[
                                    Text(
                                        'Store: ${_getStoreName(cashier['store_id'], storeProvider.stores)}'),
                                  ],
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) =>
                                    _handleCashierAction(value, cashier),
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit Cashier')),
                                  const PopupMenuItem(
                                      value: 'toggle_status',
                                      child: Text('Toggle Status')),
                                  const PopupMenuItem(
                                      value: 'reset_password',
                                      child: Text('Reset Password')),
                                  const PopupMenuItem(
                                      value: 'deactivate',
                                      child: Text('Deactivate Cashier')),
                                ],
                              ),
                              onTap: () {
                                if (_selectedCashierIds.isNotEmpty &&
                                    id != null) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedCashierIds.remove(id);
                                    } else {
                                      _selectedCashierIds.add(id);
                                    }
                                  });
                                  return;
                                }

                                _showEditCashierDialog(context, cashier);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  void _showCreateCashierDialog(BuildContext context) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final fullNameController = TextEditingController();
    int? selectedStoreId =
        context.read<AuthProvider>().user?.storeId; // Default to user's store

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const PrimaryDialogTitle(title: 'Create New Cashier'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrimaryTextField(
                  controller: usernameController,
                  label: 'Username',
                  hint: 'Enter cashier username',
                ),
                const SizedBox(height: 16),
                PrimaryTextField(
                  controller: passwordController,
                  label: 'Password',
                  hint: 'Enter cashier password',
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                PrimaryTextField(
                  controller: fullNameController,
                  label: 'Full Name',
                  hint: 'Enter cashier full name',
                ),
                if (context.read<AuthProvider>().role == 'superadmin') ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedStoreId,
                    decoration: const InputDecoration(
                      labelText: 'Assign to Store',
                      hintText: 'Select a store',
                    ),
                    items: context.read<StoreProvider>().stores.map((store) {
                      final name =
                          (store['name'] ?? 'Unnamed Store').toString();
                      return DropdownMenuItem<int>(
                        value: store['id'],
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedStoreId = value;
                      });
                    },
                  ),
                ],
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
                    fullNameController.text.isEmpty ||
                    selectedStoreId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill all fields'),
                    ),
                  );
                  return;
                }

                try {
                  await context.read<UserManagementProvider>().createUser({
                    'username': usernameController.text,
                    'password': passwordController.text,
                    'full_name': fullNameController.text,
                    'role': 'cashier',
                    'store_id': selectedStoreId,
                  });

                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cashier created successfully'),
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleCashierAction(String action, Map<String, dynamic> cashier) {
    switch (action) {
      case 'edit':
        _showEditCashierDialog(context, cashier);
        break;
      case 'toggle_status':
        _toggleCashierStatus(cashier);
        break;
      case 'reset_password':
        _showResetPasswordDialog(context, cashier);
        break;
      case 'deactivate':
        _showDeactivateCashierDialog(context, cashier);
        break;
    }
  }

  void _showEditCashierDialog(
      BuildContext context, Map<String, dynamic> cashier) {
    final fullNameController =
        TextEditingController(text: cashier['full_name']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Edit Cashier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryTextField(
                controller: fullNameController,
                label: 'Full Name',
                hint: 'Enter cashier full name',
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

              try {
                await context.read<UserManagementProvider>().updateUser(
                  cashier['id'],
                  {
                    'full_name': fullNameController.text,
                  },
                );

                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cashier updated successfully'),
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
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _toggleCashierStatus(Map<String, dynamic> cashier) async {
    try {
      await context.read<UserManagementProvider>().updateUser(
        cashier['id'],
        {'is_active': !(cashier['is_active'] ?? true)},
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cashier ${(cashier['is_active'] ?? true) ? 'deactivated' : 'activated'} successfully',
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

  void _showResetPasswordDialog(
      BuildContext context, Map<String, dynamic> cashier) {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Reset Cashier Password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryTextField(
                controller: newPasswordController,
                label: 'New Password',
                hint: 'Enter new password',
                obscureText: true,
              ),
              PrimaryTextField(
                controller: confirmPasswordController,
                label: 'Confirm Password',
                hint: 'Confirm new password',
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
              if (newPasswordController.text.isEmpty ||
                  confirmPasswordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please fill all fields'),
                  ),
                );
                return;
              }

              if (newPasswordController.text !=
                  confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Passwords do not match'),
                  ),
                );
                return;
              }

              try {
                await context.read<UserManagementProvider>().updateUser(
                  cashier['id'],
                  {'password': newPasswordController.text},
                );

                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password reset successfully'),
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
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _showDeactivateCashierDialog(
      BuildContext context, Map<String, dynamic> cashier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Deactivate Cashier'),
        content: Text(
          'Are you sure you want to deactivate cashier "${cashier['full_name'] ?? cashier['username']}"? This action will deactivate the cashier account.',
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
                    .deactivateUser(cashier['id']);

                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cashier deactivated successfully'),
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
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBulkToggleCashierStatus(bool activate) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Change Cashier Status'),
        content: Text(
            'Are you sure you want to ${activate ? 'activate' : 'deactivate'} ${_selectedCashierIds.length} selected cashiers?'),
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

    setState(() => _isBulkActionLoading = true);
    try {
      for (final id in _selectedCashierIds.toList()) {
        await context
            .read<UserManagementProvider>()
            .updateUser(id, {'is_active': activate});
      }
      if (context.mounted) {
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
        _selectedCashierIds.clear();
      });
    }
  }

  Future<void> _confirmBulkDeleteCashiers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Delete Cashiers'),
        content: Text(
            'Are you sure you want to permanently delete ${_selectedCashierIds.length} selected cashiers? This action cannot be undone.'),
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
      for (final id in _selectedCashierIds.toList()) {
        await context.read<UserManagementProvider>().hardDeleteUser(id);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected cashiers deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting cashiers: $e')));
      }
    } finally {
      setState(() {
        _isBulkActionLoading = false;
        _selectedCashierIds.clear();
      });
    }
  }

  void _clearCashierSelection() {
    setState(() => _selectedCashierIds.clear());
  }

  String _getStoreName(int? storeId, List<Map<String, dynamic>> stores) {
    if (storeId == null) return 'No Store Assigned';
    final store = stores.firstWhere(
      (store) => store['id'] == storeId,
      orElse: () => {'name': 'Unknown Store'},
    );
    return store['name'] ?? 'Unknown Store';
  }
}
