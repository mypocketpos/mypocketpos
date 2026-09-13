# Loose Products Implementation - Step by Step

## Phase 1: Database Schema (1-2 hours)

### Step 1.1: Update Drift Schema
Edit `lib/core/database/app_database.dart`:

```dart
class Products extends Table {
  // ... existing fields ...
  
  // ADD THESE NEW FIELDS:
  BoolColumn get isLooseProduct => boolean().withDefault(const Constant(false))();
  TextColumn get baseUnit => text().withDefault(const Constant('piece'))();
  RealColumn get defaultSellingQty => real().withDefault(const Constant(1))();
  RealColumn get minSellingQty => real().withDefault(const Constant(0.01))();
  RealColumn get stepQty => real().withDefault(const Constant(0.1))();
}
```

### Step 1.2: Regenerate Drift Code
```bash
cd lib/core/database
dart run build_runner build --delete-conflicting-outputs
```

**Verification:**
- Check that `app_database.g.dart` includes new fields
- Product class should have new properties

---

## Phase 2: Core Utilities (30 minutes)

### Step 2.1: Add QuantityHelper
✅ **Already created:** `lib/features/sales/domain/quantity_helper.dart`

No action needed - utility functions ready to use.

### Step 2.2: Add QuantityInputDialog
✅ **Already created:** `lib/features/sales/presentation/dialogs/quantity_input_dialog.dart`

No action needed - dialog widget ready.

### Step 2.3: Add LooseProductCard
✅ **Already created:** `lib/features/sales/presentation/widgets/loose_product_card.dart`

No action needed - card widget ready.

---

## Phase 3: Product Management UI (2-3 hours)

### Step 3.1: Update Product Dialog
**File:** `lib/features/products/presentation/product_dialog.dart`

Add section for loose products:

```dart
// In product dialog form
if (_formData['isLooseProduct'] == true) {
  Card(
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Loose Product Configuration',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          
          // Base Unit
          TextFormField(
            initialValue: _formData['baseUnit']?.toString() ?? 'piece',
            decoration: InputDecoration(
              labelText: 'Unit (kg, tablets, g, ml, etc.)',
              hintText: 'e.g., kg, tablets, grams',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _formData['baseUnit'] = v.trim(),
          ),
          const SizedBox(height: 12),
          
          // Min Selling Qty
          TextFormField(
            initialValue: (_formData['minSellingQty'] ?? 0.1).toString(),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Minimum Selling Quantity',
              hintText: 'e.g., 0.1 for rice, 1 for tablets',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _formData['minSellingQty'] = double.tryParse(v) ?? 0.1,
          ),
          const SizedBox(height: 12),
          
          // Default Selling Qty
          TextFormField(
            initialValue: (_formData['defaultSellingQty'] ?? 1.0).toString(),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Default Selling Quantity',
              hintText: 'e.g., 1 for rice, 2 for tablets',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _formData['defaultSellingQty'] = double.tryParse(v) ?? 1.0,
          ),
          const SizedBox(height: 12),
          
          // Step Qty
          TextFormField(
            initialValue: (_formData['stepQty'] ?? 0.1).toString(),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Increment/Decrement Step',
              hintText: 'e.g., 0.1 for kg, 1 for tablets',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _formData['stepQty'] = double.tryParse(v) ?? 0.1,
          ),
        ],
      ),
    ),
  )
}
```

### Step 3.2: Add Toggle for Loose Product
```dart
// In product dialog (main section)
CheckboxListTile(
  title: const Text('Loose/Partial Product'),
  subtitle: const Text('Allow selling in fractional quantities'),
  value: _formData['isLooseProduct'] ?? false,
  onChanged: (v) => setState(() {
    _formData['isLooseProduct'] = v ?? false;
  }),
),
```

---

## Phase 4: Quick Checkout Integration (2-3 hours)

### Step 4.1: Update Product Grid/List
**File:** `lib/features/sales/presentation/quick_checkout_page.dart`

In the itemBuilder where products are displayed:

```dart
// Instead of:
return _QuickCard(...)

// Use:
return row.product.isLooseProduct
    ? LooseProductCard(
        productName: row.product.name,
        emoji: row.emoji,
        price: row.product.sellingPrice,
        unit: row.product.baseUnit,
        currentQty: cartCount,
        stock: stock,
        minQty: row.product.minSellingQty,
        maxQty: row.product.defaultSellingQty * 100, // Reasonable max
        stepQty: row.product.stepQty,
        onQuantityChanged: (qty) {
          // Add to cart with new quantity
          _addProductToCart(row.product.id, qty);
        },
        isInCart: cartCount > 0,
        isBusy: busy,
      )
    : _QuickCard(
        item: row,
        busy: busy,
        cartCount: cartCount,
        stock: stock,
        onTap: () => _onTapProduct(row),
      );
```

### Step 4.2: Handle Cart Addition
Update `_onTapProduct` method:

```dart
Future<void> _onTapProduct(_QuickProductItem row, {double? quantity}) async {
  if (selected == null) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create or select a cart first')),
    );
    return;
  }

  final qty = quantity ?? (row.product.isLooseProduct 
      ? row.product.defaultSellingQty 
      : 1.0);

  // Add to cart...
  await ref.read(salesRepositoryProvider).addItem(
    cartId: selected!.id,
    productId: row.product.id,
    quantity: qty,
  );
}
```

---

