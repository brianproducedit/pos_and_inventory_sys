import 'package:flutter/material.dart';
import '../services/bluetooth_printer_service.dart';

/// Screen for discovering and connecting to Bluetooth printers
class PrinterDiscoveryScreen extends StatefulWidget {
  final BluetoothPrinterService printerService;

  const PrinterDiscoveryScreen({
    Key? key,
    required this.printerService,
  }) : super(key: key);

  @override
  State<PrinterDiscoveryScreen> createState() => _PrinterDiscoveryScreenState();
}

class _PrinterDiscoveryScreenState extends State<PrinterDiscoveryScreen> {
  bool _isScanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.printerService.addListener(_onPrinterServiceChanged);
    _startScan();
  }

  @override
  void dispose() {
    widget.printerService.removeListener(_onPrinterServiceChanged);
    super.dispose();
  }

  void _onPrinterServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _error = null;
    });

    try {
      await widget.printerService.scanForPrinters();
    } catch (e) {
      setState(() {
        _error = 'Failed to scan: $e';
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToPrinter(BluetoothPrinter printer) async {
    final success = await widget.printerService.connect(printer);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${printer.name}'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect to ${printer.name}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final printers = widget.printerService.availablePrinters;
    final connectedPrinter = widget.printerService.connectedPrinter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Printer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Help',
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Scanning indicator
          if (_isScanning)
            LinearProgressIndicator(
              backgroundColor: Colors.grey[200],
            ),

          // Error message
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red[50],
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            ),

          // Connected printer banner
          if (connectedPrinter != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.green[50],
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connected',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          connectedPrinter.name,
                          style: TextStyle(color: Colors.green[700]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await widget.printerService.disconnect();
                    },
                    tooltip: 'Disconnect',
                  ),
                ],
              ),
            ),

          // Printer list
          Expanded(
            child: printers.isEmpty && !_isScanning
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: printers.length,
                    itemBuilder: (context, index) {
                      return _buildPrinterCard(printers[index]);
                    },
                  ),
          ),

          // Scan button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isScanning ? 'Scanning...' : 'Scan Again'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.print_disabled,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Printers Found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Make sure your Bluetooth printer is:\n'
              '• Turned on\n'
              '• In pairing mode\n'
              '• Within range',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Scan Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterCard(BluetoothPrinter printer) {
    final isConnected = widget.printerService.connectedPrinter?.address == printer.address;
    final isConnecting = widget.printerService.connectionStatus == PrinterConnectionStatus.connecting;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isConnected
            ? BorderSide(color: Colors.green.shade300, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: isConnected ? Colors.green[100] : Colors.blue[100],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.print,
            color: isConnected ? Colors.green[700] : Colors.blue[700],
            size: 28,
          ),
        ),
        title: Text(
          printer.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: isConnected ? Colors.green[700] : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              printer.address,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            if (printer.modelName != null) ...[
              const SizedBox(height: 2),
              Text(
                printer.modelName!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
        trailing: isConnected
            ? Icon(Icons.check_circle, color: Colors.green[700], size: 32)
            : isConnecting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.link),
                    color: Colors.blue[700],
                    tooltip: 'Connect',
                    onPressed: () => _connectToPrinter(printer),
                  ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Printer Setup Help'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'How to connect your printer:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildHelpStep('1', 'Turn on your Bluetooth thermal printer'),
              _buildHelpStep('2', 'Enable pairing mode (usually a button or power on)'),
              _buildHelpStep('3', 'Tap "Scan Again" to search for printers'),
              _buildHelpStep('4', 'Select your printer from the list'),
              _buildHelpStep('5', 'Wait for connection to complete'),
              const SizedBox(height: 16),
              const Text(
                'Troubleshooting:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '• Make sure Bluetooth is enabled on your device\n'
                '• Keep printer within 10 meters range\n'
                '• Restart printer if connection fails\n'
                '• Check printer battery/power\n'
                '• Try forgetting and re-pairing in device settings',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue[100],
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text),
            ),
          ),
        ],
      ),
    );
  }
}
