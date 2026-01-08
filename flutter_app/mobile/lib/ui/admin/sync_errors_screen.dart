import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/domain/models/sync_error.dart';

class SyncErrorsScreen extends ConsumerWidget {
  final List<SyncError>? testErrors;

  const SyncErrorsScreen({Key? key, this.testErrors}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (testErrors != null) {
      final errors = testErrors!;
      if (errors.isEmpty) {
        return Scaffold(
            appBar: AppBar(title: const Text('Sync Errors')),
            body: const Center(child: Text('No errors')));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Sync Errors')),
        body: ListView.builder(
          itemCount: errors.length,
          itemBuilder: (context, i) {
            final e = errors[i];
            return ListTile(
              title: Text('${e.tableName} #${e.rowId}'),
              subtitle: Text(e.error),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('reenqueue-${e.id}'),
                    icon: const Icon(Icons.replay),
                    onPressed: () async {
                      final repo = ref.read(syncRepositoryProvider);
                      await repo.reenqueueQueueItem(e.queueId);
                      ref.invalidate(syncErrorsProvider);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Re-enqueued for retry')));
                    },
                  ),
                  IconButton(
                    key: Key('clear-${e.id}'),
                    icon: const Icon(Icons.clear),
                    onPressed: () async {
                      final repo = ref.read(syncRepositoryProvider);
                      await repo.clearError(e.id!);
                      ref.invalidate(syncErrorsProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Error cleared')));
                    },
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    final async = ref.watch(syncErrorsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sync Errors')),
      body: async.when(
        data: (errors) {
          // Debug print to help tests diagnose if provider delivered data
          // ignore: avoid_print
          print('SYNC ERRORS: data count=${errors.length}');
          if (errors.isEmpty) return const Center(child: Text('No errors'));
          return ListView.builder(
            itemCount: errors.length,
            itemBuilder: (context, i) {
              final e = errors[i];
              return ListTile(
                title: Text('${e.tableName} #${e.rowId}'),
                subtitle: Text(e.error),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('reenqueue-${e.id}'),
                      icon: const Icon(Icons.replay),
                      onPressed: () async {
                        final repo = ref.read(syncRepositoryProvider);
                        await repo.reenqueueQueueItem(e.queueId);
                        ref.invalidate(syncErrorsProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Re-enqueued for retry')));
                      },
                    ),
                    IconButton(
                      key: Key('clear-${e.id}'),
                      icon: const Icon(Icons.clear),
                      onPressed: () async {
                        final repo = ref.read(syncRepositoryProvider);
                        await repo.clearError(e.id!);
                        ref.invalidate(syncErrorsProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Error cleared')));
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () {
          // ignore: avoid_print
          print('SYNC ERRORS: loading');
          return const Center(child: CircularProgressIndicator());
        },
        error: (err, st) {
          // ignore: avoid_print
          print('SYNC ERRORS: error $err');
          return Center(child: Text('Error: $err'));
        },
      ),
    );
  }
}
