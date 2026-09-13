# Loose/Partial Products Implementation Guide

## Overview
This feature enables selling products in fractional quantities (rice in kg, medicine in tablets, sugar in grams) instead of only whole units.

## Database Changes

### 1. Products Table - New Fields

```dart
class Products extends Table {
  // ... existing fields ...
  
  // New fields for loose product support
  BoolColumn get isLooseProduct => boolean().withDefault(const Constant(false))();
  TextColumn get baseUnit => text().withDefault(const Constant('piece'))();
  RealColumn get defaultSellingQty => real().withDefault(const Constant(1))();
  RealColumn get minSellingQty => real().withDefault(const Constant(0.01))();
  RealColumn get stepQty => real().withDefault(const Constant(0.1))();
}
```

**After schema changes, run:**
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 2. CartItems & SaleItems - Already Support Decimals ✓
- `quantity` field is already `RealColumn`
- Supports decimal quantities natively
- No changes needed!

## Model Extensions

### Updated Product Model
```dart
@freezed
class ProductModel with _$ProductModel {
  const factory ProductModel({
    required int id,
    required String name,
    required String productCode,
    required double sellingPrice,
    required String unit,
    // New fields
    required bool isLooseProduct,
    required String baseUnit,
    required double defaultSellingQty,
    required double minSellingQty,
    required double stepQty,
    // ... other fields ...
  }) = _ProductModel;
}
```

## Core Components

### 1. QuantityHelper Utility (`quantity_helper.dart`)
**Purpose:** Format and validate decimal quantities

```dart
// Format with unit
QuantityHelper.formatQuantity(2.5, 'kg') // Returns: "2.5 kg"

// Increment/Decrement
QuantityHelper.increment(2.0, 0.5)  // Returns: 2.5
QuantityHelper.decrement(2.0, 0.5, 0.1)  // Returns: 1.5

// Validation
QuantityHelper.isValidQuantity(2.5, 0.1, 5.0)  // Check min/max
QuantityHelper.roundToStep(2.55, 0.1)  // Round to step
```

### 2. QuantityInputDialog (`quantity_input_dialog.dart`)
**Purpose:** Custom quantity input for loose products

```dart
final result = await showDialog<double>(
  context: context,
  builder: (ctx) => QuantityInputDialog(
    productName: 'Basmati Rice',
    unit: 'kg',
    currentQty: 2.0,
    minQty: 0.1,
    maxQty: 25.0,
    stepQty: 0.1,
  ),
);
```

### 3. LooseProductCard (`loose_product_card.dart`)
**Purpose:** Product card with quantity stepper for quick checkout

Features:
- +/- stepper buttons
- Tap to open custom quantity dialog
- Long-press for quick custom input
- Real-time quantity display
- Stock validation

```dart
LooseProductCard(
  productName: 'Basmati Rice',
  emoji: '🍚',
  price: 150.0,
  unit: 'kg',
  currentQty: 0,
  stock: 50.0,
  minQty: 0.1,
  maxQty: 25.0,
  stepQty: 0.1,
  onQuantityChanged: (qty) {
    // Add to cart with new quantity
  },
)
```

## Sample Product Data

### Rice (Loose - Weight Based)
```json
{
  "name": "Basmati Rice",
  "productCode": "RICE-001",
  "unit": "kg",
  "isLooseProduct": true,
  "baseUnit": "kg",
  "defaultSellingQty": 1.0,
  "minSellingQty": 0.1,
  "maxSellingQty": 25.0,
  "stepQty": 0.1,
  "sellingPrice": 150.0,
  "purchasePrice": 100.0
}
```

### Medicine (Loose - Count Based)
```json
{
  "name": "Paracetamol 500mg",
  "productCode": "MED-001",
  "unit": "tablets",
  "isLooseProduct": true,
  "baseUnit": "tablets",
  "defaultSellingQty": 1.0,
  "minSellingQty": 1.0,
  "maxSellingQty": 100.0,
  "stepQty": 1.0,
  "sellingPrice": 8.0,
  "purchasePrice": 5.0
}
```

### Sugar (Loose - Weight Based)
```json
{
  "name": "White Sugar",
  "productCode": "SUGAR-001",
  "unit": "g",
  "isLooseProduct": true,
  "baseUnit": "g",
  "defaultSellingQty": 500.0,
  "minSellingQty": 100.0,
  "maxSellingQty": 5000.0,
  "stepQty": 100.0,
  "sellingPrice": 0.08,
  "purchasePrice": 0.05
}
```

### Regular Products (Backward Compatible)
```json
{
  "name": "Milk Carton 1L",
  "productCode": "MILK-001",
  "unit": "piece",
  "isLooseProduct": false,
  "baseUnit": "piece",
  "defaultSellingQty": 1.0,
  "minSellingQty": 1.0,
  "maxSellingQty": 1000.0,
  "stepQty": 1.0,
  "sellingPrice": 60.0,
  "purchasePrice": 50.0
}
```

## Product Dialog Updates

