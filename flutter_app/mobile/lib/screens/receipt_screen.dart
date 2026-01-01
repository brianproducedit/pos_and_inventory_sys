import 'package:flutter/material.dart';
import 'package:mobile/services/sales_service.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/services/time_service.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/widgets/primary_dialog.dart';
import 'package:mobile/data/repositories/transaction_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ReceiptScreen extends StatefulWidget {
  final int saleId;
  final int? storeId; // optional override for tests or explicit store context
  final SalesService? salesService; // optional injectable service for testing
  final TransactionRepository?
      transactionRepository; // for offline receipt generation

  const ReceiptScreen(
      {super.key,
      required this.saleId,
      this.storeId,
      this.salesService,
      this.transactionRepository});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final SalesService _salesService = SalesService();
  Map<String, dynamic>? _receiptData;
  bool _isLoading = true;
  String? _errorMessage;

  // Bluetooth printing
  List<BluetoothInfo> _devices = [];
  BluetoothInfo? _selectedDevice;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _loadReceipt();
    // Don't auto-initialize Bluetooth scanning to avoid errors when just viewing receipts
  }

  Future<void> _loadReceipt() async {
    try {
      setState(() => _isLoading = true);

      // First try offline receipt generation
      if (widget.transactionRepository != null) {
        try {
          final offlineReceipt =
              await widget.transactionRepository!.getTransaction(widget.saleId);
          if (offlineReceipt != null) {
            setState(() {
              _receiptData = offlineReceipt;
              _isLoading = false;
            });
            return; // Successfully loaded offline receipt
          }
        } catch (e) {
          // Offline receipt failed, continue to online attempt
          debugPrint('Offline receipt generation failed: $e');
        }
      }

      // If offline failed or not available, try online receipt
      // Determine store id to use for request. Precedence:
      // 1) explicit widget.storeId (injected for tests or explicit flows)
      // 2) current store from StoreProvider (if available)
      // 3) null (SalesService will fall back to persisted store id if needed)
      int? sid = widget.storeId;
      if (sid == null) {
        try {
          final sp = Provider.of<StoreProvider>(context, listen: false);
          final rawId = sp.currentStore != null ? sp.currentStore!['id'] : null;
          sid = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        } catch (e) {
          // Provider might not be available in some contexts (tests); ignore.
          sid = null;
        }
      }

      final service = widget.salesService ?? _salesService;
      final receipt = await service.getReceipt(widget.saleId, storeId: sid);
      setState(() {
        _receiptData = receipt;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load receipt: $e';
        _isLoading = false;
      });
    }
  }

  void _initBluetooth() {
    // Initialize Bluetooth scanning when needed
    // The new package doesn't require background scanning initialization
  }

  Future<void> _scanDevices() async {
    setState(() => _isScanning = true);
    try {
      final List<BluetoothInfo> devices =
          await PrintBluetoothThermal.pairedBluetooths;
      if (mounted) {
        setState(() {
          _devices = devices;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting paired devices: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  String _generateReceiptText() {
    final receipt = _receiptData!;
    final items = receipt['items'] as List<dynamic>;
    final total = receipt['total_amount'] as double;
    final paymentMethod = (receipt['payment_method'] ?? 'unknown').toString();
    final createdAt = DateTime.parse(receipt['created_at']);
    final store = receipt['store'];
    final cashier = receipt['cashier'];

    final buffer = StringBuffer();

    // Store header
    if (store != null) {
      buffer.writeln(store['name'] ?? 'Store');
      if (store['location'] != null && store['location'].isNotEmpty) {
        buffer.writeln(store['location']);
      }
      buffer.writeln('');
    }

    buffer.writeln('=== RECEIPT ===');
    buffer.writeln('Sale ID: ${receipt['id']}');
    buffer.writeln('Date: ${createdAt.toString().split('.')[0]}');

    // Cashier information
    if (cashier != null) {
      buffer.writeln(
          'Cashier: ${cashier['full_name'] ?? cashier['username'] ?? 'Unknown'}');
    }

    buffer.writeln('');
    buffer.writeln('Items:');
    buffer.writeln('-' * 30);

    for (final item in items) {
      final productName = item['product_name'] ?? 'Unknown Product';
      final quantity = item['quantity'] as int;
      final unitPrice = item['unit_price'] as double;
      final itemTotal = quantity * unitPrice;

      buffer.writeln('$productName');
      buffer.writeln(
          '  $quantity x \$${unitPrice.toStringAsFixed(2)} = \$${itemTotal.toStringAsFixed(2)}');
    }

    buffer.writeln('-' * 30);
    buffer.writeln('Total: \$${total.toStringAsFixed(2)}');
    buffer.writeln('Payment: ${paymentMethod.toUpperCase()}');
    buffer.writeln('');
    buffer.writeln('Thank you for your business!');
    buffer.writeln('================');

    return buffer.toString();
  }

  void _showPrinterSelectionDialog() {
    // Initialize Bluetooth scanning when user wants to print
    _initBluetooth();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const PrimaryDialogTitle(
                  title: 'Select Printer', textColor: AppColors.primaryBrand),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedDevice != null
                                ? 'Selected: ${_selectedDevice!.name}'
                                : 'No printer selected',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _isScanning
                              ? null
                              : () async {
                                  setState(() => _isScanning = true);
                                  await _scanDevices();
                                  setState(() => _isScanning = false);
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _devices.isEmpty
                          ? const Center(
                              child: Text(
                                  'No devices found. Tap refresh to scan.'))
                          : ListView.builder(
                              itemCount: _devices.length,
                              itemBuilder: (context, index) {
                                final device = _devices[index];
                                return ListTile(
                                  title: Text(device.name ??
                                      'Unknown Device'), // ignore: dead_null_aware_expression
                                  subtitle: Text(device.macAdress),
                                  trailing: _selectedDevice != null &&
                                          _selectedDevice!.macAdress ==
                                              device.macAdress
                                      ? const Icon(Icons.check,
                                          color: Colors.green)
                                      : null,
                                  onTap: () {
                                    setState(() => _selectedDevice = device);
                                  },
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
                ElevatedButton(
                  onPressed: _selectedDevice != null
                      ? () {
                          Navigator.of(context).pop();
                          _printReceipt();
                        }
                      : null,
                  child: const Text('Print'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          if (_receiptData != null) ...[
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Printer Settings',
              onPressed: _showPrinterSelectionDialog,
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareReceipt,
            ),
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _downloadReceipt,
            ),
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _printReceipt,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadReceipt,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_receiptData == null) {
      return const Center(child: Text('No receipt data available'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(),

              const Divider(height: 32),

              // Items
              _buildItems(),

              const Divider(height: 32),

              // Total
              _buildTotal(),

              const SizedBox(height: 24),

              // Footer
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final store = _receiptData!['store'];
    final cashier = _receiptData!['cashier'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Store Information
        if (store != null) ...[
          Text(
            store['name'] ?? 'Store',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (store['location'] != null && store['location'].isNotEmpty)
            Text(
              store['location'],
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          const SizedBox(height: 16),
        ],

        const Text(
          'RECEIPT',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),

        // Offline indicator
        if (_receiptData!['is_offline'] == true) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange[300]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.offline_bolt, size: 16, color: Colors.orange[800]),
                const SizedBox(width: 4),
                Text(
                  'Offline Receipt',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 8),
        Text(
          'Sale #${_receiptData!['sale_id']}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatDate(_receiptData!['created_at']),
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),

        // Cashier Information
        if (cashier != null) ...[
          const SizedBox(height: 8),
          Text(
            'Cashier: ${cashier['full_name'] ?? cashier['username'] ?? 'Unknown'}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildItems() {
    final items = _receiptData!['items'] as List<dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Items',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      item['product_name'] ?? 'Unknown Product',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      'x${item['quantity']}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '\$${item['unit_price']?.toStringAsFixed(2) ?? '0.00'}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '\$${item['total_price']?.toStringAsFixed(2) ?? '0.00'}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildTotal() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Total Amount:',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '\$${_receiptData!['total_amount']?.toStringAsFixed(2) ?? '0.00'}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Payment Method: ${_receiptData!['payment_method'] ?? 'N/A'}',
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 8),
        const Text(
          'Thank you for your business!',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Generated on ${TimeService.instance.formatNow()}',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Future<void> _shareReceipt() async {
    if (_receiptData == null) return;

    final receiptText = _generateReceiptText();
    await SharePlus.instance.share(
      ShareParams(
        text: receiptText,
        subject: 'Receipt #${_receiptData!['sale_id']}',
      ),
    );
  }

  Future<void> _downloadReceipt() async {
    if (_receiptData == null) return;

    try {
      final pdf = pw.Document();
      final store = _receiptData!['store'];
      final cashier = _receiptData!['cashier'];

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Store Information
                if (store != null) ...[
                  pw.Text(store['name'] ?? 'Store',
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  if (store['location'] != null && store['location'].isNotEmpty)
                    pw.Text(store['location'],
                        style: const pw.TextStyle(fontSize: 14)),
                  pw.SizedBox(height: 16),
                ],

                pw.Text('RECEIPT',
                    style: pw.TextStyle(
                        fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text('Sale #${_receiptData!['sale_id']}',
                    style: const pw.TextStyle(fontSize: 16)),
                pw.Text(_formatDate(_receiptData!['created_at']),
                    style: const pw.TextStyle(fontSize: 14)),

                // Cashier Information
                if (cashier != null) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                      'Cashier: ${cashier['full_name'] ?? cashier['username'] ?? 'Unknown'}',
                      style: const pw.TextStyle(fontSize: 14)),
                ],

                pw.SizedBox(height: 16),
                pw.Divider(),
                pw.Text('Items:',
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                ...(_receiptData!['items'] as List<dynamic>).map((item) => pw.Text(
                    '${item['product_name']} x${item['quantity']} - \$${item['total_price']?.toStringAsFixed(2)}')),
                pw.Divider(),
                pw.Text(
                    'Total: \$${_receiptData!['total_amount']?.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text(
                    'Payment Method: ${_receiptData!['payment_method'] ?? 'N/A'}',
                    style: const pw.TextStyle(fontSize: 14)),
                pw.SizedBox(height: 16),
                pw.Text('Thank you for your business!',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ],
            );
          },
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final file =
          File('${directory.path}/receipt_${_receiptData!['sale_id']}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt saved to ${file.path}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save receipt: $e')),
        );
      }
    }
  }

  Future<void> _printReceipt() async {
    if (_selectedDevice == null) {
      _showPrinterSelectionDialog();
      return;
    }

    if (_receiptData == null) return;

    try {
      // Connect to the selected device
      final bool connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: _selectedDevice!.macAdress,
      );

      if (!connected) {
        throw Exception('Failed to connect to printer');
      }

      // Generate receipt text
      final receiptText = _generateReceiptText();

      // Print the receipt using writeString with size 1 (normal size)
      await PrintBluetoothThermal.writeString(
        printText: PrintTextSize(size: 1, text: receiptText),
      );

      // Add some spacing
      await PrintBluetoothThermal.writeString(
        printText: PrintTextSize(size: 1, text: '\n\n'),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt sent to printer')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing receipt: $e')),
        );
      }
    } finally {
      // Disconnect from printer
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (e) {
        // Ignore disconnect errors
      }
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }
}
