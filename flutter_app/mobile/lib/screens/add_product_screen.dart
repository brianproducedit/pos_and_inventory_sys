import 'package:flutter/material.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:provider/provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:mobile/widgets/primary_button.dart';
// import 'package:mobile/theme/tokens.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final storeProvider = context.read<StoreProvider>();
      final inventoryProvider = context.read<InventoryProvider>();

      try {
        if (!storeProvider.isInitialized) await storeProvider.initialize();
      } catch (e) {
        debugPrint('AddProductScreen: store init skipped: $e');
      }
      inventoryProvider.setStoreProvider(storeProvider);
    });
  }

  Future<void> _addProduct() async {
    if (!_formKey.currentState!.validate()) return;

    // Ensure a store is selected before attempting to add a product
    final storeProvider = context.read<StoreProvider>();
    if (storeProvider.currentStore == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a store before adding a product')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final productData = {
      'name': _nameController.text.trim(),
      'price': double.parse(_priceController.text),
      'stock_quantity': int.parse(_stockController.text),
      'description': _descriptionController.text.trim(),
    };

    try {
      await context.read<InventoryProvider>().addProduct(productData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product added successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding product: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.role != 'superadmin' && authProvider.role != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
            child: Text('You do not have permission to access this screen.')),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Add Product'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StoreIndicator(
                store: context.watch<StoreProvider>().currentStore),
          ),
        ),
        actions: [
          if (context.watch<AuthProvider>().role == 'superadmin' ||
              context.watch<AuthProvider>().role == 'admin')
            const StoreQuickAction(),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrimaryTextField(
                  controller: _nameController,
                  label: 'Product Name',
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Please enter a name' : null,
                ),
                const SizedBox(height: 12),
                PrimaryTextField(
                  controller: _priceController,
                  label: 'Price',
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value?.isEmpty ?? true) return 'Please enter a price';
                    final price = double.tryParse(value!);
                    if (price == null || price <= 0) {
                      return 'Please enter a valid price';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                PrimaryTextField(
                  controller: _stockController,
                  label: 'Stock Quantity',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return 'Please enter stock quantity';
                    }
                    final stock = int.tryParse(value!);
                    if (stock == null || stock < 0) {
                      return 'Please enter a valid quantity';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                PrimaryTextField(
                  controller: _descriptionController,
                  label: 'Description',
                  maxLines: 3,
                  hint: 'Optional description',
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : PrimaryButton(
                        onPressed: _addProduct,
                        child: const Text('Add Product'),
                      ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/add_product'),
    );
  }
}
