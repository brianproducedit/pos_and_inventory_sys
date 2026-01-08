import 'package:flutter/material.dart';
import 'package:mobile/utils/smooth_page_route.dart';
import '../services/bluetooth_printer_service.dart';
import 'printer_discovery_screen.dart';
import 'print_queue_screen.dart';

/// Screen for managing printer settings and preferences
class PrinterSettingsScreen extends StatefulWidget {
  final BluetoothPrinterService printerService;

  const PrinterSettingsScreen({
    Key? key,
    required this.printerService,
  }) : super(key: key);

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  PrinterSettings? _settings;
  bool _isLoading = true;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    widget.printerService.addListener(_onPrinterServiceChanged);
    _loadSettings();
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

  Future<void> _loadSettings() async {
    final settings = await widget.printerService.getSettings();
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _updateSettings(PrinterSettings settings) async {
    await widget.printerService.updateSettings(settings);
    setState(() {
      _settings = settings;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _testPrint() async {
    setState(() => _isTesting = true);

    final success = await widget.printerService.testPrint();

    setState(() => _isTesting = false);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Test print successful!' : 'Test print failed'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectedPrinter = widget.printerService.connectedPrinter;
    final queuedCount = widget.printerService.queuedJobsCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Connection status card
                _buildConnectionCard(connectedPrinter),

                const SizedBox(height: 16),

                // Printer actions
                _buildActionsSection(connectedPrinter, queuedCount),

                const SizedBox(height: 24),

                // Settings section
                if (_settings != null) ...[
                  Text(
                    'Printer Preferences',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  _buildSettingsCard(),
                ],

                const SizedBox(height: 24),

                // Information section
                _buildInfoSection(),
              ],
            ),
    );
  }

  Widget _buildConnectionCard(BluetoothPrinter? printer) {
    final isConnected = printer != null;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isConnected ? Colors.green[100] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isConnected ? Icons.print : Icons.print_disabled,
                    color: isConnected ? Colors.green[700] : Colors.grey[600],
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected ? printer.name : 'No Printer Connected',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isConnected
                            ? printer.address
                            : 'Connect a Bluetooth printer to print receipts',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsSection(BluetoothPrinter? printer, int queuedCount) {
    final isConnected = printer != null;

    return Column(
      children: [
        // Find/Change printer button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              context.pushSmooth(
                PrinterDiscoveryScreen(
                  printerService: widget.printerService,
                ),
              );
            },
            icon: Icon(isConnected ? Icons.swap_horiz : Icons.search),
            label: Text(isConnected ? 'Change Printer' : 'Find Printer'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ),

        if (isConnected) ...[
          const SizedBox(height: 12),

          // Test print button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isTesting ? null : _testPrint,
              icon: _isTesting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.receipt),
              label: Text(_isTesting ? 'Printing...' : 'Test Print'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Print queue button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                context.pushSmooth(
                  PrintQueueScreen(
                    printerService: widget.printerService,
                  ),
                );
              },
              icon: queuedCount > 0
                  ? Badge(
                      label: Text('$queuedCount'),
                      child: const Icon(Icons.queue),
                    )
                  : const Icon(Icons.queue),
              label: const Text('View Print Queue'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Disconnect button
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () async {
                await widget.printerService.disconnect();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Printer disconnected')),
                  );
                }
              },
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSettingsCard() {
    if (_settings == null) return const SizedBox();

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Paper width setting
          ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('Paper Width'),
            subtitle: Text('${_settings!.paperWidth} characters'),
            trailing: DropdownButton<int>(
              value: _settings!.paperWidth,
              items: const [
                DropdownMenuItem(value: 32, child: Text('32 chars (58mm)')),
                DropdownMenuItem(value: 48, child: Text('48 chars (80mm)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  _updateSettings(PrinterSettings(
                    paperWidth: value,
                    autoPrint: _settings!.autoPrint,
                  ));
                }
              },
            ),
          ),
          const Divider(height: 1),

          // Auto-print setting
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome),
            title: const Text('Auto-Print Receipts'),
            subtitle: const Text('Automatically print after completing sale'),
            value: _settings!.autoPrint,
            onChanged: (value) {
              _updateSettings(PrinterSettings(
                paperWidth: _settings!.paperWidth,
                autoPrint: value,
              ));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'Printer Information',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Supported Printers:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '• Most Bluetooth thermal printers (58mm, 80mm)\n'
              '• ESC/POS compatible printers\n'
              '• Common brands: Xprinter, HOIN, Goojprt, etc.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tips:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '• Keep printer within 10 meters for best connection\n'
              '• Ensure printer has paper and sufficient battery\n'
              '• Queue receipts when printer is offline - they will print when connected',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}
