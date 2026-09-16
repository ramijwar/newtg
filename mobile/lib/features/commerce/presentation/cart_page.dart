import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/network/api_exception.dart';
import '../domain/commerce_models.dart';
import 'checkout_page.dart';

final class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final isCustomer = controller.session?.roles.contains('customer') == true;
    return Scaffold(
      appBar: AppBar(title: const Text('سلة المشتريات')),
      body: !isCustomer
          ? const _CartAccessNotice()
          : RefreshIndicator(
              onRefresh: controller.refreshCarts,
              child: _CartBody(
                carts: controller.carts,
                loading: controller.isCartLoading,
              ),
            ),
    );
  }
}

final class _CartAccessNotice extends StatelessWidget {
  const _CartAccessNotice();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 45,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              const Text(
                'السلة متاحة لحساب العميل',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'سجّل الدخول أو أنشئ حساب عميل لإضافة المنتجات وإتمام الطلبات.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _CartBody extends StatelessWidget {
  const _CartBody({required this.carts, required this.loading});
  final List<ShoppingCart> carts;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading && carts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (carts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: const [SizedBox(height: 80), _EmptyCart()],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      itemCount: carts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, index) => _CartCard(cart: carts[index]),
    );
  }
}

final class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 46,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          const Text(
            'سلتك فارغة',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          const Text(
            'تصفّح متجراً وأضف منتجاتك المفضلة هنا.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

final class _CartCard extends StatelessWidget {
  const _CartCard({required this.cart});
  final ShoppingCart cart;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Icon(
                    Icons.storefront_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cart.storeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '${cart.itemCount} قطعة',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const Divider(height: 25),
            ...cart.items.map(
              (item) => _CartItemRow(
                cart: cart,
                item: item,
                busy: controller.isCartMutating,
              ),
            ),
            const Divider(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'الإجمالي المبدئي',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  _money(cart.subtotal, cart.currencyCode),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            FilledButton.icon(
              onPressed: controller.isCartMutating
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CheckoutPage(cart: cart),
                      ),
                    ),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('إتمام طلب هذا المتجر'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CartItemRow extends StatelessWidget {
  const _CartItemRow({
    required this.cart,
    required this.item,
    required this.busy,
  });
  final ShoppingCart cart;
  final CartItem item;
  final bool busy;

  Future<void> _change(BuildContext context, int quantity) async {
    final controller = AppScope.of(context);
    try {
      await controller.changeCartQuantity(
        cartId: cart.publicId,
        productId: item.productPublicId,
        quantity: quantity,
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 54,
            height: 54,
            child: item.mediaPublicId == null
                ? const ColoredBox(
                    color: Color(0xFFE7EEE9),
                    child: Icon(Icons.inventory_2_outlined),
                  )
                : CachedMediaImage(mediaPublicId: item.mediaPublicId!),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                _money(item.effectivePrice, item.currencyCode),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            IconButton(
              onPressed: busy
                  ? null
                  : () => _change(context, item.quantity - 1),
              icon: const Icon(Icons.remove_circle_outline_rounded),
              tooltip: 'إنقاص الكمية',
            ),
            Text(
              '${item.quantity}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            IconButton(
              onPressed: busy || item.quantity >= item.availableStock
                  ? null
                  : () => _change(context, item.quantity + 1),
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: 'زيادة الكمية',
            ),
          ],
        ),
      ],
    ),
  );
}

String _money(num amount, String currency) =>
    '${amount.toStringAsFixed(2)} $currency';
