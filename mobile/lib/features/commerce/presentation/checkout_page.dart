import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import '../domain/commerce_models.dart';
import 'addresses_page.dart';

final class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key, required this.cart});
  final ShoppingCart cart;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

final class _CheckoutPageState extends State<CheckoutPage> {
  Future<List<CustomerAddress>>? _addressesFuture;
  String _fulfillment = 'delivery';
  String _paymentMethod = 'cash_on_delivery';
  String? _addressId;
  Future<DeliveryQuote>? _quoteFuture;
  bool _submitting = false;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!widget.cart.acceptsDelivery && widget.cart.acceptsPickup) _fulfillment = 'pickup';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _addressesFuture ??= AppScope.of(context).loadAddresses();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _reloadAddresses() async {
    setState(() => _addressesFuture = AppScope.of(context).loadAddresses());
  }

  void _selectAddress(String? addressId) {
    setState(() {
      _addressId = addressId;
      _quoteFuture = addressId == null || addressId.isEmpty
          ? null
          : AppScope.of(context).deliveryQuote(
              cartId: widget.cart.publicId,
              deliveryAddressId: addressId,
            );
    });
  }

  Future<void> _submit() async {
    if (_fulfillment == 'delivery' &&
        (_addressId == null || _addressId!.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اختر عنوان توصيل أولاً.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await AppScope.of(context).checkout(
        cartId: widget.cart.publicId,
        fulfillmentType: _fulfillment,
        deliveryAddressId: _fulfillment == 'delivery' ? _addressId : null,
        paymentMethod: _paymentMethod,
        customerNote: _note.text,
      );
      if (!mounted) return;
      final order = result['order'] is Map
          ? Map<String, dynamic>.from(result['order'] as Map)
          : const <String, dynamic>{};
      final number = order['order_number'] as String? ?? 'طلبك';
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF125F4F),
            size: 38,
          ),
          title: const Text('تم إنشاء الطلب'),
          content: Text(
            _paymentMethod == 'cash_on_delivery'
                ? '$number جاهز للمتابعة. الدفع سيكون عند الاستلام.'
                : '$number أُنشئ بانتظار التحويل اليدوي وإرفاق السند.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إتمام الطلب')),
    body: FutureBuilder<List<CustomerAddress>>(
      future: _addressesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final addresses = snapshot.data ?? const <CustomerAddress>[];
        final defaults = addresses.where((item) => item.isDefault);
        final selected =
            _addressId ??
            (defaults.isNotEmpty
                ? defaults.first.publicId
                : (addresses.isEmpty ? null : addresses.first.publicId));
        if (_addressId == null && selected != null) {
          _addressId = selected;
          _quoteFuture = AppScope.of(context).deliveryQuote(
            cartId: widget.cart.publicId,
            deliveryAddressId: selected,
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            _SummaryCard(cart: widget.cart),
            const SizedBox(height: 18),
            Text(
              'طريقة الاستلام',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                if (widget.cart.acceptsDelivery) const ButtonSegment(value: 'delivery', icon: Icon(Icons.local_shipping_outlined), label: Text('توصيل')),
                if (widget.cart.acceptsPickup) const ButtonSegment(value: 'pickup', icon: Icon(Icons.store_mall_directory_outlined), label: Text('استلام مباشر')),
              ],
              selected: {_fulfillment},
              onSelectionChanged: _submitting
                  ? null
                  : (values) => setState(() {
                      _fulfillment = values.first;
                      if (_fulfillment == 'delivery' && _addressId != null) {
                        _quoteFuture = AppScope.of(context).deliveryQuote(
                          cartId: widget.cart.publicId,
                          deliveryAddressId: _addressId!,
                        );
                      }
                    }),
            ),
            if (_fulfillment == 'delivery') ...[
              const SizedBox(height: 23),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'عنوان التوصيل',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _submitting
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => const AddressesPage()),
                            );
                            if (mounted) _reloadAddresses();
                          },
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: Text(addresses.isEmpty ? 'إعداد العنوان' : 'تعديل'),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              if (addresses.isEmpty)
                _NoAddress(
                  onAdd: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const AddressesPage()),
                    );
                    if (mounted) _reloadAddresses();
                  },
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on_rounded, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('عنوان التوصيل المعتمد', style: TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text([addresses.first.city, addresses.first.district, addresses.first.addressLine1, addresses.first.addressLine2].whereType<String>().where((value) => value.trim().isNotEmpty).join('، ')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_quoteFuture != null) ...[
                const SizedBox(height: 10),
                _DeliveryQuoteCard(quoteFuture: _quoteFuture!),
              ],
            ],
            const SizedBox(height: 23),
            Text(
              'طريقة الدفع',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Card(
              child: RadioGroup<String>(
                groupValue: _paymentMethod,
                onChanged: (value) {
                  if (!_submitting && value != null) {
                    setState(() => _paymentMethod = value);
                  }
                },
                child: Column(
                  children: [
                    const RadioListTile<String>(value: 'cash_on_delivery', title: Text('الدفع عند الاستلام'), subtitle: Text('ادفع بعد استلام طلبك.')),
                    if (widget.cart.manualPayment?.enabled == true) ...[
                      const Divider(height: 1),
                      const RadioListTile<String>(value: 'manual_transfer', title: Text('تحويل يدوي'), subtitle: Text('ستظهر تعليمات الإيداع ثم ترسل إشعاراً كتابياً أو صورة إيصال.')),
                    ],
                  ],
                ),
              ),
            ),
            if (_paymentMethod == 'manual_transfer' && widget.cart.manualPayment != null) ...[
              const SizedBox(height: 10),
              _ManualDepositCard(instructions: widget.cart.manualPayment!),
            ],
            const SizedBox(height: 17),
            TextField(
              controller: _note,
              maxLength: 1000,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'ملاحظة للمتجر (اختيارية)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.lock_outline_rounded),
              label: Text(_submitting ? 'جارٍ إنشاء الطلب...' : 'تأكيد الطلب'),
            ),
            const SizedBox(height: 10),
            const Text(
              'يحسب الخادم السعر النهائي ورسوم التوصيل بأمان عند تأكيد الطلب.',
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    ),
  );
}

