import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/network/api_exception.dart';
import '../../catalog/domain/catalog_models.dart';
import '../data/workspace_repository.dart';
import 'product_editor_page.dart';

/// Dedicated merchant inventory page. Store settings are intentionally kept in
/// MerchantWorkspacePage so an inventory parsing issue cannot obscure settings.
final class MerchantProductsPage extends StatefulWidget {
  const MerchantProductsPage({super.key});

  @override
  State<MerchantProductsPage> createState() => _MerchantProductsPageState();
}

final class _MerchantProductsPageState extends State<MerchantProductsPage> {
  late Future<MerchantWorkspace> _future;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _future = AppScope.of(context).loadMerchantWorkspace();
    }
  }

  void _reload() => setState(() => _future = AppScope.of(context).loadMerchantWorkspace());

  Future<void> _openEditor(Map<String, dynamic> store, [StoreProduct? product]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProductEditorPage(
          currencyCode: store['currency_code'] as String? ?? product?.currencyCode ?? 'USD',
          canPublish: store['store_status'] == 'active',
          product: product,
        ),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المنتجات')),
    floatingActionButton: FutureBuilder<MerchantWorkspace>(
      future: _future,
      builder: (context, snapshot) {
        final store = snapshot.data?.store;
        if (store == null) return const SizedBox.shrink();
        return FloatingActionButton.extended(
          onPressed: () => _openEditor(store),
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('إضافة منتج'),
        );
      },
    ),
    body: FutureBuilder<MerchantWorkspace>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تعذر تحميل المنتجات.';
          return _ProductsState(icon: Icons.cloud_off_rounded, message: message, action: _reload, actionLabel: 'إعادة المحاولة');
        }
        final workspace = snapshot.data!;
        final store = workspace.store;
        if (store == null) return _ProductsState(icon: Icons.storefront_outlined, message: 'أكمل إعدادات المتجر أولاً قبل إدارة المنتجات.', action: () => Navigator.of(context).pop(), actionLabel: 'إعدادات المتجر');
        if (workspace.products.isEmpty) {
          return _ProductsState(icon: Icons.inventory_2_outlined, message: 'لا توجد منتجات بعد.', action: () => _openEditor(store), actionLabel: 'إضافة منتج');
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
            itemCount: workspace.products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 9),
            itemBuilder: (_, index) => _MerchantProductRow(
              product: workspace.products[index],
              onTap: () => _openEditor(store, workspace.products[index]),
            ),
          ),
        );
      },
    ),
  );
}

final class _MerchantProductRow extends StatelessWidget {
  const _MerchantProductRow({required this.product, required this.onTap});
  final StoreProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.all(10),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          width: 58,
          height: 58,
          child: product.mediaPublicId == null
              ? const ColoredBox(color: Color(0xFFECEFF1), child: Icon(Icons.image_outlined))
              : CachedMediaImage(mediaPublicId: product.mediaPublicId!, errorIcon: Icons.broken_image_outlined),
        ),
      ),
      title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text('${product.effectivePrice} ${product.currencyCode} · مخزون ${product.stockQuantity} · ${_status(product.productStatus)}'),
      trailing: const Icon(Icons.chevron_left_rounded),
    ),
  );

  String _status(String value) => switch (value) {
    'active' => 'منشور',
    'draft' => 'مسودة',
    'hidden' => 'مخفي',
    _ => value,
  };
}

final class _ProductsState extends StatelessWidget {
  const _ProductsState({required this.icon, required this.message, required this.action, required this.actionLabel});
  final IconData icon;
  final String message;
  final VoidCallback action;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: action, icon: const Icon(Icons.add_rounded), label: Text(actionLabel)),
      ]),
    ),
  );
}
