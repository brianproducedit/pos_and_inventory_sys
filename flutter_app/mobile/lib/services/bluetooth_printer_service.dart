import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../models/receipt_model.dart';
import '../db/app_database.dart';

/// Bluetooth printer connection status
enum PrinterConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Bluetooth printer model
class BluetoothPrinter {
  final String name;
  final String address; // MAC address
  final String? modelName;
  final bool isConnected;

  BluetoothPrinter({
    required this.name,
    required this.address,
    this.modelName,
    this.isConnected = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BluetoothPrinter &&
          runtimeType == other.runtimeType &&
          address == other.address;

  @override
  int get hashCode => address.hashCode;

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'model_name': modelName,
      };

  factory BluetoothPrinter.fromJson(Map<String, dynamic> json) =>
      BluetoothPrinter(
        name: json['name'] as String,
        address: json['address'] as String,
        modelName: json['model_name'] as String?,
      );
}

/// Print job in queue
class PrintJob {
  final String id;
  final ReceiptModel receipt;
  final DateTime queuedAt;
  PrintJobStatus status;
  String? errorMessage;
  DateTime? printedAt;
  int retryCount;

  PrintJob({
    required this.id,
    required this.receipt,
    required this.queuedAt,
    this.status = PrintJobStatus.queued,
    this.errorMessage,
    this.printedAt,
    this.retryCount = 0,
  });

  bool get isPending =>
      status == PrintJobStatus.queued || status == PrintJobStatus.printing;
  bool get isFailed => status == PrintJobStatus.failed;
  bool get isComplete => status == PrintJobStatus.completed;
}

enum PrintJobStatus {
  queued,
  printing,
  completed,
  failed,
}

/// Service for managing Bluetooth thermal printer operations
///
/// Uses print_bluetooth_thermal for Bluetooth communication with ESC/POS printers.
class BluetoothPrinterService extends ChangeNotifier {
  final AppDatabase db;

  // Printer state
  BluetoothPrinter? _connectedPrinter;
  PrinterConnectionStatus _connectionStatus =
      PrinterConnectionStatus.disconnected;
  List<BluetoothPrinter> _availablePrinters = [];

  // Print queue
  final List<PrintJob> _printQueue = [];
  bool _isProcessingQueue = false;

  BluetoothPrinterService({required this.db});

  // Getters
  BluetoothPrinter? get connectedPrinter => _connectedPrinter;
  PrinterConnectionStatus get connectionStatus => _connectionStatus;
  List<BluetoothPrinter> get availablePrinters =>
      List.unmodifiable(_availablePrinters);
  List<PrintJob> get printQueue => List.unmodifiable(_printQueue);
  bool get isConnected =>
      _connectionStatus == PrinterConnectionStatus.connected;
  int get queuedJobsCount => _printQueue.where((j) => j.isPending).length;

  /// Scan for available Bluetooth printers
  Future<List<BluetoothPrinter>> scanForPrinters() async {
    debugPrint('BluetoothPrinterService: Scanning for printers...');

    try {
      // Get paired Bluetooth devices
      final List<BluetoothInfo> devices =
          await PrintBluetoothThermal.pairedBluetooths;

      // Convert to our BluetoothPrinter model
      _availablePrinters = devices.map((device) {
        return BluetoothPrinter(
          name: device.name,
          address: device.macAdress,
          modelName: device.name,
        );
      }).toList();

      notifyListeners();
      debugPrint(
          'BluetoothPrinterService: Found ${_availablePrinters.length} printers');
      return _availablePrinters;
    } catch (e) {
      debugPrint('BluetoothPrinterService: Scan failed: $e');
      return [];
    }
  }

