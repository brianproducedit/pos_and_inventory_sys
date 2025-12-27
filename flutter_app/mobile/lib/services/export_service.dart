import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

abstract class ExportService {
  Future<String> exportReceiptsCsv(List<Map<String, dynamic>> receipts);
  Future<Uint8List> exportReceiptsPdf(List<Map<String, dynamic>> receipts);
}

class DefaultExportService implements ExportService {
  DefaultExportService._private();
  static final DefaultExportService instance = DefaultExportService._private();

  @override
  Future<String> exportReceiptsCsv(List<Map<String, dynamic>> receipts) async {
    final csvLines = <String>[];
    csvLines.add('id,reference,items_count,total,created_at');

    for (final r in receipts) {
      final id = r['id'] ?? '';
      final reference = (r['reference'] ?? '').toString().replaceAll(',', '');
      final items = r['items_count'] ?? '';
      final total = r['total'] ?? '';
      final created = r['created_at']?.toString() ?? '';
      csvLines.add('$id,$reference,$items,$total,$created');
    }

    final csv = csvLines.join('\n');

    final tempDir = Directory.systemTemp.createTempSync('pos_receipts_');
    final file = File(
        '${tempDir.path}${Platform.pathSeparator}receipts_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv, encoding: utf8);
    return file.path;
  }

  @override
  Future<Uint8List> exportReceiptsPdf(
      List<Map<String, dynamic>> receipts) async {
    // Simple PDF stub: produce plain-text bytes for now. Replace with proper PDF generation (package:pdf) when ready.
    final buffer = StringBuffer();
    buffer.writeln('Receipts Export\n-------------------');
    for (final r in receipts) {
      buffer.writeln('Ref: ${r['reference'] ?? r['id']}');
      buffer.writeln('Items: ${r['items_count'] ?? 0}');
      buffer.writeln('Total: ${r['total'] ?? 0}');
      buffer.writeln('Date: ${r['created_at'] ?? ''}');
      buffer.writeln('');
    }

    return Future.value(Uint8List.fromList(utf8.encode(buffer.toString())));
  }
}
