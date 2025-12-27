import 'package:flutter/material.dart';
import 'package:mobile/ui/sync_conflict_dialog.dart';
import 'package:provider/provider.dart';
import '../db/app_database.dart';
import '../sync/sync_service.dart';
import 'sync_conflict_dialog.dart';

class SyncDemoScreen extends StatefulWidget {
  final SyncService? syncServiceOverride;
  const SyncDemoScreen({Key? key, this.syncServiceOverride}) : super(key: key);

  @override
  State<SyncDemoScreen> createState() => _SyncDemoScreenState();
}

class _SyncDemoScreenState extends State<SyncDemoScreen> {
  late AppDatabase db;
  late SyncService syncService;
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    db = Provider.of<AppDatabase>(context);
    syncService = widget.syncServiceOverride ?? SyncService(db);
  }

  Future<void> _createOffline() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text) ?? 0.0;
    if (name.isEmpty) return;
    final clientId =
        await syncService.enqueueCreateProduct(name: name, price: price);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created offline (id: $clientId)')));
    _nameCtrl.clear();
    _priceCtrl.clear();
    setState(() {});
  }

  Future<void> _syncNow() async {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Syncing...')));
    try {
      final token = null; // TODO: fetch JWT from secure storage
      final res = await syncService.pushChanges(jwtToken: token);
      final conflicts = (res['conflicts'] as List);
      if (conflicts.isNotEmpty) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Sync Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Product name')),
            TextField(
                controller: _priceCtrl,
                decoration: const InputDecoration(labelText: 'Price')),
            const SizedBox(height: 8),
            Row(children: [
              ElevatedButton(
                  onPressed: _createOffline,
                  child: const Text('Create Offline')),
              const SizedBox(width: 12),
              ElevatedButton(
                  onPressed: _syncNow, child: const Text('Sync Now')),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<Product>>(
                future: db.getAllProducts(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final products = snapshot.data!;
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
