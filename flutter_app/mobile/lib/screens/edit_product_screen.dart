import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:mobile/providers/inventory_provider_v2.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/sync_provider.dart';
import 'package:mobile/db/app_database.dart';

class EditProductScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const EditProductScreen({super.key, required this.product});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final TextEditingController _descriptionController;
  late bool _isActive;

  bool _isLoading = false;

  String get _appBarTitle => 'Edit Product${_isActive ? '' : ' (Inactive)'}';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product['name'] ?? '');
    _priceController = TextEditingController(
        text: (widget.product['price'] ?? 0.0).toString());
    _stockController = TextEditingController(
        text: (widget.product['stock_quantity'] ?? 0).toString());
    _descriptionController =
        TextEditingController(text: widget.product['description'] ?? '');
    _isActive = widget.product['is_active'] ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;

    // V2: Instant local write, no loading state needed
    setState(() => _isLoading = true);

    try {
      await context.read<InventoryProviderV2>().updateProduct(
            widget.product['id'],
            name: _nameController.text.trim(),
            price: double.parse(_priceController.text),
            stockQuantity: int.parse(_stockController.text),
            description: _descriptionController.text.trim(),
            isActive: _isActive,
          );

      // Trigger immediate sync after updating product
      debugPrint('🔄 Product updated locally, triggering immediate sync...');
      if (mounted) {
        context.read<SyncProvider>().sync();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product updated successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating product: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteProduct() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await context
          .read<InventoryProviderV2>()
          .deleteProduct(widget.product['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting product: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.role != UserRole.superadmin &&
        authProvider.role != UserRole.admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
            child: Text('You do not have permission to access this screen.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteProduct,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name: show current value and editable field
              Text('Current: ${widget.product['name'] ?? '—'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
              const SizedBox(height: 6),
              PrimaryTextField(
                controller: _nameController,
                label: 'Product Name',
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter a name' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),

              // Price
              Text(
                  'Current: \$${(widget.product['price'] ?? 0.0).toStringAsFixed(2)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
              const SizedBox(height: 6),
              PrimaryTextField(
                controller: _priceController,
                label: 'Price',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Please enter a price';
                  final price = double.tryParse(value!);
                  if (price == null || price <= 0) {
                    return 'Please enter a valid price';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),

              // Stock
              Text('Current: ${widget.product['stock_quantity'] ?? 0}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
              const SizedBox(height: 6),
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
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),

              // Description
              Text('Current: ${widget.product['description'] ?? '—'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
              const SizedBox(height: 6),
              PrimaryTextField(
                controller: _descriptionController,
                label: 'Description',
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Active Product'),
                subtitle: Text(_isActive
                    ? 'Product is visible in inventory'
                    : 'Product is hidden from inventory'),
                value: _isActive,
                onChanged: (value) {
                  setState(() => _isActive = value);
                },
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _updateProduct,
                      child: const Text('Update Product'),
                    ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/edit_product'),
    );
  }
}
