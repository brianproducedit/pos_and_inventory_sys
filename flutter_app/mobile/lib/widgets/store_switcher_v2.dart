import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/store_provider.dart';
import '../providers/analytics_provider.dart';

class StoreSwitcher extends StatefulWidget {
  const StoreSwitcher({super.key});

  @override
  State<StoreSwitcher> createState() => _StoreSwitcherState();
}

class _StoreSwitcherState extends State<StoreSwitcher> {
  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final storeProvider = context.watch<StoreProvider>();
    final analyticsProvider = context.watch<AnalyticsProvider>();

    // Show for superadmin and admin roles
    final userRole = authProvider.role;
    if (userRole != 'superadmin' && userRole != 'admin') {
      return const SizedBox.shrink();
    }

    final myStores = storeProvider.myStores;
    final currentStore = storeProvider.currentStore;

    final canViewAll = userRole == 'superadmin' || userRole == 'admin';

    // If the user has no stores and cannot view all stores, hide the switcher
    if (myStores.isEmpty && !canViewAll) {
      return const SizedBox.shrink();
    }

    // Remove duplicates based on ID to prevent assertion errors
    final uniqueStores = <Map<String, dynamic>>[];
    final seenIds = <int>{};
    for (final store in myStores) {
      final id = store['id'] is int
          ? store['id'] as int
          : int.tryParse(store['id']?.toString() ?? '') ?? -1;
      if (!seenIds.contains(id) && id != -1) {
        seenIds.add(id);
        uniqueStores.add(store);
      }
    }

    // Build menu list, optionally including 'All Stores' at the top for admin/superadmin
    final menuStores = <Map<String, dynamic>>[];
    if (canViewAll) {
      menuStores.add(
          {'id': 0, 'name': 'All Stores', 'is_active': true, 'is_all': true});
    }
    menuStores.addAll(uniqueStores);

    // Find the current store by ID to ensure object reference matches. If currentStore is null
    // and the user can view all stores, display the All Stores option as selected. Use
    // defensive orElse handlers to avoid StateError when elements are not found.

    // If there are no menu stores (shouldn't happen), hide the widget.
    if (menuStores.isEmpty) return const SizedBox.shrink();

    Map<String, dynamic> selectedStore = menuStores.first;

    if (currentStore != null) {
      selectedStore = menuStores.firstWhere(
        (store) => store['id'] == currentStore['id'],
        orElse: () => menuStores.firstWhere((s) => s['id'] != 0,
            orElse: () => menuStores.first),
      );

      // If the resulting selected store is the placeholder All Stores but the
      // provider indicates a specific store, attempt to switch to a valid store
      if (selectedStore['id'] == 0 && currentStore['id'] != 0) {
        final fallback = menuStores.firstWhere((s) => s['id'] != 0,
            orElse: () => menuStores.first);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Only switch if provider is not already set to the fallback store
          final cs = storeProvider.currentStore;
          final already = cs != null && cs['id'] == fallback['id'];
          if (!already) storeProvider.switchStore(fallback);
        });
        selectedStore = fallback;
      }
    } else if (canViewAll) {
      // Select All Stores option (first entry)
      selectedStore = menuStores.first;
      // don't auto-switch to All Stores on startup; leave provider currentStore null
    } else {
      selectedStore = menuStores.firstWhere((s) => s['id'] != 0,
          orElse: () => menuStores.first);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Only switch if provider does not already indicate this store
        final cs = storeProvider.currentStore;
        final already = cs != null && cs['id'] == selectedStore['id'];
        if (!already) storeProvider.switchStore(selectedStore);
      });
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Store Icon/Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.store,
              color: Theme.of(context).colorScheme.onPrimary,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),

          // Store Info
          Flexible(
            fit: FlexFit.loose,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Store Name
                Text(
                  (selectedStore['name'] ?? 'Unnamed Store').toString(),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
                // Store Location (if available)
                if (selectedStore['location'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    (selectedStore['location'] ?? '').toString(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Dropdown Button
          storeProvider.isSwitchingStore
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                )
              : PopupMenuButton<Map<String, dynamic>>(
                  onSelected: (Map<String, dynamic> newStore) async {
                    await _handleStoreSwitch(
                        context, storeProvider, analyticsProvider, newStore);
                  },
                  itemBuilder: (BuildContext context) {
                    return menuStores.map((store) {
                      final isActive = store['is_active'] == true;
                      final isSelected = store['id'] == selectedStore['id'];

                      return PopupMenuItem<Map<String, dynamic>>(
                        value: store,
                        child: Row(
                          children: [
                            // Store Icon
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.1)
                                    : Theme.of(context)
                                        .colorScheme
                                        .error
                                        .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                  store['id'] == 0
                                      ? Icons.language
                                      : Icons.store,
                                  size: 14,
                                  color: isActive
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.error),
                            ),
                            const SizedBox(width: 8),

                            // Store Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          (store['name'] ?? 'Unnamed Store')
                                              .toString(),
                                          style: TextStyle(
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: isActive
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.5),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isSelected) ...[
                                        const SizedBox(width: 4),
                                        Icon(Icons.check,
                                            size: 16,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                      ],
                                    ],
                                  ),
                                  if (store['location'] != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      (store['location'] ?? '').toString(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.6)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (!isActive) ...[
                                    const SizedBox(height: 2),
                                    Text('Inactive',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                            fontSize: 10,
                                            fontStyle: FontStyle.italic)),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Switch',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _handleStoreSwitch(
    BuildContext context,
    StoreProvider storeProvider,
    AnalyticsProvider analyticsProvider,
    Map<String, dynamic> newStore,
  ) async {
    final currentStore = storeProvider.currentStore;

    // If switching to the same store, do nothing
    if (currentStore != null && currentStore['id'] == newStore['id']) {
      return;
    }

    // Show confirmation dialog
    final shouldSwitch = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Switch Store'),
          content: Text(newStore['id'] == 0
              ? 'Switch to All Stores?\n\nThis will reload aggregated data for all stores.'
              : 'Switch to store: ${newStore['name']}${newStore['location'] != null ? ' (' + newStore['location'] + ')' : ''}?\n\nThis will reload data for the selected store.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Switch')),
          ],
        );
      },
    );

    if (shouldSwitch == true) {
      try {
        final success = await storeProvider.switchStore(newStore);

        if (success) {
          // Reload analytics for the new store (null storeId => all stores)
          analyticsProvider.loadAnalytics(
              storeId: newStore['id'] == 0 ? null : newStore['id']);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(newStore['id'] == 0 ? Icons.language : Icons.store,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(newStore['id'] == 0
                            ? 'Switched to: All Stores'
                            : 'Switched to store: ${(newStore['name'] ?? 'Store').toString()}')),
                  ],
                ),
                duration: const Duration(seconds: 3),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    storeProvider.errorMessage ?? 'Failed to switch store'),
                backgroundColor: Theme.of(context).colorScheme.error));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error switching store: $e'),
              backgroundColor: Theme.of(context).colorScheme.error));
        }
      }
    }
  }
}
