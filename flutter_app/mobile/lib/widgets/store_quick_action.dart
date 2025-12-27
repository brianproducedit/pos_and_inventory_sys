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
    await storeProvider.loadAvailableStores();
    setState(() => _isLoading = false);

    final stores = storeProvider.availableStores;
    if (stores.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No stores available')));
      return;
    }

    // Insert an 'All Stores' option at the top for admins and superadmins
    final role = context.read<AuthProvider>().role;
    final canViewAll = role == 'superadmin' || role == 'admin';
    final dialogStores = <Map<String, dynamic>>[];
    // Avoid duplicate 'All Stores' entries in case backend already provides one
    final hasAllFromBackend =
        stores.any((s) => s['id'] == 0 || s['is_all'] == true);
    if (canViewAll && !hasAllFromBackend) {
      dialogStores.add({'id': 0, 'name': 'All Stores', 'is_all': true});
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
      final fromStoreId = storeProvider.currentStore?['id'];
      final stopwatch = Stopwatch()..start();

      final success = await storeProvider.switchStore(selected);
      stopwatch.stop();

      if (success) {
        // Refresh analytics (null -> all stores)
        analyticsProvider.loadAnalytics(
            storeId: selected['id'] == 0 ? null : selected['id']);
        analyticsProvider.trackEvent('store_quick_switch', {
          'userId': authProvider.user?.id,
          'fromStoreId': fromStoreId,
          'toStoreId': selected['id'],
          'durationMs': stopwatch.elapsedMilliseconds,
        });
      }
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
      tooltip: 'Quick Switch Store',
      onPressed: () => _openPicker(context),
    );
  }
}
