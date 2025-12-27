import 'package:flutter/material.dart';
import 'package:mobile/services/export_service.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/receipts_provider.dart';
import 'package:mobile/widgets/receipt_card.dart';
import 'package:mobile/theme/tokens.dart';

class ReceiptsScreen extends StatelessWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ReceiptsProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Receipts')),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.receipts.isEmpty
              ? const Center(child: Text('No receipts yet'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: provider.receipts.length,
                  itemBuilder: (context, index) {
                    final r = provider.receipts[index];
                    return ReceiptCard(
                      receipt: r,
                      onPrint: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Print requested')));
                      },
                      onExport: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Export requested')));
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.print),
        label: const Text('Export All'),
        backgroundColor: AppColors.primaryBrand,
        onPressed: () async {
          final receipts = provider.receipts;
          try {
            final path =
                await DefaultExportService.instance.exportReceiptsCsv(receipts);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Exported CSV to $path')));
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Export failed: $e')));
            }
          }
        },
      ),
    );
  }
}
