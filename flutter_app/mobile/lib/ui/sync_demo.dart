import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile/config/env.dart';
import 'package:mobile/db/app_database.dart';
import 'package:mobile/ui/sync_conflict_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/app_database.dart' as app_db;
import '../sync/sync_service.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import 'package:mobile/data/providers.dart';
import 'package:mobile/domain/models/product.dart' as domain_product;

class SyncDemoScreen extends ConsumerStatefulWidget {
  final SyncService? syncServiceOverride;
  const SyncDemoScreen({Key? key, this.syncServiceOverride}) : super(key: key);

  @override
  ConsumerState<SyncDemoScreen> createState() => _SyncDemoScreenState();
}

class _SyncDemoScreenState extends ConsumerState<SyncDemoScreen> {
  late app_db.AppDatabase db;
  late SyncService syncService;
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  int _conflictCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    db = Provider.of<AppDatabase>(context);
    syncService =
        widget.syncServiceOverride ?? SyncService(db, serverBase: Env.baseUrl);

    // Load last conflict count persisted by SyncService
    SharedPreferences.getInstance().then((prefs) {
      final c = prefs.getInt('sync_conflict_count') ?? 0;
      setState(() {
        _conflictCount = c;
      });
    });
  }

  Future<void> _createOffline() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text) ?? 0.0;
    if (name.isEmpty) return;
    try {
      final clientId =
          await syncService.enqueueCreateProduct(name: name, price: price);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created offline (id: $clientId)')));
      _nameCtrl.clear();
      _priceCtrl.clear();
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Create failed: ${e.toString()}')));
    }
  }

  Future<void> _openStorePicker(BuildContext context) async {
    final storeProvider = context.read<StoreProvider>();
    setState(() {});

    // Ensure stores are loaded
    await storeProvider.loadAvailableStores();
    final stores = storeProvider.availableStores;
    if (stores.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No stores available')));
      return;
    }

    // Insert an 'All Stores' option for admins/superadmins
    final role = context.read<AuthProvider>().role;
    final canViewAll = role == 'superadmin' || role == 'admin';
    final dialogStores = <Map<String, dynamic>>[];
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
      final success = await storeProvider.switchStore(selected);
      if (success) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Switched to ${selected['name']}')));
      }
    }
  }

  Future<void> _syncNow() async {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Syncing...')));
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final res = await syncService.pushChanges(jwtToken: token);
      final conflicts = (res['conflicts'] as List);
      if (conflicts.isNotEmpty) {
        // Persist conflict information for UI and quick resolution
        final prefs = await SharedPreferences.getInstance();
        prefs.setInt('sync_conflict_count', conflicts.length);
        prefs.setString('last_sync_conflicts', jsonEncode(conflicts));
        setState(() {
          _conflictCount = conflicts.length;
        });

        final first = conflicts.first as Map<String, dynamic>;
        final serverData = first['server_data'] as Map<String, dynamic>? ?? {};
        // Show merge dialog
        await showDialog<void>(
            context: context,
            builder: (ctx) => SyncConflictDialog(
                  serverData: serverData,
                  onAcceptServer: () async {
                    Navigator.of(ctx).pop();
                    // For now, accept server means pulling changes
                    await syncService.pullChanges(
                        since: DateTime.fromMillisecondsSinceEpoch(0));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Accepted server version')));
                    setState(() {});
                  },
                  onForce: () async {
                    Navigator.of(ctx).pop();
                    // Force update as admin (in real app pass JWT)
                    try {
                      await syncService.forceUpdate(
                          resourceType: first['resource_type'] as String,
                          id: first['id'] as int,
                          data: {});
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Forced update applied')));
                      setState(() {});
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Force failed: $e')));
                    }
                  },
                ));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Sync completed')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final storeProvider = Provider.of<StoreProvider>(context);
    final currentStore = storeProvider.currentStore;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Demo'),
        actions: const [StoreQuickAction()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current store display + quick select
            Card(
              child: ListTile(
                leading: const Icon(Icons.store),
                title: Text(currentStore == null
                    ? 'Current store: All Stores / None selected'
                    : 'Current store: ${currentStore['name']}'),
                trailing: TextButton(
                    onPressed: () => _openStorePicker(context),
                    child: const Text('Select')),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Product name')),
            TextField(
                controller: _priceCtrl,
                decoration: const InputDecoration(labelText: 'Price')),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ElevatedButton(
                    onPressed: _createOffline,
                    child: const Text('Create Offline (legacy)')),
                const SizedBox(width: 12),
                ElevatedButton(
                    onPressed: () async {
                      // Use the new ProductRepository via Riverpod to create a product in the new local DB
                      final repo = ref.read(productRepositoryProvider);
                      final name = _nameCtrl.text.trim();
                      final price = double.tryParse(_priceCtrl.text) ?? 0.0;
                      if (name.isEmpty) return;
                      try {
                        final id = await repo.addProduct(
                          domain_product.Product(
                              name: name,
                              sku:
                                  'SKU-${DateTime.now().millisecondsSinceEpoch}',
                              price: price,
                              stockQuantity: 0),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Created via repo (id: $id)')));
                        _nameCtrl.clear();
                        _priceCtrl.clear();
                        setState(() {});
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Repo create failed: $e')));
                      }
                    },
                    child: const Text('Create Offline (repo)')),
                const SizedBox(width: 12),
                ElevatedButton(
                    onPressed: _syncNow, child: const Text('Sync Now')),
                const SizedBox(width: 12),
                ElevatedButton(
                    onPressed: () async {
                      // Trigger initial server snapshot fetch and seed local DB
                      try {
                        final tokenPrefs =
                            await SharedPreferences.getInstance();
                        final token = tokenPrefs.getString('access_token');
                        if (token == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'No token available - log in first')));
                          return;
                        }

                        final api = ref.read(postgresApiServiceProvider);
                        final dbHelper = ref.read(databaseHelperProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Fetching initial data...')));
                        await api.fetchInitialDataAndSeedDB(
                            token: token, dbHelper: dbHelper);
                        final rows =
                            await (await dbHelper.database).query('products');
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Seed completed: ${rows.length} products')));
                        setState(() {});
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Seed failed: $e')));
                      }
                    },
                    child: const Text('Seed DB (initial fetch)')),
                const SizedBox(width: 12),
                ElevatedButton(
                    onPressed: () async {
                      final storeProvider = context.read<StoreProvider>();
                      // Let user pick a store (this will switch current store)
                      await _openStorePicker(context);
                      final cs = storeProvider.currentStore;
                      if (cs == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No store selected')));
                        return;
                      }
                      try {
                        final fixed =
                            await syncService.attachStoreToPendingCreates(
                                storeId: cs['id'] as int);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Fixed $fixed pending creates')));
                        setState(() {});
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Fix failed: $e')));
                      }
                    },
                    child: const Text('Fix pending creates')),
              ]),
            ),
            const SizedBox(height: 12),
            if (_conflictCount > 0)
              Card(
                color: Colors.amber[50],
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text('Conflicts: $_conflictCount'),
                  trailing: TextButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        final raw = prefs.getString('last_sync_conflicts');
                        if (raw == null) return;
                        final list = (jsonDecode(raw) as List)
                            .cast<Map<String, dynamic>>();
                        if (list.isEmpty) return;
                        final first = list.first;
                        final serverData =
                            first['server_data'] as Map<String, dynamic>? ?? {};
                        await showDialog<void>(
                            context: context,
                            builder: (ctx) => SyncConflictDialog(
                                  serverData: serverData,
                                  onAcceptServer: () async {
                                    Navigator.of(ctx).pop();
                                    await syncService.pullChanges(
                                        since:
                                            DateTime.fromMillisecondsSinceEpoch(
                                                0));
                                    setState(() {
                                      _conflictCount = 0;
                                    });
                                    final prefs2 =
                                        await SharedPreferences.getInstance();
                                    prefs2.remove('last_sync_conflicts');
                                    prefs2.setInt('sync_conflict_count', 0);
                                  },
                                  onForce: () async {
                                    Navigator.of(ctx).pop();
                                    try {
                                      await syncService.forceUpdate(
                                          resourceType:
                                              first['resource_type'] as String,
                                          id: first['id'] as int,
                                          data: {});
                                      setState(() {
                                        _conflictCount = 0;
                                      });
                                      final prefs2 =
                                          await SharedPreferences.getInstance();
                                      prefs2.remove('last_sync_conflicts');
                                      prefs2.setInt('sync_conflict_count', 0);
                                    } catch (e) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content:
                                                  Text('Force failed: $e')));
                                    }
                                  },
                                ));
                      },
                      child: const Text('Resolve')),
                ),
              ),
            Expanded(
              child: FutureBuilder<List<app_db.Product>>(
                future: db.getAllProducts(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final products = snapshot.data! as List<app_db.Product>;
                  if (products.isEmpty)
                    return const Center(child: Text('No products'));
                  return ListView.builder(
                    itemCount: products.length,
                    itemBuilder: (context, i) {
                      final p = products[i];
                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text(
                            'Price: ${p.price} | Stock: ${p.stockQuantity} | clientId: ${p.clientId ?? '-'}'),
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
