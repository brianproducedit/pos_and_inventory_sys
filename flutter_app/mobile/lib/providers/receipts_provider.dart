import 'package:flutter/foundation.dart';

class ReceiptsProvider with ChangeNotifier {
  List<Map<String, dynamic>> _receipts = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get receipts => _receipts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadReceipts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Simulate network call
    await Future.delayed(const Duration(milliseconds: 50));
    _receipts = [
      {
        'id': 1,
        'total': 12.5,
        'items_count': 2,
        'created_at': '2025-12-24T10:00:00Z',
        'reference': 'INV-1001'
      },
      {
        'id': 2,
        'total': 45.0,
        'items_count': 4,
        'created_at': '2025-12-23T14:30:00Z',
        'reference': 'INV-0999'
      }
    ];

    _isLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> getReceiptById(int id) async {
    return _receipts.firstWhere((r) => r['id'] == id, orElse: () => {});
  }

  Future<void> createReceipt(Map<String, dynamic> receipt) async {
    _receipts.add(receipt);
    notifyListeners();
  }

  Future<void> deleteReceipt(int id) async {
    _receipts.removeWhere((r) => r['id'] == id);
    notifyListeners();
  }
}
