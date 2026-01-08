import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/sync_provider.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/db/app_database.dart';

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _businessNameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _taxNumberController;
  late TextEditingController _receiptFooterController;

  bool _isSuperadmin = false;

  @override
  void initState() {
    super.initState();
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    _isSuperadmin = (authProvider.role == UserRole.superadmin);

    _businessNameController = TextEditingController(
        text: settingsProvider.storeSettings?.businessName ?? '');
    _addressController = TextEditingController(
        text: settingsProvider.storeSettings?.address ?? '');
    _phoneController = TextEditingController(
        text: settingsProvider.storeSettings?.phone ?? '');
    _emailController = TextEditingController(
        text: settingsProvider.storeSettings?.email ?? '');
    _taxNumberController = TextEditingController(
        text: settingsProvider.storeSettings?.taxNumber ?? '');
    _receiptFooterController = TextEditingController(
        text: settingsProvider.storeSettings?.receiptFooter ?? '');

    // Load settings if not already loaded and user is not superadmin (defer until after build)
    if (!_isSuperadmin && settingsProvider.storeSettings == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        settingsProvider.loadStoreSettings();
      });
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _taxNumberController.dispose();
    _receiptFooterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Settings'),
        backgroundColor: AppColors.primaryBrand,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSuperadmin ? null : _saveSettings,
          ),
        ],
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          if (settingsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Update controllers when settings load
          if (_isSuperadmin) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Superadmin manages all stores and cannot edit store-specific settings.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
          }

          if (settingsProvider.storeSettings != null) {
            _businessNameController.text =
                settingsProvider.storeSettings!.businessName ?? '';
            _addressController.text =
                settingsProvider.storeSettings!.address ?? '';
            _phoneController.text = settingsProvider.storeSettings!.phone ?? '';
            _emailController.text = settingsProvider.storeSettings!.email ?? '';
            _taxNumberController.text =
                settingsProvider.storeSettings!.taxNumber ?? '';
            _receiptFooterController.text =
                settingsProvider.storeSettings!.receiptFooter ?? '';
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Business Information',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Business Name
                  TextFormField(
                    controller: _businessNameController,
                    decoration: const InputDecoration(
                      labelText: 'Business Name',
                      border: OutlineInputBorder(),
                      hintText: 'Enter your business name',
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Address
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                      hintText: 'Enter business address',
                    ),
                    maxLines: 3,
                  ),

                  const SizedBox(height: 16),

                  // Phone
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                      hintText: 'Enter phone number',
                    ),
                    keyboardType: TextInputType.phone,
                  ),

                  const SizedBox(height: 16),

                  // Email
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      hintText: 'Enter email address',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final emailRegex =
                            RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                        if (!emailRegex.hasMatch(value)) {
                          return 'Please enter a valid email';
                        }
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Tax Number
                  TextFormField(
                    controller: _taxNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Tax Number',
                      border: OutlineInputBorder(),
                      hintText: 'Enter tax registration number',
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Receipt Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Receipt Footer
                  TextFormField(
                    controller: _receiptFooterController,
                    decoration: const InputDecoration(
                      labelText: 'Receipt Footer',
                      border: OutlineInputBorder(),
                      hintText: 'Thank you for your business!',
                    ),
                    maxLines: 2,
                  ),

                  const SizedBox(height: 24),

                  // Error message
                  if (settingsProvider.error != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        settingsProvider.error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      child: const Text('Save Settings'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final newSettings = settingsProvider.storeSettings?.copyWith(
          businessName: _businessNameController.text.isEmpty
              ? null
              : _businessNameController.text,
          address:
              _addressController.text.isEmpty ? null : _addressController.text,
          phone: _phoneController.text.isEmpty ? null : _phoneController.text,
          email: _emailController.text.isEmpty ? null : _emailController.text,
          taxNumber: _taxNumberController.text.isEmpty
              ? null
              : _taxNumberController.text,
          receiptFooter: _receiptFooterController.text.isEmpty
              ? null
              : _receiptFooterController.text,
        ) ??
        StoreSettings(
          businessName: _businessNameController.text.isEmpty
              ? null
              : _businessNameController.text,
          address:
              _addressController.text.isEmpty ? null : _addressController.text,
          phone: _phoneController.text.isEmpty ? null : _phoneController.text,
          email: _emailController.text.isEmpty ? null : _emailController.text,
          taxNumber: _taxNumberController.text.isEmpty
              ? null
              : _taxNumberController.text,
          receiptFooter: _receiptFooterController.text.isEmpty
              ? null
              : _receiptFooterController.text,
        );

    final success = await settingsProvider.updateStoreSettings(newSettings);
    if (success && mounted) {
      // Trigger sync after store settings update
      context.read<SyncProvider>().sync();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Store settings saved successfully')),
      );
    }
  }
}
