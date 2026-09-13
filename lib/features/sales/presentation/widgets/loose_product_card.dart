import 'package:flutter/material.dart';
import '../../domain/quantity_helper.dart';
import '../dialogs/quantity_input_dialog.dart';

/// Product card widget for loose/partial products with quantity stepper
class LooseProductCard extends StatefulWidget {
  const LooseProductCard({
    Key? key,
    required this.productName,
    required this.emoji,
    required this.price,
    required this.unit,
    required this.currentQty,
    required this.stock,
    required this.minQty,
    required this.maxQty,
    required this.stepQty,
    required this.onQuantityChanged,
    this.isInCart = false,
    this.isBusy = false,
  }) : super(key: key);

  final String productName;
  final String emoji;
  final double price;
  final String unit;
  final double currentQty;
  final double stock;
  final double minQty;
  final double maxQty;
  final double stepQty;
  final Function(double newQty) onQuantityChanged;
  final bool isInCart;
  final bool isBusy;

  @override
  State<LooseProductCard> createState() => _LooseProductCardState();
}

class _LooseProductCardState extends State<LooseProductCard> {
  late double _quantity;

  @override
  void initState() {
    super.initState();
    _quantity = widget.currentQty;
  }

  void _increment() {
    final newQty = QuantityHelper.increment(_quantity, widget.stepQty);
    if (newQty <= widget.maxQty && newQty <= widget.stock) {
      setState(() => _quantity = newQty);
      widget.onQuantityChanged(newQty);
    }
  }

  void _decrement() {
    final newQty = QuantityHelper.decrement(_quantity, widget.stepQty, widget.minQty);
    setState(() => _quantity = newQty);
    widget.onQuantityChanged(newQty);
  }

  void _showCustomQtyDialog() async {
    if (!mounted) return;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => QuantityInputDialog(
        productName: widget.productName,
        unit: widget.unit,
        currentQty: _quantity,
        minQty: widget.minQty,
        maxQty: widget.maxQty.clamp(0, widget.stock),
        stepQty: widget.stepQty,
      ),
    );

    if (result != null && mounted) {
      setState(() => _quantity = result);
      widget.onQuantityChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOutOfStock = widget.stock <= 0;
    final backgroundColor = _quantity > 0
        ? Colors.green.withValues(alpha: 0.15)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final borderColor = _quantity > 0 ? Colors.green : const Color(0xFFE3E3E3);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _showCustomQtyDialog,
      onLongPress: _showCustomQtyDialog,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: _quantity > 0 ? 2 : 1,
          ),
          color: backgroundColor,
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.emoji.isNotEmpty ? widget.emoji : '🛒',
                    style: const TextStyle(fontSize: 22),
                  ),
                  const Spacer(),
                  if (_quantity > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        QuantityHelper.formatQtyOnly(_quantity),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    )
                  else if (widget.isBusy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.add_circle_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                widget.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '₹${widget.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isOutOfStock
                          ? Colors.red.shade100
                          : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'S:${QuantityHelper.formatQtyOnly(widget.stock)}',
                      style: TextStyle(
                        fontSize: 8,
                        color: isOutOfStock ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Quantity stepper controls
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 28,
                      child: OutlinedButton(
                        onPressed: _quantity > widget.minQty ? _decrement : null,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side: BorderSide(
                            color: _quantity > widget.minQty
                                ? Colors.grey.shade400
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: const Text(
                          '−',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _showCustomQtyDialog,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${QuantityHelper.formatQtyOnly(_quantity)} ${widget.unit}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SizedBox(
                      height: 28,
                      child: FilledButton(
                        onPressed: _quantity < widget.maxQty && _quantity < widget.stock
                            ? _increment
                            : null,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text(
                          '+',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Tap or long-press to set custom quantity',
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