  /// Connect to a Bluetooth printer
  Future<bool> connect(BluetoothPrinter printer) async {
    debugPrint('BluetoothPrinterService: Connecting to ${printer.name}...');

    _connectionStatus = PrinterConnectionStatus.connecting;
    notifyListeners();

    try {
      // Connect using MAC address
      final bool result =
          await PrintBluetoothThermal.connect(macPrinterAddress: printer.address);

      if (!result) {
        throw Exception('Connection returned false');
      }

      _connectedPrinter = printer;
      _connectionStatus = PrinterConnectionStatus.connected;

      // Save to settings
      await _savePrinterSettings(printer);

      notifyListeners();
      debugPrint('BluetoothPrinterService: Connected to ${printer.name}');
      return true;
    } catch (e) {
      debugPrint('BluetoothPrinterService: Connection failed: $e');
      _connectionStatus = PrinterConnectionStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Disconnect from current printer
  Future<void> disconnect() async {
    if (_connectedPrinter == null) return;

    debugPrint(
        'BluetoothPrinterService: Disconnecting from ${_connectedPrinter!.name}...');

    try {
      // Disconnect from the device
      await PrintBluetoothThermal.disconnect;

      _connectedPrinter = null;
      _connectionStatus = PrinterConnectionStatus.disconnected;
      notifyListeners();
      debugPrint('BluetoothPrinterService: Disconnected');
    } catch (e) {
      debugPrint('BluetoothPrinterService: Disconnect failed: $e');
      // Still update state even if disconnect fails
      _connectedPrinter = null;
      _connectionStatus = PrinterConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  /// Print receipt immediately
  Future<bool> printReceipt(ReceiptModel receipt) async {
    if (!isConnected) {
      debugPrint('BluetoothPrinterService: Cannot print - not connected');
      return false;
    }

    debugPrint(
        'BluetoothPrinterService: Printing receipt ${receipt.transactionNumber}...');

    try {
      // Generate ESC/POS commands
      final commands = receipt.toEscPosCommands();

      // Send raw bytes to printer
      final bool result =
          await PrintBluetoothThermal.writeBytes(Uint8List.fromList(commands));

      if (!result) {
        throw Exception('writeBytes returned false');
      }

      debugPrint('BluetoothPrinterService: Receipt printed successfully');
      return true;
    } catch (e) {
      debugPrint('BluetoothPrinterService: Print failed: $e');
      return false;
    }
  }

  /// Add receipt to print queue
  Future<String> queueReceipt(ReceiptModel receipt) async {
    final job = PrintJob(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      receipt: receipt,
      queuedAt: DateTime.now(),
    );

    _printQueue.add(job);
    notifyListeners();

    debugPrint(
        'BluetoothPrinterService: Receipt queued (${_printQueue.length} in queue)');

    // Auto-process queue if connected
    if (isConnected && !_isProcessingQueue) {
      _processQueue();
    }

    return job.id;
  }

  /// Process queued print jobs
  Future<void> _processQueue() async {
    if (_isProcessingQueue || _printQueue.isEmpty) return;

    _isProcessingQueue = true;

    while (_printQueue.isNotEmpty && isConnected) {
      final job = _printQueue.firstWhere(
        (j) => j.status == PrintJobStatus.queued,
        orElse: () => _printQueue.first,
      );

      if (job.status != PrintJobStatus.queued) break;

      job.status = PrintJobStatus.printing;
      notifyListeners();

      final success = await printReceipt(job.receipt);

      if (success) {
        job.status = PrintJobStatus.completed;
        job.printedAt = DateTime.now();
        _printQueue.remove(job);
      } else {
        job.retryCount++;
        if (job.retryCount >= 3) {
          job.status = PrintJobStatus.failed;
          job.errorMessage = 'Max retries exceeded';
        } else {
          job.status = PrintJobStatus.queued; // Retry later
        }
      }

      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isProcessingQueue = false;
  }

  /// Retry failed print job
  Future<void> retryJob(String jobId) async {
    final job = _printQueue.firstWhere((j) => j.id == jobId);
    job.status = PrintJobStatus.queued;
    job.retryCount = 0;
    job.errorMessage = null;
    notifyListeners();

    if (isConnected) {
      _processQueue();
    }
  }

  /// Remove job from queue
  void removeJob(String jobId) {
    _printQueue.removeWhere((j) => j.id == jobId);
    notifyListeners();
  }

  /// Clear all completed jobs
  void clearCompletedJobs() {
    _printQueue.removeWhere((j) => j.isComplete);
    notifyListeners();
  }

  /// Test print connection
  Future<bool> testPrint() async {
    if (!isConnected) return false;

    debugPrint('BluetoothPrinterService: Running test print...');

    try {
      // Create test receipt
      final testReceipt = ReceiptModel(
        transactionNumber: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
        date: DateTime.now(),
        storeName: 'Test Store',
        cashierName: 'Test Cashier',
        items: [
          ReceiptLineItem(
            name: 'Test Item',
            quantity: 1,
            unitPrice: 10.0,
            total: 10.0,
          ),
        ],
        subtotal: 10.0,
        total: 10.0,
        paymentMethod: 'Cash',
        footerMessage: 'This is a test receipt',
      );

      return await printReceipt(testReceipt);
    } catch (e) {
      debugPrint('BluetoothPrinterService: Test print failed: $e');
      return false;
    }
  }

  /// Load saved printer settings
  Future<void> loadSavedPrinter() async {
    final printerAddress = await _getPrinterAddress();
    if (printerAddress == null) return;

    final printerName = await _getPrinterName();

    final savedPrinter = BluetoothPrinter(
      name: printerName ?? 'Saved Printer',
      address: printerAddress,
    );

    // Auto-connect to saved printer
    await connect(savedPrinter);
  }

  Future<void> _savePrinterSettings(BluetoothPrinter printer) async {
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: 'printer_address',
            value: drift.Value(printer.address),
          ),
        );
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: 'printer_name',
            value: drift.Value(printer.name),
          ),
        );
  }

  Future<String?> _getPrinterAddress() async {
    final meta = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals('printer_address')))
        .getSingleOrNull();
    return meta?.value;
  }

  Future<String?> _getPrinterName() async {
    final meta = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals('printer_name')))
        .getSingleOrNull();
    return meta?.value;
  }

  /// Get printer settings
  Future<PrinterSettings> getSettings() async {
    final paperWidth = await _getPaperWidth();
    final autoPrint = await _getAutoPrint();

    return PrinterSettings(
      paperWidth: paperWidth,
      autoPrint: autoPrint,
    );
  }

  /// Update printer settings
  Future<void> updateSettings(PrinterSettings settings) async {
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: 'printer_paper_width',
            value: drift.Value(settings.paperWidth.toString()),
          ),
        );
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: 'printer_auto_print',
            value: drift.Value(settings.autoPrint.toString()),
          ),
        );
    notifyListeners();
  }

  Future<int> _getPaperWidth() async {
    final meta = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals('printer_paper_width')))
        .getSingleOrNull();
    return int.tryParse(meta?.value ?? '48') ?? 48;
  }

  Future<bool> _getAutoPrint() async {
    final meta = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals('printer_auto_print')))
        .getSingleOrNull();
    return meta?.value?.toLowerCase() == 'true';
  }
}

/// Printer settings
class PrinterSettings {
  final int paperWidth; // 32, 48, or 58 characters
  final bool autoPrint; // Auto-print after sale completion

  PrinterSettings({
    required this.paperWidth,
    required this.autoPrint,
  });
}
