import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../core/firestore/firestore_mappers.dart';
import '../../../core/firestore/store_scope.dart';
import '../../store/presentation/store_auth_controller.dart';
import '../domain/sales_repository.dart';

class QuickCheckoutPage extends ConsumerStatefulWidget {
  const QuickCheckoutPage({super.key});

  @override
  ConsumerState<QuickCheckoutPage> createState() => _QuickCheckoutPageState();
}

class _QuickCheckoutPageState extends ConsumerState<QuickCheckoutPage> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final Set<int> _addingProductIds = <int>{};

  List<_QuickProductItem> _products = const <_QuickProductItem>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitial();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>>? get _productsCol {
    final storeId = ref.read(activeStoreIdProvider);
    if (storeId == null || storeId.isEmpty) return null;
    return storeCollection(ref.read(firestoreProvider), storeId, 'products');
  }

  void _onScroll() {
    if (_query.isNotEmpty || _loading || !_hasMore) return;
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels + 320 >=
        _scrollCtrl.position.maxScrollExtent) {
      _loadMore(limit: 10);
    }
  }

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _products = const <_QuickProductItem>[];
      _cursor = null;
      _hasMore = true;
    });

    if (_query.isEmpty) {
      await _loadMore(limit: 50, replace: true);
      return;
    }
    await _runSearch(_query);
  }

  Future<void> _loadMore({required int limit, bool replace = false}) async {
    final col = _productsCol;
    if (col == null || _loading || !_hasMore) return;

    setState(() => _loading = true);
    try {
      Query<Map<String, dynamic>> q = col
          .where('isActive', isEqualTo: true)
          .where('showInQuickCheckout', isEqualTo: true)
          .orderBy('name')
          .limit(limit);
      if (_cursor != null) {
        q = q.startAfterDocument(_cursor!);
      }

      final snap = await q.get();
      final incoming = snap.docs
          .map((doc) => _QuickProductItem.fromDoc(doc))
          .where((row) => row.product.name.trim().isNotEmpty)
          .toList();

      setState(() {
        if (replace) {
          _products = incoming;
        } else {
          _products = <_QuickProductItem>[..._products, ...incoming];
        }
        if (snap.docs.isNotEmpty) {
          _cursor = snap.docs.last;
        }
        _hasMore = snap.docs.length == limit;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load products: $e')),
        );
      }
      setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) {
      await _loadInitial();
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await ref.read(productRepositoryProvider).search(q);
      final result = rows
          .map((p) => _QuickProductItem(
                product: p,
                showInQuickCheckout: false,
                emoji: '',
              ))
          .toList();
      if (mounted) {
        setState(() {
          _products = result;
          _hasMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onTapProduct(_QuickProductItem row) async {
    if (_addingProductIds.contains(row.product.id)) return;

    setState(() => _addingProductIds.add(row.product.id));
    try {
      var cartId = ref.read(selectedCartIdProvider);
      if (cartId == null) {
        cartId = await _createQuickCart();
        if (cartId == null) return;
      }

      await ref.read(salesRepositoryProvider).addItem(
            cartId: cartId,
            productId: row.product.id,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 700),
            content: Text('${row.product.name} added'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _addingProductIds.remove(row.product.id));
      }
    }
  }

  Future<int?> _createQuickCart() async {
    final mobileCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    final result = await showDialog<({String mobile, String name})?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Quick Cart'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: mobileCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) async {
                final mobile = value.trim();
                if (mobile.isEmpty) return;
                final existing = await ref
                    .read(customerRepositoryProvider)
                    .findByMobile(mobile);
                if (existing != null && ctx.mounted) {
                  nameCtrl.text = existing.name;
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              (mobile: mobileCtrl.text.trim(), name: nameCtrl.text.trim()),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == null) return null;

    final mobile = result.mobile;
    final name = result.name;
    final label = name.isNotEmpty
        ? name
        : (mobile.isNotEmpty
            ? mobile
            : 'Quick Cart ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}');

    final counterId = ref.read(activeCounterIdProvider);
    int cartId;
    if (mobile.isNotEmpty) {
      final customerId =
          await ref.read(customerRepositoryProvider).createOrUpdate(
                mobile: mobile,
                name: name.isNotEmpty ? name : 'Customer $mobile',
              );
      cartId = await ref.read(salesRepositoryProvider).createCartWithCustomer(
            label,
            customerId,
            posCounterId: counterId,
          );
    } else {
      cartId = await ref.read(salesRepositoryProvider).createCart(
            label,
            posCounterId: counterId,
          );
    }

    ref.read(selectedCartIdProvider.notifier).state = cartId;
    return cartId;
  }

  Future<void> _showInvoiceSearch() async {
    final searchCtrl = TextEditingController();
    final searchTypeNotifier = ValueNotifier<String>('mobile');

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Find Invoice'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Search by:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: searchTypeNotifier,
                builder: (context, type, _) => Column(
                  children: [
                    RadioListTile<String>(
                      title: const Text('Customer Mobile'),
                      value: 'mobile',
                      groupValue: type,
                      onChanged: (v) => searchTypeNotifier.value = v ?? 'mobile',
                    ),
                    RadioListTile<String>(
                      title: const Text('Invoice Number'),
                      value: 'invoice',
                      groupValue: type,
                      onChanged: (v) => searchTypeNotifier.value = v ?? 'invoice',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  labelText: searchTypeNotifier.value == 'mobile'
                      ? 'Mobile Number'
                      : 'Invoice Number (e.g., INV-...)',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(
                    searchTypeNotifier.value == 'mobile'
                        ? Icons.phone
                        : Icons.receipt,
                  ),
                ),
                keyboardType: searchTypeNotifier.value == 'mobile'
                    ? TextInputType.phone
                    : TextInputType.text,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final query = searchCtrl.text.trim();
              if (query.isEmpty) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Please enter search value')),
                  );
                }
                return;
              }

              try {
                List<Sale> invoices = [];

                if (searchTypeNotifier.value == 'mobile') {
                  invoices = await ref
                      .read(salesRepositoryProvider)
                      .findSalesByCustomerMobile(query, limit: 10);
                } else {
                  final sale = await ref
                      .read(salesRepositoryProvider)
                      .findByInvoiceNo(query);
                  if (sale != null) {
                    invoices = [sale];
                  }
                }

                if (!ctx.mounted) return;
                Navigator.pop(ctx);

                if (invoices.isEmpty) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No invoices found')),
                  );
                  return;
                }

                if (!mounted) return;
                _showInvoiceList(invoices);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Search failed: $e')),
                  );
                }
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Future<void> _showInvoiceList(List<Sale> invoices) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Found ${invoices.length} Invoice${invoices.length > 1 ? 's' : ''}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...invoices.asMap().entries.map((entry) {
                final invoice = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: InkWell(
                    onTap: () => Navigator.pop(ctx),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  invoice.invoiceNo,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '₹${invoice.grandTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green,
                                  ),
                                ),
                                Text(
                                  invoice.soldAt.toString().split('.')[0],
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.print_rounded),
                            onPressed: () {
                              // TODO: Implement invoice print
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (invoices.length >= 10) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(ctx);
                    // TODO: Navigate to customer module for full invoice list
                    // context.go('/customers');
                  },
                  child: const Text('Show More in Customer Module'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _printCartItems(List<CartItemWithProduct> rows) async {
    if (rows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty')),
      );
      return;
    }

    final summary = ref.read(cartSummaryProvider(rows));
    final now = DateTime.now();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bill Preview'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bill Header
              Center(
                child: Column(
                  children: [
                    const Text('Bill of Supply',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    const Text('Cash',
                      style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Date and Invoice
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Date: ${now.day}/${now.month}/${now.year}',
                    style: const TextStyle(fontSize: 10)),
                  Text('Invoice no: ${now.millisecondsSinceEpoch % 1000}',
                    style: const TextStyle(fontSize: 10)),
                ],
              ),
              Text('Time: ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),

              const SizedBox(height: 12),
              const Divider(height: 1),

              // Table Header
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text('Item Name',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: Text('Qty',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center),
                    ),
                    Expanded(
                      child: Text('Price',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.right),
                    ),
                    Expanded(
                      child: Text('Amount',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.right),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Items
              ...rows.map((row) {
                final lineTotal = row.product.sellingPrice * row.item.quantity;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(row.product.name,
                          style: const TextStyle(fontSize: 9),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        child: Text(
                          row.item.quantity.toStringAsFixed(
                            row.item.quantity % 1 == 0 ? 0 : 1),
                          style: const TextStyle(fontSize: 9),
                          textAlign: TextAlign.center),
                      ),
                      Expanded(
                        child: Text('₹${row.product.sellingPrice.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 9),
                          textAlign: TextAlign.right),
                      ),
                      Expanded(
                        child: Text('₹${lineTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 9),
                          textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                );
              }),

              const Divider(height: 1),

              // Totals
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal',
                          style: TextStyle(fontSize: 10)),
                        Text('₹${(summary.grandTotal - summary.taxTotal).toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('₹${summary.grandTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              Center(
                child: Text('Thank you for doing business with us',
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                  textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _editCartName(int cartId, String currentName) async {
    final nameCtrl = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Cart Name'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Cart Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || !mounted) return;

    // TODO: Implement cart name update in repository
    // await ref.read(salesRepositoryProvider).updateCartName(cartId, newName);
  }

  Future<void> _showCartItemsPopup(int cartId) async {
    final discountPercentCtrl = TextEditingController();
    final discountPercentNotifier = ValueNotifier<double>(0);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (context, ref, child) {
          final cartItemsAsync = ref.watch(cartItemsProvider(cartId));

          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Cart Items'),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: cartItemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Center(child: Text('Cart is empty'));
                }
                return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...rows.map((row) {
                    final lineTotal = row.product.sellingPrice * row.item.quantity;
                    final gstAmount = lineTotal * (row.product.taxPercent / 100);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.product.name,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        '₹${row.product.sellingPrice.toStringAsFixed(2)}',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                                        onPressed: () async {
                                          if (row.item.quantity <= 1) {
                                            await ref
                                                .read(salesRepositoryProvider)
                                                .removeItem(row.item.id);
                                          } else {
                                            await ref
                                                .read(salesRepositoryProvider)
                                                .updateItemQuantity(
                                                  row.item.id,
                                                  row.item.quantity - 1,
                                                );
                                          }
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(
                                        row.item.quantity.toStringAsFixed(
                                            row.item.quantity % 1 == 0 ? 0 : 1),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.add_circle_outline, size: 18),
                                        onPressed: () async {
                                          await ref
                                              .read(salesRepositoryProvider)
                                              .updateItemQuantity(
                                                row.item.id,
                                                row.item.quantity + 1,
                                              );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Subtotal',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                                Text(
                                  '₹${lineTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              ],
                            ),
                            if (row.product.taxPercent > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'GST (${row.product.taxPercent.toStringAsFixed(0)}%)',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                  Text(
                                    '₹${gstAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const Divider(height: 24),
                  // Discount % field
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Discount %:', style: TextStyle(fontWeight: FontWeight.w600)),
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (discCtx) => AlertDialog(
                              title: const Text('Enter Discount %'),
                              content: TextField(
                                controller: discountPercentCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  hintText: '0',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(discCtx),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    final percent =
                                        double.tryParse(discountPercentCtrl.text) ?? 0;
                                    discountPercentNotifier.value = percent.clamp(0, 100);
                                    Navigator.pop(discCtx);
                                  },
                                  child: const Text('Apply'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: ValueListenableBuilder<double>(
                          valueListenable: discountPercentNotifier,
                          builder: (context, discPercent, _) => Text(
                            discPercent > 0 ? '${discPercent.toStringAsFixed(1)}%' : 'Add',
                            style: TextStyle(
                              color: discPercent > 0 ? Colors.green : Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Summary with discount and GST
                  ValueListenableBuilder<double>(
                    valueListenable: discountPercentNotifier,
                    builder: (context, discPercent, _) {
                      final subtotal = rows.fold<double>(
                        0,
                        (sum, row) => sum + (row.product.sellingPrice * row.item.quantity),
                      );
                      final discountAmount =
                          (subtotal * (discPercent / 100)).clamp(0, subtotal);
                      final taxableAmount = subtotal - discountAmount;
                      final totalGst = rows.fold<double>(
                        0,
                        (sum, row) {
                          final lineTotal = row.product.sellingPrice * row.item.quantity;
                          final lineTaxableAfterDisc =
                              lineTotal * ((100 - discPercent) / 100);
                          return sum +
                              (lineTaxableAfterDisc * (row.product.taxPercent / 100));
                        },
                      );
                      final finalTotal = taxableAmount + totalGst;

                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal'),
                              Text('₹${subtotal.toStringAsFixed(2)}'),
                            ],
                          ),
                          if (discPercent > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Discount (${discPercent.toStringAsFixed(1)}%)'),
                                Text(
                                  '-₹${discountAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.green),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total GST'),
                              Text('₹${totalGst.toStringAsFixed(2)}'),
                            ],
                          ),
                          const Divider(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Grand Total',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                '₹${finalTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
              },
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (confirmCtx) => AlertDialog(
                      title: const Text('Clear Cart?'),
                      content: const Text('Remove all items from cart?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmCtx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(confirmCtx, true),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final cartItemsAsync = ref.read(cartItemsProvider(cartId));
                    if (cartItemsAsync is AsyncData) {
                      final rows = (cartItemsAsync as AsyncData).value;
                      for (final item in rows) {
                        await ref
                            .read(salesRepositoryProvider)
                            .removeItem(item.item.id);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
                label: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _checkoutDirect(int cartId, List<CartItemWithProduct> rows) async {
    if (rows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty. Add products first.')),
      );
      return;
    }

    final summary = ref.read(cartSummaryProvider(rows));
    final paymentModeCtrl = ValueNotifier<String>('cash');

    if (!mounted) return;
    final result = await showDialog<({String paymentMode, double paidAmount})?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Checkout'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Amount: ₹${summary.grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Payment Mode:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: paymentModeCtrl,
                builder: (context, mode, _) => Column(
                  children: [
                    RadioListTile<String>(
                      title: const Text('Cash'),
                      value: 'cash',
                      groupValue: mode,
                      onChanged: (v) => paymentModeCtrl.value = v ?? 'cash',
                    ),
                    RadioListTile<String>(
                      title: const Text('Card'),
                      value: 'card',
                      groupValue: mode,
                      onChanged: (v) => paymentModeCtrl.value = v ?? 'card',
                    ),
                    RadioListTile<String>(
                      title: const Text('UPI'),
                      value: 'upi',
                      groupValue: mode,
                      onChanged: (v) => paymentModeCtrl.value = v ?? 'upi',
                    ),
                    RadioListTile<String>(
                      title: const Text('Udhar (Credit)'),
                      value: 'credit',
                      groupValue: mode,
                      onChanged: (v) => paymentModeCtrl.value = v ?? 'credit',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              (paymentMode: paymentModeCtrl.value, paidAmount: summary.grandTotal),
            ),
            child: const Text('Pay Now'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    // If credit/udhar selected, ask how much to pay now vs credit
    if (result.paymentMode == 'credit') {
      final paidNowCtrl = TextEditingController();

      if (!mounted) return;
      final udharResult = await showDialog<({double paidNow, double creditAmount})?>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Udhar (Credit Sale)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total Amount: ₹${summary.grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: paidNowCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount to Pay Now (₹)',
                  border: const OutlineInputBorder(),
                  hintText: '0',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Credit Amount: ₹${(summary.grandTotal - (double.tryParse(paidNowCtrl.text) ?? 0)).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final paidNow = double.tryParse(paidNowCtrl.text) ?? 0;
                final creditAmount = summary.grandTotal - paidNow;
                Navigator.pop(ctx, (paidNow: paidNow, creditAmount: creditAmount));
              },
              child: const Text('Confirm Udhar'),
            ),
          ],
        ),
      );

      if (udharResult == null || !mounted) return;

      try {
        await ref.read(salesRepositoryProvider).checkout(
          cartId: cartId,
          paymentMode: 'credit',
          paidAmount: udharResult.paidNow,
        );
        ref.invalidate(dashboardMetricsProvider);
        ref.invalidate(salesReportProvider);
        ref.read(selectedCartIdProvider.notifier).state = null;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade700,
              content: Text(
                'Udhar created: ₹${udharResult.creditAmount.toStringAsFixed(2)} to be paid later',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Udhar failed: $e')),
          );
        }
      }
      return;
    }

    try {
      await ref.read(salesRepositoryProvider).checkout(
        cartId: cartId,
        paymentMode: result.paymentMode,
        paidAmount: result.paidAmount,
      );
      ref.invalidate(dashboardMetricsProvider);
      ref.invalidate(salesReportProvider);
      ref.read(selectedCartIdProvider.notifier).state = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              'Checkout complete: ₹${summary.grandTotal.toStringAsFixed(2)}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCartId = ref.watch(selectedCartIdProvider);
    final carts = ref.watch(activeCartsProvider).valueOrNull ?? const <Cart>[];

    Cart? selected;
    if (selectedCartId != null) {
      for (final cart in carts) {
        if (cart.id == selectedCartId) {
          selected = cart;
          break;
        }
      }
    }

    final cartItemsAsync = selectedCartId == null
        ? null
        : ref.watch(cartItemsProvider(selectedCartId));

    final rows = cartItemsAsync?.valueOrNull ?? const <CartItemWithProduct>[];
    final summary = ref.watch(cartSummaryProvider(rows));
    final qty = rows.fold<double>(0, (sum, row) => sum + row.item.quantity);
    final total = summary.grandTotal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Checkout'),
        actions: [
          IconButton(
            tooltip: 'Find Invoice',
            onPressed: _showInvoiceSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Open standard POS',
            onPressed: () => context.go('/billing'),
            icon: const Icon(Icons.point_of_sale_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by name, code or barcode',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                              _loadInitial();
                            },
                          ),
                  ),
                  onChanged: (value) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 250), () {
                      if (!mounted) return;
                      setState(() => _query = value.trim());
                      _loadInitial();
                    });
                    setState(() {});
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _createQuickCart,
                        icon: const Icon(Icons.add),
                        label: const Text('New Cart'),
                      ),
                      const SizedBox(width: 8),
                      for (final c in carts)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: c.id == selectedCartId
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ChoiceChip(
                                      selected: true,
                                      label: Text(c.name),
                                      onSelected: (_) => ref
                                          .read(selectedCartIdProvider.notifier)
                                          .state = c.id,
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Delete Cart?'),
                                            content: Text('Delete "${c.name}" and all items?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx, false),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(ctx, true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true && mounted) {
                                          await ref
                                              .read(salesRepositoryProvider)
                                              .deleteCart(c.id);
                                          ref
                                              .read(selectedCartIdProvider.notifier)
                                              .state = null;
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade600,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ChoiceChip(
                                  selected: false,
                                  label: Text(c.name),
                                  onSelected: (_) => ref
                                      .read(selectedCartIdProvider.notifier)
                                      .state = c.id,
                                ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                childAspectRatio: 1.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _products.length + (_loading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _products.length) {
                  return const Card(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final row = _products[index];
                final busy = _addingProductIds.contains(row.product.id);

                // Count this product in the cart
                var cartCount = 0.0;
                for (final item in rows) {
                  if (item.product.id == row.product.id) {
                    cartCount = item.item.quantity;
                    break;
                  }
                }

                // Watch stock in real-time from inventory provider
                return Consumer(
                  builder: (context, localRef, _) {
                    final inventoryAsync = localRef.watch(inventoryProvider);
                    double stock = 0.0;

                    if (inventoryAsync.hasValue) {
                      final inventoryList = inventoryAsync.asData?.value ?? [];
                      // Find stock for this product in real-time
                      for (final item in inventoryList) {
                        if (item.product.id == row.product.id) {
                          stock += item.inventory.availableStock;
                        }
                      }
                    }

                    return _QuickCard(
                      item: row,
                      busy: busy,
                      cartCount: cartCount,
                      stock: stock,
                      onTap: () => _onTapProduct(row),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: const Border(top: BorderSide(color: Color(0xFFE5E5E5))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selected == null
                                        ? 'Select or create cart'
                                        : 'Cart: ${selected.name}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (selected != null)
                                  Tooltip(
                                    message: 'Edit cart name',
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      icon: const Icon(Icons.edit, size: 16),
                                      onPressed: () => _editCartName(
                                        selected!.id,
                                        selected!.name,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              'Qty: ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 1)}  ·  Total: ₹${total.toStringAsFixed(2)}',
                              style:
                                  const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: selectedCartId == null || rows.isEmpty
                            ? null
                            : () => _showCartItemsPopup(selectedCartId),
                        icon: const Icon(Icons.list_rounded),
                        label: const Text('Items'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: selectedCartId == null || rows.isEmpty
                            ? null
                            : () => _printCartItems(rows),
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('Print'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: selectedCartId == null || rows.isEmpty
                            ? null
                            : () => _checkoutDirect(selectedCartId, rows),
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Checkout'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.item,
    required this.onTap,
    required this.busy,
    required this.cartCount,
    required this.stock,
  });

  final _QuickProductItem item;
  final VoidCallback onTap;
  final bool busy;
  final double cartCount;
  final double stock;

  @override
  Widget build(BuildContext context) {
    final emoji = item.emoji.trim();
    final isInCart = cartCount > 0;
    final backgroundColor = isInCart
        ? Colors.green.withValues(alpha: 0.15)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final borderColor =
        isInCart ? Colors.green : const Color(0xFFE3E3E3);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: busy ? null : onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: isInCart ? 2 : 1,
          ),
          color: backgroundColor,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      emoji.isNotEmpty ? emoji : '🛒',
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                  if (isInCart)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${cartCount.toStringAsFixed(cartCount % 1 == 0 ? 0 : 1)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.add_circle_rounded,
                        color: Theme.of(context).colorScheme.primary),
                ],
              ),
              const Spacer(),
              Text(
                item.product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '₹${item.product.sellingPrice.toStringAsFixed(2)}',
                    style:
                        const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: stock <= 0 ? Colors.red.shade100 : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Stock: ${stock.toStringAsFixed(stock % 1 == 0 ? 0 : 1)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: stock <= 0 ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickProductItem {
  const _QuickProductItem({
    required this.product,
    required this.showInQuickCheckout,
    required this.emoji,
  });

  final Product product;
  final bool showInQuickCheckout;
  final String emoji;

  factory _QuickProductItem.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return _QuickProductItem(
      product: productFromDoc(doc),
      showInQuickCheckout: data['showInQuickCheckout'] == true,
      emoji: (data['quickCheckoutEmoji'] as String?)?.trim() ?? '',
    );
  }
}
