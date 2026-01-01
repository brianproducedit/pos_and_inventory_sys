import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/analytics_provider.dart';

class StoreQuickAction extends StatefulWidget {
  const StoreQuickAction({super.key});

  @override
  State<StoreQuickAction> createState() => _StoreQuickActionState();
}

class _StoreQuickActionState extends State<StoreQuickAction> {
  bool _isLoading = false;

  Future<void> _openPicker(BuildContext context) async {
    final storeProvider = context.read<StoreProvider>();
    setState(() => _isLoading = true);
    await storeProvider.loadMyStores();
    setState(() => _isLoading = false);

    final stores = storeProvider.myStores;

    // Determine role & whether All Stores should be shown
    final role = context.read<AuthProvider>().role;
    final isSuper = role == 'superadmin';

    // Only superadmins can see the All Stores option
    final showAllOption = isSuper;

    // If there are no stores and the user is not allowed to view All Stores, inform them
    if (stores.isEmpty && !showAllOption) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No stores available')));
      return;
    }

    final dialogStores = <Map<String, dynamic>>[];
    // Avoid duplicate 'All Stores' entries in case backend already provides one
    final hasAllFromBackend =
        stores.any((s) => s['id'] == 0 || s['is_all'] == true);
    if (showAllOption && !hasAllFromBackend) {
      dialogStores.add({
        'id': 0,
        'name': 'All Stores',
        'is_all': true,
      });
    }
    dialogStores.addAll(stores);

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Switch Store'),
        children: dialogStores.map((s) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(s),
            child: Text(s['name']),
          );
        }).toList(),
      ),
    );

    if (selected != null) {
      final analyticsProvider = context.read<AnalyticsProvider>();
      final authProvider = context.read<AuthProvider>();
      final fromStoreId = storeProvider.currentStore == null
          ? null
          : (storeProvider.currentStore!['id'] is int
              ? storeProvider.currentStore!['id'] as int
              : int.tryParse(
                  storeProvider.currentStore!['id']?.toString() ?? ''));
      final stopwatch = Stopwatch()..start();

      final success = await storeProvider.switchStore(selected);
      stopwatch.stop();

      // Parse selected id that might be a string
      final selectedId = selected['id'] is int
          ? selected['id'] as int?
          : int.tryParse(selected['id']?.toString() ?? '');

      // If switch succeeded refresh analytics for new context, otherwise show an error
      if (success) {
        analyticsProvider.loadAnalytics(
            storeId: selectedId == 0 ? null : selectedId);
      } else {
        final msg = storeProvider.errorMessage ?? 'Failed to switch store';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }

      // Always track the switch attempt with success/failure
      analyticsProvider.trackEvent('store_quick_switch', {
        'userId': authProvider.user?.id,
        'fromStoreId': fromStoreId,
        'toStoreId': selectedId,
        'durationMs': stopwatch.elapsedMilliseconds,
        'success': success,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final role = authProvider.role;

    if (role != 'superadmin' && role != 'admin') return const SizedBox.shrink();

    final iconColor = Theme.of(context).appBarTheme.foregroundColor ??
        Theme.of(context).iconTheme.color ??
        Colors.white;

    final tooltip = role == 'superadmin'
        ? 'Switch between stores (Super Admin: full access)'
        : 'Switch between assigned stores (Admin: assigned stores only)';

    return IconButton(
      icon: _isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(iconColor),
              ),
            )
          : Icon(Icons.store, color: iconColor),
      tooltip: tooltip,
      onPressed: () => _openPicker(context),
    );
  }
}
