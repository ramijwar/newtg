import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/network/api_exception.dart';
import '../domain/catalog_models.dart';
import '../data/catalog_repository.dart';
import 'catalog_detail_pages.dart';

/// Full store-directory filter surface matching the web stores route.
final class StoreBrowsePage extends StatefulWidget {
  const StoreBrowsePage({super.key});

  @override
  State<StoreBrowsePage> createState() => _StoreBrowsePageState();
}

final class _StoreBrowsePageState extends State<StoreBrowsePage> {
  final _search = TextEditingController();
  Future<CatalogPage<StoreSummary>>? _stores;
  Future<List<Map<String, dynamic>>>? _categories;
  String _categoryId = '';
  String _mode = '';
  String _sort = 'popular';
  int _page = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _categories ??= AppScope.of(context).loadPublicStoreCategories();
    _stores ??= _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<CatalogPage<StoreSummary>> _load() => AppScope.of(context).browseStoresPage(
        search: _search.text, categoryId: _categoryId, mode: _mode, sort: _sort, page: _page,
      );

  void _apply({bool resetPage = true}) => setState(() { if (resetPage) _page = 1; _stores = _load(); });
  void _goToPage(int page) { if (page < 1) return; setState(() { _page = page; _stores = _load(); }); }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('دليل المتاجر')),
        body: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _search,
                      maxLength: 100,
                      onSubmitted: (_) => _apply(),
                      decoration: const InputDecoration(
                        counterText: '',
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'ابحث في المتاجر',
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _categories,
                      builder: (context, snapshot) => DropdownButtonFormField<String>(
                        value: _categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'تصنيف المتجر'),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('كل التصنيفات')),
                          ...(snapshot.data ?? const <Map<String, dynamic>>[]).map(
                            (item) => DropdownMenuItem(
                              value: item['public_id'] as String? ?? '',
                              child: Text(item['name'] as String? ?? 'تصنيف'),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          _categoryId = value ?? '';
                          _apply();
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _mode,
                            decoration: const InputDecoration(labelText: 'نمط البيع'),
                            items: const [
                              DropdownMenuItem(value: '', child: Text('كل الأنماط')),
                              DropdownMenuItem(value: 'retail', child: Text('تجزئة')),
                              DropdownMenuItem(value: 'preorder', child: Text('بيع مسبق')),
                            ],
                            onChanged: (value) {
                              _mode = value ?? '';
                              _apply();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _sort,
                            decoration: const InputDecoration(labelText: 'الترتيب'),
                            items: const [
                              DropdownMenuItem(value: 'popular', child: Text('الأكثر زيارة')),
                              DropdownMenuItem(value: 'rating', child: Text('الأعلى تقييماً')),
                              DropdownMenuItem(value: 'sales', child: Text('الأكثر مبيعاً')),
                              DropdownMenuItem(value: 'newest', child: Text('الأحدث')),
                            ],
                            onChanged: (value) {
                              _sort = value ?? 'popular';
                              _apply();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<CatalogPage<StoreSummary>>(
                future: _stores,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return _StoreBrowseEmpty(icon: Icons.cloud_off_rounded, message: snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تعذر تحميل المتاجر.', action: _apply, actionLabel: 'إعادة المحاولة');
                  final result = snapshot.data!; final stores = result.items;
                  if (stores.isEmpty) return _StoreBrowseEmpty(icon: Icons.storefront_outlined, message: 'لا توجد متاجر تطابق عوامل التصفية الحالية.', action: _apply, actionLabel: 'تحديث');
                  return Column(children: [Expanded(child: RefreshIndicator(onRefresh: () async => _apply(resetPage: false), child: ListView.separated(padding: const EdgeInsets.all(16), itemCount: stores.length + (result.banners.isEmpty ? 0 : 1), separatorBuilder: (_, _) => const SizedBox(height: 9), itemBuilder: (context, index) { if (result.banners.isNotEmpty && index == 0) return StoreBannerStrip(banners: result.banners, title: 'إعلانات مميزة'); final storeIndex = index - (result.banners.isEmpty ? 0 : 1); return _StoreResultCard(store: stores[storeIndex]); }))), _StoreBrowsePager(page: result.page, totalPages: result.totalPages, total: result.total, onPage: _goToPage)]);
                },
              ),
            ),
          ],
        ),
      );
}

final class _StoreBrowsePager extends StatelessWidget {
  const _StoreBrowsePager({required this.page, required this.totalPages, required this.total, required this.onPage});
  final int page; final int totalPages; final int total; final ValueChanged<int> onPage;
  @override Widget build(BuildContext context) { if (totalPages <= 1) return Padding(padding: const EdgeInsets.all(12), child: Text('$total متجر', textAlign: TextAlign.center)); return SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: Row(children: [OutlinedButton.icon(onPressed: page <= 1 ? null : () => onPage(page - 1), icon: const Icon(Icons.chevron_right_rounded), label: const Text('السابق')), Expanded(child: Text('صفحة $page من $totalPages · $total متجر', textAlign: TextAlign.center)), OutlinedButton.icon(onPressed: page >= totalPages ? null : () => onPage(page + 1), icon: const Icon(Icons.chevron_left_rounded), label: const Text('التالي'))]))); }
}

final class _StoreResultCard extends StatelessWidget {
  const _StoreResultCard({required this.store});
  final StoreSummary store;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: SizedBox(
            width: 52,
            height: 52,
            child: store.logoMediaPublicId?.trim().isEmpty != false
                ? DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xFFD9F0E8)),
                    child: Center(
                      child: Text(
                        store.name.trim().isEmpty ? 'ت' : store.name.trim().substring(0, 1),
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 21),
                      ),
                    ),
                  )
                : CachedMediaImage(mediaPublicId: store.logoMediaPublicId!, fit: BoxFit.cover),
          ),
          title: Row(children: [Expanded(child: Text(store.name, style: const TextStyle(fontWeight: FontWeight.w900))), if (store.isVerified) const Icon(Icons.verified_rounded, color: Color(0xFF2585E6), size: 19)]),
          subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [Expanded(child: Text('${store.categoryName ?? 'متجر محلي'} · ${store.productCount} منتج')), if (store.acceptsDelivery) const Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(Icons.local_shipping_outlined, size: 17, color: Color(0xFF237A4B))), if (store.acceptsPickup) const Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(Icons.storefront_outlined, size: 17, color: Color(0xFF237A4B)))])),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => StoreDetailsPage(storeId: store.publicId, storeName: store.name)),
          ),
        ),
      );
}

final class _StoreBrowseEmpty extends StatelessWidget {
  const _StoreBrowseEmpty({required this.icon, required this.message, required this.action, required this.actionLabel});
  final IconData icon;
  final String message;
  final VoidCallback action;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: action, icon: const Icon(Icons.refresh_rounded), label: Text(actionLabel)),
            ],
          ),
        ),
      );
}
