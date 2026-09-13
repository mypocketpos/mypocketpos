/// Helper utilities for handling loose/partial product quantities
class QuantityHelper {
  /// Format quantity with unit for display (e.g., "2.5 kg", "500 g")
  static String formatQuantity(double quantity, String unit) {
    if (quantity == quantity.toInt()) {
      return '${quantity.toInt()} $unit';
    }
    return '${quantity.toStringAsFixed(2)} $unit';
  }

  /// Format quantity without unit (e.g., "2.5", "500")
  static String formatQtyOnly(double quantity) {
    if (quantity == quantity.toInt()) {
      return quantity.toInt().toString();
    }
    final formatted = quantity.toStringAsFixed(2);
    // Remove trailing zeros after decimal point
    return formatted.replaceAll(RegExp(r'\.?0+$'), '');
  }

  /// Increment quantity by step amount
  static double increment(double current, double step) {
    final incremented = current + step;
    return double.parse(incremented.toStringAsFixed(2));
  }

  /// Decrement quantity by step amount (but not below minimum)
  static double decrement(double current, double step, double minimum) {
    final decremented = current - step;
    if (decremented < minimum) return minimum;
    return double.parse(decremented.toStringAsFixed(2));
  }

  /// Validate quantity is within bounds
  static bool isValidQuantity(
    double quantity,
    double minQty,
    double maxQty,
  ) {
    return quantity >= minQty && quantity <= maxQty;
  }

  /// Round quantity to step precision
  static double roundToStep(double quantity, double step) {
    if (step <= 0) return quantity;
    final rounded = (quantity / step).round() * step;
    return double.parse(rounded.toStringAsFixed(2));
  }

  /// Get decimal places from step (e.g., 0.1 → 1, 0.01 → 2)
  static int getDecimalPlaces(double step) {
    if (step >= 1) return 0;
    final str = step.toString();
    final decimalIndex = str.indexOf('.');
    if (decimalIndex == -1) return 0;
    return str.length - decimalIndex - 1;
  }

  /// Format price with quantity (useful for bill display)
  static String formatLineTotal(double quantity, String unit, double price) {
    return '${formatQtyOnly(quantity)} $unit × ₹$price';
  }
}
