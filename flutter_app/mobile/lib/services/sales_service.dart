import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

class SalesService {
  static const String baseUrl = Env.baseUrl;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> saleData) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$baseUrl/api/sales'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(saleData),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create sale');
    }
  }

  Future<List<Map<String, dynamic>>> getSales({int? storeId}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    if (storeId != null) {
      headers['X-Store-ID'] = storeId.toString();
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/sales'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('Failed to load sales');
    }
  }

  Future<Map<String, dynamic>> getReceipt(int saleId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/api/receipts/$saleId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load receipt');
    }
  }

  Future<Map<String, dynamic>> getSalesAnalytics({int? storeId}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final uri = storeId != null
        ? Uri.parse('$baseUrl/api/analytics/sales?store_id=$storeId')
        : Uri.parse('$baseUrl/api/analytics/sales');

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load sales analytics');
    }
  }
}
