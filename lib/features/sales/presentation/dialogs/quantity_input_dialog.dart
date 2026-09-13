import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/quantity_helper.dart';

/// Dialog for inputting custom quantity for loose products
class QuantityInputDialog extends StatefulWidget {
  const QuantityInputDialog({
    required this.productName,
    required this.unit,
    required this.currentQty,
    required this.minQty,
    required this.maxQty,
    required this.stepQty,
  });

  final String productName;
  final String unit;
  final double currentQty;
  final double minQty;
  final double maxQty;
  final double stepQty;

  @override
  State<QuantityInputDialog> createState() => _QuantityInputDialogState();
}

class _QuantityInputDialogState extends State<QuantityInputDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: QuantityHelper.formatQtyOnly(widget.currentQty),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text);
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid number')),
      );
      return;
    }

    if (value < widget.minQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quantity must be at least ${QuantityHelper.formatQtyOnly(widget.minQty)}',
          ),
        ),
      );
      return;
    }

    if (value > widget.maxQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quantity cannot exceed ${QuantityHelper.formatQtyOnly(widget.maxQty)}',
          ),
        ),
      );
      return;
    }

    final rounded = QuantityHelper.roundToStep(value, widget.stepQty);
    Navigator.pop(context, rounded);
  }

  @override
  Widget build(BuildContext context) {
    final decimalPlaces = QuantityHelper.getDecimalPlaces(widget.stepQty);

    return AlertDialog(
      title: Text('Enter Quantity'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Product: ${widget.productName}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.numberWithOptions(
              decimal: decimalPlaces > 0,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d*\.?\d{0,2}$'),
              ),
            ],
            decoration: InputDecoration(
              labelText: 'Quantity',
              suffixText: widget.unit,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              helperText:
                  'Min: ${QuantityHelper.formatQtyOnly(widget.minQty)} | Max: ${QuantityHelper.formatQtyOnly(widget.maxQty)}',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
