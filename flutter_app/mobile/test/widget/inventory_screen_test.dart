import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/inventory_screen.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/screens/edit_product_screen.dart';
import '../test_helpers.dart';

class FakeInventoryProvider extends InventoryProvider {
  @override
  bool get isLoading => false;
  @override
  List<Map<String, dynamic>> get products => [
        {
          'id': 1,
          'name': 'Widget',
          'price': 3.0,
          'stock_quantity': 2,
          'is_active': true
        },
      ];
  @override
  List<Map<String, dynamic>> get lowStockAlerts => [
        // Intentionally use a mismatched product_name in the alert to ensure
        // the dialog prefers the real product name from the provider
        {'id': 1, 'product_name': 'WRONG NAME', 'stock_quantity': 2}
      ];
  @override
  int get lowStockCount => 1;
  @override
  int get criticalLowStockCount => 0;
}

class TestInventoryProvider extends InventoryProvider {
  TestInventoryProvider() : super();

  final List<int> deleted = [];
  final List<Map<String, dynamic>> _products = [
    {
      'id': 1,
      'name': 'Widget',
      'price': 3.0,
      'stock_quantity': 2,
      'is_active': true
    },
    {
      'id': 2,
      'name': 'Gadget',
      'price': 5.0,
      'stock_quantity': 5,
      'is_active': false
    },
  ];

  @override
  bool get isLoading => false;

  @override
  List<Map<String, dynamic>> get products => _products;

  @override
  Future<void> loadProducts() async {
    // No-op; rely on static products
    notifyListeners();
  }

  @override
  Future<void> deleteProduct(int productId) async {
    deleted.add(productId);
    _products.removeWhere((p) => p['id'] == productId);
    notifyListeners();
  }

  @override
  Future<void> updateProductStatus(int productId, bool isActive) async {
    final idx = _products.indexWhere((p) => p['id'] == productId);
    if (idx != -1) {
      _products[idx] = {..._products[idx], 'is_active': isActive};
    }
    notifyListeners();
  }
}

class FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String? get role => 'admin';
}

