import 'package:flutter/foundation.dart';
import '../data/repositories/sale_repository_v2.dart';

class ReceiptsProvider with ChangeNotifier {
  final SaleRepository _saleRepository;

  List<Map<String, dynamic>> _receipts = [];
  bool _isLoading = false;
  String? _error;

  ReceiptsProvider({required SaleRepository saleRepository})
      : _saleRepository = saleRepository;

  List<Map<String, dynamic>> get receipts => _receipts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadReceipts({int? storeId}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Load receipts from local database
      final sales = await _saleRepository.getAllSales(storeId: storeId);

      _receipts = sales.map((sale) {
        return {
          'id': sale.serverId ?? sale.id,
          'local_id': sale.id,
          'total': sale.totalAmount,
          'items_count': 0, // Can be enhanced by counting items
          'created_at': sale.createdAt.toIso8601String(),
          'reference': sale.transactionNumber,
          'payment_method': sale.paymentMethod,
          'is_synced': sale.serverId != null,
        };
      }).toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load receipts: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> getReceiptById(int id) async {
    try {
      return await _saleRepository.getReceiptData(id);
    } catch (e) {
      _error = 'Failed to get receipt: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> createReceipt(Map<String, dynamic> receipt) async {
    // This would typically be handled by the POS flow via SaleRepository.completeSale
    // Left here for interface compatibility
    _receipts.add(receipt);
    notifyListeners();
  }

  Future<void> deleteReceipt(int id) async {
    // Note: Sale deletion should be handled carefully with sync considerations
    // This is a placeholder for interface compatibility
    _receipts.removeWhere((r) => r['id'] == id);
    notifyListeners();
  }
}
