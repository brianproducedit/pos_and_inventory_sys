import '../db/app_database.dart';

/// Receipt line item
class ReceiptLineItem {
  final String name;
  final int quantity;
  final double unitPrice;
  final double total;

  ReceiptLineItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });
}

/// Receipt model for printing and display
class ReceiptModel {
  final String transactionNumber;
  final DateTime date;
  final String storeName;
  final String? storeAddress;
  final String? storePhone;
  final String cashierName;
  final List<ReceiptLineItem> items;
  final double subtotal;
  final double? taxRate;
  final double? taxAmount;
  final double? discount;
  final double total;
  final String paymentMethod;
  final String? paymentReference;
  final String? footerMessage;

  ReceiptModel({
    required this.transactionNumber,
    required this.date,
    required this.storeName,
    this.storeAddress,
    this.storePhone,
    required this.cashierName,
    required this.items,
    required this.subtotal,
    this.taxRate,
    this.taxAmount,
    this.discount,
    required this.total,
    required this.paymentMethod,
    this.paymentReference,
    this.footerMessage,
  });

  /// Generate plain text receipt
  String toPlainText({int paperWidth = 32}) {
    final buffer = StringBuffer();
    final separator = '=' * paperWidth;
    final divider = '-' * paperWidth;

    // Header
    buffer.writeln(_center(storeName, paperWidth));
    if (storeAddress != null) {
      buffer.writeln(_center(storeAddress!, paperWidth));
    }
    if (storePhone != null) {
      buffer.writeln(_center(storePhone!, paperWidth));
    }
    buffer.writeln(separator);

    // Transaction details
    buffer.writeln('TXN: $transactionNumber');
    buffer.writeln('Date: ${_formatDateTime(date)}');
    buffer.writeln('Cashier: $cashierName');
    buffer.writeln(divider);

    // Items
    for (final item in items) {
      // Product name
      buffer.writeln(item.name);
      
      // Quantity x Price = Total
      final qtyLine = '  ${item.quantity} x \$${item.unitPrice.toStringAsFixed(2)}';
      final totalStr = '\$${item.total.toStringAsFixed(2)}';
      buffer.writeln(_leftRight(qtyLine, totalStr, paperWidth));
    }
    buffer.writeln(divider);

    // Totals
    buffer.writeln(_leftRight('Subtotal:', '\$${subtotal.toStringAsFixed(2)}', paperWidth));
    
    if (discount != null && discount! > 0) {
      buffer.writeln(_leftRight('Discount:', '-\$${discount!.toStringAsFixed(2)}', paperWidth));
    }
    
    if (taxAmount != null && taxAmount! > 0) {
      final taxLabel = taxRate != null ? 'Tax (${taxRate!.toStringAsFixed(1)}%)' : 'Tax';
      buffer.writeln(_leftRight(taxLabel, '\$${taxAmount!.toStringAsFixed(2)}', paperWidth));
    }
    
    buffer.writeln(separator);
    buffer.writeln(_leftRight('TOTAL:', '\$${total.toStringAsFixed(2)}', paperWidth, bold: true));
    buffer.writeln(separator);

    // Payment
    buffer.writeln('Payment: ${_formatPaymentMethod(paymentMethod)}');
    if (paymentReference != null) {
      buffer.writeln('Ref: $paymentReference');
    }

    // Footer
    if (footerMessage != null) {
      buffer.writeln(divider);
      buffer.writeln(_center(footerMessage!, paperWidth));
    }

    buffer.writeln(_center('Thank you!', paperWidth));
    
    return buffer.toString();
  }