### Add Loose Product Section
```dart
if (!isLooseProduct) {
  // Regular section
} else {
  // Loose Product Configuration
  Card(
    child: Column(
      children: [
        TextFormField(
          label: 'Base Unit',
          hint: 'kg, tablets, g, ml, etc.',
          value: baseUnit,
        ),
        TextFormField(
          label: 'Min Selling Qty',
          value: minSellingQty.toString(),
        ),
        TextFormField(
          label: 'Default Qty',
          value: defaultSellingQty.toString(),
        ),
        TextFormField(
          label: 'Step Qty (increment)',
          value: stepQty.toString(),
        ),
      ],
    ),
  )
}
```

## Cart Display Updates

### Show Quantities with Units
```dart
// Before:
Text('Qty: 2')

// After:
Text('Qty: ${QuantityHelper.formatQuantity(2.5, 'kg')}')
// Output: "Qty: 2.5 kg"
```

### Bill/Invoice Display
```dart
// Line item in cart
Row(
  children: [
    Text(product.name),
    Spacer(),
    Text(
      QuantityHelper.formatQuantity(
        cartItem.quantity,
        product.baseUnit,
      ),
    ),
    Text(' × ₹${product.sellingPrice}'),
  ],
)
```

## Stock Management

### Deduct Stock (Already Supports Decimals)
```dart
// Before (int only)
inventory.availableStock -= 2;

// After (decimal support)
inventory.availableStock -= 2.5;  // Works!
inventory.availableStock -= 100.0; // Weight-based
```

### Restock (Reverse)
```dart
inventory.availableStock += 2.5;  // Add back loose quantity
```

## Integration Checklist

- [ ] Run Drift migration: `dart run build_runner build`
- [ ] Update Product model with new fields
- [ ] Add UI section to product dialog
- [ ] Update quick checkout to use LooseProductCard for isLooseProduct=true
- [ ] Update cart display to show units
- [ ] Update invoice/bill printing with units
- [ ] Update stock management calculations
- [ ] Test with sample data (rice, medicine, sugar)
- [ ] Verify backward compatibility with existing products
- [ ] Test partial quantity checkout flow
- [ ] Test stock deduction with decimals

## Usage Example

### Creating a Loose Product
```dart
final product = Product(
  name: 'Basmati Rice',
  productCode: 'RICE-001',
  sellingPrice: 150.0,
  unit: 'kg',
  isLooseProduct: true,
  baseUnit: 'kg',
  defaultSellingQty: 1.0,
  minSellingQty: 0.1,
  stepQty: 0.1,
);

await productRepository.create(product);
```

### Adding to Cart with Custom Quantity
```dart
// User selects 2.5 kg of rice
final cartItem = CartItem(
  productId: riceProductId,
  quantity: 2.5,  // Decimal!
  unitPrice: 150.0,
);

await cartRepository.addItem(cartItem);
```

### Checkout with Decimals
```dart
// Cart calculation with decimals
final lineSub = 2.5 * 150.0;  // 375
final tax = (lineSub * 0.18);  // 67.5
final total = lineSub + tax;  // 442.5

// All calculations rounded to 2 decimals
final rounded = double.parse(total.toStringAsFixed(2));
```

## Backward Compatibility

**Regular products (isLooseProduct = false) continue to work:**
- `stepQty: 1.0` keeps quantities as whole numbers
- `minSellingQty: 1.0` prevents fractional quantities
- Default step is 1.0 (only whole increments)

**Existing data migration:**
```sql
-- Set defaults for existing products
UPDATE products 
SET isLooseProduct = false,
    baseUnit = unit,
    defaultSellingQty = 1.0,
    minSellingQty = 1.0,
    stepQty = 1.0
WHERE isLooseProduct IS NULL;
```

## Key Files

```
lib/
├── features/sales/
│   ├── domain/
│   │   └── quantity_helper.dart          # Quantity utilities
│   └── presentation/
│       ├── dialogs/
│       │   └── quantity_input_dialog.dart # Custom qty input
│       └── widgets/
│           └── loose_product_card.dart    # Product card with stepper
├── core/database/
│   └── app_database.dart                  # Schema with new fields
```

## Testing Scenarios

1. **Add loose product (2.5 kg rice)**
   - Verify quantity accepts decimals
   - Verify unit displays correctly
   - Verify stock deducted as 2.5

2. **Increment/Decrement**
   - Start at 1.0 kg, increment by 0.1 → 1.1 kg ✓
   - Start at 2.5 kg, decrement by 0.1 → 2.4 kg ✓

3. **Custom quantity input**
   - Enter 3.75 kg → Validate & round ✓
   - Enter below min (0.05 < 0.1) → Error ✓
   - Enter above max (26 > 25) → Error ✓

4. **Stock management**
   - Stock: 10 kg, Sell: 2.5 kg → Remaining: 7.5 kg ✓
   - Stock: 100 tablets, Sell: 8 tablets → Remaining: 92 ✓

5. **Backward compatibility**
   - Regular products still work (step=1.0) ✓
   - Mixed carts (loose + regular) checkout ✓
   - Invoice shows mixed units ✓

## Performance Notes

- Decimal calculations use `toStringAsFixed(2)` for rounding
- Stepper operates locally, syncs to backend on cartUpdate
- Real-time stock updates via Riverpod streams
- No performance impact on regular products

---

**Implementation Status:** ✅ All core components completed
**Testing:** Ready for integration and testing
**Backward Compatibility:** ✅ Fully maintained
