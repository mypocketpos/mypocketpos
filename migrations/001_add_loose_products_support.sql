-- Migration: Add loose/partial product support
-- Created: 2026-09-13
-- Purpose: Enable selling products in fractional quantities

-- Add new columns to products table
-- Note: Drift handles these through schema generation

-- For manual SQLite (if needed):
-- ALTER TABLE products ADD COLUMN is_loose_product BOOLEAN DEFAULT 0;
-- ALTER TABLE products ADD COLUMN base_unit TEXT DEFAULT 'piece';
-- ALTER TABLE products ADD COLUMN default_selling_qty REAL DEFAULT 1.0;
-- ALTER TABLE products ADD COLUMN min_selling_qty REAL DEFAULT 0.01;
-- ALTER TABLE products ADD COLUMN step_qty REAL DEFAULT 0.1;

-- Initialize existing products as non-loose (backward compatible)
UPDATE products
SET is_loose_product = 0,
    base_unit = unit,
    default_selling_qty = 1.0,
    min_selling_qty = 1.0,
    step_qty = 1.0
WHERE is_loose_product IS NULL;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_products_is_loose_product
ON products(is_loose_product);

CREATE INDEX IF NOT EXISTS idx_products_base_unit
ON products(base_unit);

-- Sample data: Insert loose products
-- Rice
INSERT INTO products (
  name, product_code, category_id, brand,
  purchase_price, selling_price, mrp, tax_percent,
  unit, description, is_active,
  is_loose_product, base_unit, default_selling_qty, min_selling_qty, step_qty,
  created_at
) VALUES (
  'Basmati Rice Premium', 'RICE-PREMIUM-001', NULL, 'Local',
  80.0, 150.0, 160.0, 0.0,
  'kg', 'Premium basmati rice', 1,
  1, 'kg', 1.0, 0.1, 0.1,
  CURRENT_TIMESTAMP
);

-- Sugar
INSERT INTO products (
  name, product_code, category_id, brand,
  purchase_price, selling_price, mrp, tax_percent,
  unit, description, is_active,
  is_loose_product, base_unit, default_selling_qty, min_selling_qty, step_qty,
  created_at
) VALUES (
  'White Sugar', 'SUGAR-WHITE-001', NULL, 'Crystal',
  40.0, 80.0, 85.0, 0.05,
  'g', 'Refined white sugar', 1,
  1, 'g', 500.0, 100.0, 100.0,
  CURRENT_TIMESTAMP
);

-- Medicine (tablet count)
INSERT INTO products (
  name, product_code, category_id, brand,
  purchase_price, selling_price, mrp, tax_percent,
  unit, description, is_active,
  is_loose_product, base_unit, default_selling_qty, min_selling_qty, step_qty,
  created_at
) VALUES (
  'Paracetamol 500mg', 'MED-PARACETAMOL-001', NULL, 'Generic',
  5.0, 8.0, 10.0, 0.05,
  'tablets', 'Pain reliever & fever reducer', 1,
  1, 'tablets', 2.0, 1.0, 1.0,
  CURRENT_TIMESTAMP
);

-- Honey (by weight)
INSERT INTO products (
  name, product_code, category_id, brand,
  purchase_price, selling_price, mrp, tax_percent,
  unit, description, is_active,
  is_loose_product, base_unit, default_selling_qty, min_selling_qty, step_qty,
  created_at
) VALUES (
  'Pure Honey', 'HONEY-PURE-001', NULL, 'Golden',
  200.0, 400.0, 450.0, 0.05,
  'g', 'Pure natural honey', 1,
  1, 'g', 250.0, 50.0, 50.0,
  CURRENT_TIMESTAMP
);

-- Ghee (by weight)
INSERT INTO products (
  name, product_code, category_id, brand,
  purchase_price, selling_price, mrp, tax_percent,
  unit, description, is_active,
  is_loose_product, base_unit, default_selling_qty, min_selling_qty, step_qty,
  created_at
) VALUES (
  'Pure Ghee', 'GHEE-PURE-001', NULL, 'Dairy',
  300.0, 600.0, 650.0, 0.05,
  'ml', 'Pure cow ghee', 1,
  1, 'ml', 250.0, 100.0, 50.0,
  CURRENT_TIMESTAMP
);

-- Regular product (non-loose, for backward compatibility test)
INSERT INTO products (
  name, product_code, category_id, brand,
  purchase_price, selling_price, mrp, tax_percent,
  unit, description, is_active,
  is_loose_product, base_unit, default_selling_qty, min_selling_qty, step_qty,
  created_at
) VALUES (
  'Milk Carton 1L', 'MILK-1L-001', NULL, 'Local Dairy',
  40.0, 60.0, 65.0, 0.05,
  'piece', 'Fresh milk in 1 liter carton', 1,
  0, 'piece', 1.0, 1.0, 1.0,
  CURRENT_TIMESTAMP
);

-- Verification queries
-- Check new columns exist:
-- SELECT is_loose_product, base_unit, default_selling_qty FROM products LIMIT 5;

-- Count loose products:
-- SELECT COUNT(*) as loose_product_count FROM products WHERE is_loose_product = 1;

-- List all loose products:
-- SELECT name, base_unit, default_selling_qty, min_selling_qty, step_qty
-- FROM products
-- WHERE is_loose_product = 1;