void main() {
  testWidgets('Inventory shows low stock panel and products', (tester) async {
    final inventory = FakeInventoryProvider();
    final auth = FakeAuthProvider();

    await tester.pumpWidget(wrapWithDefaultProviders(const InventoryScreen(),
        inventory: inventory, auth: auth, store: StoreProvider()));

    await tester.pumpAndSettle();

    expect(find.textContaining('low stock'), findsOneWidget);
    expect(find.text('Widget'), findsOneWidget);
    // Product name should be bold and black on the card
    final nameText = tester.widget<Text>(find.text('Widget'));
    expect(nameText.style?.color, equals(Colors.black));
    expect(nameText.style?.fontWeight, equals(FontWeight.bold));

    expect(find.text('\$3.00'), findsOneWidget);

    // Stock text should be red because this product is in FakeInventoryProvider.lowStockAlerts
    final stockText = tester.widget<Text>(find.text('Stock: 2'));
    expect(stockText.style?.color, equals(Colors.red));

    // Open low stock dialog and verify title color uses primary brand
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    final dialogTitle = tester.widget<Text>(find.text('Low stock alerts'));
    expect(dialogTitle.style?.color, equals(AppColors.primaryBrand));

    // Ensure the dialog shows the real product name (from provider), not the
    // mismatched alert-provided name
    final nameInDialog = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Widget'),
    );
    expect(nameInDialog, findsOneWidget);
    final wrongName = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('WRONG NAME'),
    );
    expect(wrongName, findsNothing);

    // Tap the product listed in the dialog and verify we navigate to Edit Product screen
    await tester.tap(nameInDialog);
    await tester.pumpAndSettle();

    expect(find.text('Edit Product'), findsOneWidget);

    // The edit form should present current values in the editable fields
    final fieldWidgets =
        tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(fieldWidgets.length, greaterThanOrEqualTo(4));

    final nameField = fieldWidgets[0];
    expect(nameField.controller?.text, equals('Widget'));

    final priceField = fieldWidgets[1];
    expect(priceField.controller?.text, equals('3.0'));

    final stockField = fieldWidgets[2];
    expect(stockField.controller?.text, equals('2'));

    final descField = fieldWidgets[3];
    expect(descField.controller?.text, equals(''));
  });

  testWidgets('Inventory bulk actions: select-all, toggle, delete, clear',
      (tester) async {
    final inv = TestInventoryProvider();
    final auth = FakeAuthProvider();

    await tester.pumpWidget(wrapWithDefaultProviders(const InventoryScreen(),
        inventory: inv, auth: auth, store: StoreProvider()));

    await tester.pumpAndSettle();

    // Initially no selection checkboxes should be visible
    final initialCheckboxes = find.byType(Checkbox);
    expect(initialCheckboxes, findsNothing);

    // Start selection mode by long-pressing the product card
    final productCard =
        find.ancestor(of: find.text('Widget'), matching: find.byType(Card));
    expect(productCard, findsOneWidget);
    await tester.longPress(productCard);
    await tester.pumpAndSettle();

    // There should now be two checkboxes (visible in selection mode)
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(2));

    // Toggle the first checkbox by invoking its onChanged directly
    final firstCheckbox = tester.widget<Checkbox>(checkboxes.first);
    firstCheckbox.onChanged?.call(true);
    await tester.pumpAndSettle();

    // Bulk bar should appear with 1 selected
    expect(find.text('1 selected'), findsOneWidget);

    // Use Select All to pick all visible products
    final selectAllFinder = find.byTooltip('Select all');
    expect(selectAllFinder, findsOneWidget);
    final selectAllBtnFinder =
        find.ancestor(of: selectAllFinder, matching: find.byType(IconButton));
    expect(selectAllBtnFinder, findsOneWidget);
    final selectAllIcon = tester.widget<IconButton>(selectAllBtnFinder);
    selectAllIcon.onPressed?.call();
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);

    // Clear selection
    final clearIcon =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.clear));
    clearIcon.onPressed?.call();
    await tester.pumpAndSettle();

    // Start selection mode again by long-pressing the product card
    await tester.longPress(productCard);
    await tester.pumpAndSettle();

    // Re-select first checkbox
    final firstCheckbox2 = tester.widget<Checkbox>(find.byType(Checkbox).first);
    firstCheckbox2.onChanged?.call(true);
    await tester.pumpAndSettle();

    // Toggle selected (one active -> expect Deactivate action via tooltip)
    final toggleOffTooltip = find.byTooltip('Deactivate selected');
    expect(toggleOffTooltip, findsOneWidget);
    final toggleOffBtn =
        find.ancestor(of: toggleOffTooltip, matching: find.byType(IconButton));
    final toggleOff = tester.widget<IconButton>(toggleOffBtn);
    toggleOff.onPressed?.call();
    await tester.pumpAndSettle();

    // Confirm dialog appears and accept
    expect(find.text('Confirm'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // The first product should be deactivated
    expect(inv.products[0]['is_active'], isFalse);

    // After operation the selection is cleared; start selection mode again and select both
    await tester.longPress(productCard);
    await tester.pumpAndSettle();

    final checkboxesAfter = find.byType(Checkbox);
    expect(checkboxesAfter, findsNWidgets(2));
    final firstCheckbox3 = tester.widget<Checkbox>(checkboxesAfter.first);
    firstCheckbox3.onChanged?.call(true);
    final lastCheckbox3 = tester.widget<Checkbox>(checkboxesAfter.last);
    lastCheckbox3.onChanged?.call(true);
    await tester.pumpAndSettle();

    // Bulk bar should show 2 selected
    expect(find.text('2 selected'), findsOneWidget);

    // Verify the '+' add icon is not present on the product's card
    // final productCard =
    find.ancestor(of: find.text('Widget'), matching: find.byType(Card));
    expect(productCard, findsOneWidget);

    final addIconInCard = find.descendant(
      of: productCard,
      matching: find.byIcon(Icons.add),
    );
    expect(addIconInCard, findsNothing);

    // Tap overflow menu on the product's card and choose Edit
    final firstOverflow = find.descendant(
      of: productCard,
      matching: find.byIcon(Icons.more_vert),
    );
    expect(firstOverflow, findsOneWidget);
    await tester.tap(firstOverflow);
    await tester.pumpAndSettle();

    final editItem = find.text('Edit');
    expect(editItem, findsOneWidget);
    await tester.tap(editItem);
    await tester.pumpAndSettle();

    // Confirm navigation to edit screen by type
    expect(find.byType(EditProductScreen), findsOneWidget);

    // Return to inventory screen
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Both selected and at least one inactive -> show activate icon (toggle_on)
    final toggleOnIcon = find.byIcon(Icons.toggle_on);
    expect(toggleOnIcon, findsOneWidget);

    // Invoke toggle (which will set targetActivate to hasInactive -> true)
    final toggleOnBtn = tester.widget<IconButton>(
        find.ancestor(of: toggleOnIcon, matching: find.byType(IconButton)));
    toggleOnBtn.onPressed?.call();
    await tester.pumpAndSettle();

    // Confirm dialog appears and accept
    expect(find.text('Confirm'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // After confirm the selected products should be activated
    expect(inv.products[0]['is_active'], isTrue);
    expect(inv.products[1]['is_active'], isTrue);

    // Selection is cleared after confirm, start selection mode again and select both for deletion
    await tester.longPress(productCard);
    await tester.pumpAndSettle();

    final checkboxesAfter2 = find.byType(Checkbox);
    expect(checkboxesAfter2, findsNWidgets(2));

    final firstCheckbox4 = tester.widget<Checkbox>(checkboxesAfter2.first);
    firstCheckbox4.onChanged?.call(true);
    final lastCheckbox4 = tester.widget<Checkbox>(checkboxesAfter2.last);
    lastCheckbox4.onChanged?.call(true);
    await tester.pumpAndSettle();

    // Delete selected — invoke callback directly
    final deleteIcon = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_forever));
    deleteIcon.onPressed?.call();
    await tester.pumpAndSettle();

    // Confirm dialog appears
    expect(find.text('Delete Products'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    // Both products deleted in provider
    expect(inv.deleted, containsAll(<int>[1, 2]));
  });

  testWidgets('Long press activates selection mode and selects product',
      (tester) async {
    final inv = TestInventoryProvider();
    final auth = FakeAuthProvider();

    await tester.pumpWidget(wrapWithDefaultProviders(const InventoryScreen(),
        inventory: inv, auth: auth, store: StoreProvider()));

    await tester.pumpAndSettle();

    // Long press the product card to start selection mode
    final productCard =
        find.ancestor(of: find.text('Widget'), matching: find.byType(Card));
    expect(productCard, findsOneWidget);
    await tester.longPress(productCard);
    await tester.pumpAndSettle();

    // Bulk bar should appear and show 1 selected
    expect(find.text('1 selected'), findsOneWidget);

    // The corresponding checkbox should be checked
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(2));
    final firstCheckbox = tester.widget<Checkbox>(checkboxes.first);
    expect(firstCheckbox.value, isTrue);
  });

  testWidgets('Long press toggles selection off when pressed again',
      (tester) async {
    final inv = TestInventoryProvider();
    final auth = FakeAuthProvider();

    await tester.pumpWidget(wrapWithDefaultProviders(const InventoryScreen(),
        inventory: inv, auth: auth, store: StoreProvider()));

    await tester.pumpAndSettle();

    final productCard =
        find.ancestor(of: find.text('Widget'), matching: find.byType(Card));
    expect(productCard, findsOneWidget);

    // Long press to select
    await tester.longPress(productCard);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    // Long press the same card again to toggle off
    await tester.longPress(productCard);
    await tester.pumpAndSettle();

    // Bulk bar should no longer be present
    expect(find.textContaining('selected'), findsNothing);

    // Checkboxes should be hidden when selection is cleared
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNothing);
  });

  testWidgets('Stock color is green when not low', (tester) async {
    final inv = TestInventoryProvider();
    final auth = FakeAuthProvider();

    await tester.pumpWidget(wrapWithDefaultProviders(const InventoryScreen(),
        inventory: inv, auth: auth, store: StoreProvider()));

    await tester.pumpAndSettle();

    // Gadget has stock 5 in TestInventoryProvider and no lowStockAlerts -> should be green
    final gadgetStock = tester.widget<Text>(find.text('Stock: 5'));
    expect(gadgetStock.style?.color, equals(AppColors.primaryAction));
  });

  testWidgets('Search filters product list', (tester) async {
    final inv = TestInventoryProvider();
    final auth = FakeAuthProvider();

    await tester.pumpWidget(wrapWithDefaultProviders(const InventoryScreen(),
        inventory: inv, auth: auth, store: StoreProvider()));

    await tester.pumpAndSettle();

    // Find the search field and enter 'gadget'
    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'gadget');
    // allow debounce timer to fire (300ms)
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // Only Gadget should be visible
    expect(find.text('Gadget'), findsOneWidget);
    expect(find.text('Widget'), findsNothing);

    // Clear search and ensure both reappear
    await tester.enterText(searchField, '');
    // allow debounce timer to fire for clearing
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Gadget'), findsOneWidget);
    expect(find.text('Widget'), findsOneWidget);
  });
}