  /// Generate ESC/POS commands for thermal printer
  /// This is a simplified version - actual implementation would use
  /// a proper ESC/POS library
  List<int> toEscPosCommands() {
    // ESC/POS command constants
    const esc = 0x1B;
    const gs = 0x1D;
    const lf = 0x0A;
    
    final commands = <int>[];

    // Initialize printer
    commands.addAll([esc, 0x40]);

    // Set to center alignment
    commands.addAll([esc, 0x61, 1]);
    
    // Store name (large text)
    commands.addAll([esc, 0x21, 0x30]); // Double height and width
    commands.addAll(storeName.codeUnits);
    commands.add(lf);
    
    // Reset text size
    commands.addAll([esc, 0x21, 0x00]);
    
    if (storeAddress != null) {
      commands.addAll(storeAddress!.codeUnits);
      commands.add(lf);
    }
    
    if (storePhone != null) {
      commands.addAll(storePhone!.codeUnits);
      commands.add(lf);
    }

    // Left align for details
    commands.addAll([esc, 0x61, 0]);
    commands.add(lf);
    
    // Transaction details
    commands.addAll('TXN: $transactionNumber'.codeUnits);
    commands.add(lf);
    commands.addAll('Date: ${_formatDateTime(date)}'.codeUnits);
    commands.add(lf);
    commands.addAll('Cashier: $cashierName'.codeUnits);
    commands.add(lf);
    commands.addAll('--------------------------------'.codeUnits);
    commands.add(lf);

    // Items
    for (final item in items) {
      commands.addAll(item.name.codeUnits);
      commands.add(lf);
      commands.addAll('  ${item.quantity} x \$${item.unitPrice.toStringAsFixed(2)} = \$${item.total.toStringAsFixed(2)}'.codeUnits);
      commands.add(lf);
    }
    
    commands.addAll('--------------------------------'.codeUnits);
    commands.add(lf);

    // Totals
    commands.addAll('Subtotal: \$${subtotal.toStringAsFixed(2)}'.codeUnits);
    commands.add(lf);
    
    if (taxAmount != null && taxAmount! > 0) {
      commands.addAll('Tax: \$${taxAmount!.toStringAsFixed(2)}'.codeUnits);
      commands.add(lf);
    }
    
    // Bold text for total
    commands.addAll([esc, 0x45, 1]); // Bold on
    commands.addAll('TOTAL: \$${total.toStringAsFixed(2)}'.codeUnits);
    commands.add(lf);
    commands.addAll([esc, 0x45, 0]); // Bold off
    
    commands.addAll('================================'.codeUnits);
    commands.add(lf);

    // Payment info
    commands.addAll('Payment: ${_formatPaymentMethod(paymentMethod)}'.codeUnits);
    commands.add(lf);
    
    if (paymentReference != null) {
      commands.addAll('Ref: $paymentReference'.codeUnits);
      commands.add(lf);
    }

    // Footer - center aligned
    commands.addAll([esc, 0x61, 1]);
    if (footerMessage != null) {
      commands.add(lf);
      commands.addAll(footerMessage!.codeUnits);
      commands.add(lf);
    }
    commands.add(lf);
    commands.addAll('Thank you!'.codeUnits);
    commands.add(lf);

    // Cut paper
    commands.addAll([gs, 0x56, 0x00]);

    return commands;
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'transaction_number': transactionNumber,
      'date': date.toIso8601String(),
      'store_name': storeName,
      'store_address': storeAddress,
      'store_phone': storePhone,
      'cashier_name': cashierName,
      'items': items.map((item) => {
        'name': item.name,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'total': item.total,
      }).toList(),
      'subtotal': subtotal,
      'tax_rate': taxRate,
      'tax_amount': taxAmount,
      'discount': discount,
      'total': total,
      'payment_method': paymentMethod,
      'payment_reference': paymentReference,
      'footer_message': footerMessage,
    };
  }

  /// Create from JSON
  factory ReceiptModel.fromJson(Map<String, dynamic> json) {
    return ReceiptModel(
      transactionNumber: json['transaction_number'] as String,
      date: DateTime.parse(json['date'] as String),
      storeName: json['store_name'] as String,
      storeAddress: json['store_address'] as String?,
      storePhone: json['store_phone'] as String?,
      cashierName: json['cashier_name'] as String,
      items: (json['items'] as List).map((item) {
        return ReceiptLineItem(
          name: item['name'] as String,
          quantity: item['quantity'] as int,
          unitPrice: (item['unit_price'] as num).toDouble(),
          total: (item['total'] as num).toDouble(),
        );
      }).toList(),
      subtotal: (json['subtotal'] as num).toDouble(),
      taxRate: json['tax_rate'] as double?,
      taxAmount: json['tax_amount'] as double?,
      discount: json['discount'] as double?,
      total: (json['total'] as num).toDouble(),
      paymentMethod: json['payment_method'] as String,
      paymentReference: json['payment_reference'] as String?,
      footerMessage: json['footer_message'] as String?,
    );
  }

  // Helper methods

  String _center(String text, int width) {
    if (text.length >= width) return text;
    final padding = (width - text.length) ~/ 2;
    return ' ' * padding + text;
  }

  String _leftRight(String left, String right, int width, {bool bold = false}) {
    final spaces = width - left.length - right.length;
    if (spaces < 0) return '$left $right';
    return left + (' ' * spaces) + right;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatPaymentMethod(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'Cash';
      case 'card':
        return 'Card';
      case 'mobile':
        return 'Mobile Payment';
      default:
        return method;
    }
  }
}