final class _ManualDepositCard extends StatelessWidget {
  const _ManualDepositCard({required this.instructions});
  final ManualPaymentInstructions instructions;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF7E9),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.account_balance_outlined, color: Color(0xFF8A6118)), const SizedBox(width: 8), Expanded(child: Text(instructions.depositTitle?.trim().isNotEmpty == true ? instructions.depositTitle! : 'عنوان الإيداع', style: const TextStyle(fontWeight: FontWeight.w900)))]),
        const SizedBox(height: 8),
        SelectableText(instructions.depositAddress ?? '', style: const TextStyle(height: 1.6, fontWeight: FontWeight.w700)),
        if (instructions.instructions?.trim().isNotEmpty == true) ...[const SizedBox(height: 8), Text(instructions.instructions!, style: const TextStyle(height: 1.5))],
      ]),
    ),
  );
}

final class _DeliveryQuoteCard extends StatelessWidget {
  const _DeliveryQuoteCard({required this.quoteFuture});
  final Future<DeliveryQuote> quoteFuture;

  @override
  Widget build(BuildContext context) => FutureBuilder<DeliveryQuote>(
    future: quoteFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Card(child: ListTile(leading: CircularProgressIndicator(), title: Text('جارٍ حساب مسافة الطريق ورسوم التوصيل…')));
      }
      if (snapshot.hasError) {
        final message = snapshot.error is ApiException
            ? (snapshot.error! as ApiException).message
            : 'تعذر حساب مسار التوصيل الآن.';
        return Card(color: Theme.of(context).colorScheme.errorContainer, child: ListTile(leading: const Icon(Icons.route_outlined), title: const Text('لا يمكن تأكيد توصيل هذا العنوان'), subtitle: Text(message)));
      }
      final quote = snapshot.data!;
      final minutes = (quote.durationSeconds / 60).ceil();
      return Card(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(.48),
        child: ListTile(
          leading: const Icon(Icons.route_rounded),
          title: Text('التوصيل ${quote.distanceKm.toStringAsFixed(1)} كم · نحو $minutes دقيقة'),
          subtitle: Text('الحد الأدنى ${quote.baseFee.toStringAsFixed(2)} + ${quote.perKmFee.toStringAsFixed(2)} لكل كم'),
          trailing: Text('${quote.deliveryFee.toStringAsFixed(2)} ${quote.currencyCode}', style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      );
    },
  );
}

final class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.cart});
  final ShoppingCart cart;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cart.storeName,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            '${cart.itemCount} قطعة · إجمالي المنتجات ${cart.subtotal.toStringAsFixed(2)} ${cart.currencyCode}',
          ),
        ],
      ),
    ),
  );
}

final class _NoAddress extends StatelessWidget {
  const _NoAddress({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Text('لا يوجد عنوان توصيل محفوظ.'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('إضافة عنوان الآن'),
          ),
        ],
      ),
    ),
  );
}