## Phase 5: Cart Display Updates (1-2 hours)

### Step 5.1: Update Cart Items Display
**File:** `lib/features/sales/presentation/quick_checkout_page.dart` (in `_showCartItemsPopup`)

Display quantities with units:

```dart
// Before:
Text('${item.quantity} x ₹${product.sellingPrice}')

// After:
Text(
  '${QuantityHelper.formatQuantity(item.quantity, product.baseUnit)} × ₹${product.sellingPrice}',
)
```

### Step 5.2: Update Cart Summary
```dart
// Display with unit in summary
Text('Qty: ${QuantityHelper.formatQuantity(totalQty, primaryUnit)}')
```

### Step 5.3: Update Invoice/Bill Display
In `_printCartItems` method:

```dart
// In bill preview, show quantity with unit
Text(
  '${QuantityHelper.formatQuantity(row.item.quantity, row.product.baseUnit)}',
  style: const TextStyle(fontSize: 10),
),
```

---

## Phase 6: Stock Management (1 hour)

### Step 6.1: Update Inventory Deduction
**File:** `lib/features/sales/data/sales_repository_impl.dart`

In the checkout method:

```dart
// Deduct stock with decimal support
for (final item in items) {
  stock.availableStock -= item.quantity;  // Works with decimals!
}
```

### Step 6.2: Verify Decimal Arithmetic
```dart
// All calculations already support decimals:
final lineSub = item.quantity * item.unitPrice;  // 2.5 * 150 = 375
final tax = (lineSub * (taxPercent / 100));      // Works!
final total = lineSub + tax;                      // Works!
```

---

## Phase 7: Testing & Validation (2-3 hours)

### Step 7.1: Create Test Products
Use migration script or manually create:

1. **Rice (2.5 kg)**
   - isLooseProduct: true
   - baseUnit: kg
   - stepQty: 0.1
   - Min: 0.1, Default: 1.0

2. **Medicine (8 tablets)**
   - isLooseProduct: true
   - baseUnit: tablets
   - stepQty: 1
   - Min: 1, Default: 2

3. **Regular product (1 piece)**
   - isLooseProduct: false
   - baseUnit: piece
   - stepQty: 1
   - Min: 1, Default: 1

### Step 7.2: Test Each Scenario

```
[ ] Add loose product to cart
    [ ] Start at 0, increment +0.1 → 0.1 kg ✓
    [ ] Continue +0.1 → 0.2, 0.3, ... 2.5 kg ✓
    
[ ] Custom quantity input
    [ ] Open dialog, enter 3.5 kg
    [ ] Validate min/max
    [ ] Confirm and add to cart ✓
    
[ ] Cart display
    [ ] Shows "2.5 kg" not "2.5"
    [ ] Shows correct price calculation
    [ ] Unit displayed consistently ✓
    
[ ] Checkout
    [ ] Mixed cart (loose + regular)
    [ ] All quantities calculated correctly
    [ ] Stock deducted as decimals
    [ ] Invoice shows correct quantities ✓
    
[ ] Backward compatibility
    [ ] Regular products still work
    [ ] No impact on existing orders
    [ ] Mixed checkouts work ✓
```

---

## Phase 8: Deployment Checklist

- [ ] All Drift code generated
- [ ] No compilation errors
- [ ] Product dialog working
- [ ] Quick checkout cards displaying
- [ ] Cart adds with correct quantities
- [ ] Stock deduction correct
- [ ] Invoice displays units
- [ ] All test scenarios pass
- [ ] Backward compatibility verified
- [ ] No breaking changes to existing features

---

## Rollback Plan

If issues arise:

```bash
# Restore original code
git checkout HEAD~1 lib/core/database/app_database.dart

# Regenerate without new fields
dart run build_runner build

# Revert UI changes
git checkout HEAD~1 lib/features/...
```

---

## Timeline

| Phase | Task | Duration | Status |
|-------|------|----------|--------|
| 1 | Database Schema | 1-2h | ✅ Code Ready |
| 2 | Core Utilities | 0.5h | ✅ Complete |
| 3 | Product Dialog | 2-3h | 🔄 Pending |
| 4 | Quick Checkout | 2-3h | 🔄 Pending |
| 5 | Cart Display | 1-2h | 🔄 Pending |
| 6 | Stock Management | 1h | ✅ Ready |
| 7 | Testing | 2-3h | 🔄 Pending |
| 8 | Deployment | Varies | ⏸️ Standby |
| **TOTAL** | **All Phases** | **~13h** | **On Track** |

---

## Quick Reference Commands

```bash
# Rebuild Drift
dart run build_runner build --delete-conflicting-outputs

# Run specific test
flutter test test/features/sales/quantity_helper_test.dart

# Clean and rebuild
flutter clean && flutter pub get && flutter run

# Check for compilation errors
flutter analyze
```

---

## Support Files

Created files ready for use:
- ✅ `lib/features/sales/domain/quantity_helper.dart`
- ✅ `lib/features/sales/presentation/dialogs/quantity_input_dialog.dart`
- ✅ `lib/features/sales/presentation/widgets/loose_product_card.dart`
- ✅ `LOOSE_PRODUCTS_GUIDE.md` (comprehensive reference)
- ✅ `migrations/001_add_loose_products_support.sql` (sample data)

---

**Status:** Ready for Phase 3 implementation
**Next Action:** Update product dialog UI
**Estimated Completion:** 1-2 days for full integration
