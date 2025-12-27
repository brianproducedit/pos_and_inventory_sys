import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/export_service.dart';

void main() {
  test('DefaultExportService exports CSV file and returns path', () async {
    final svc = DefaultExportService.instance;

    final receipts = [
      {
        'id': 1,
        'reference': 'R-1',
        'items_count': 2,
        'total': 12.5,
        'created_at': '2025-12-24'
      },
    ];

    final path = await svc.exportReceiptsCsv(receipts);
    final file = File(path);
    expect(file.existsSync(), isTrue);

    final content = await file.readAsString();
    expect(content.contains('R-1'), isTrue);

    // cleanup
    try {
      file.deleteSync();
      file.parent.deleteSync();
    } catch (_) {}
  });
}
