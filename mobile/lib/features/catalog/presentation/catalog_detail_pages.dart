import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/network/api_exception.dart';
import '../domain/catalog_models.dart';
import 'comments_page.dart';
import 'marketplace_activity_page.dart';
import 'store_engagement_panel.dart';

final class StoreDetailsPage extends StatefulWidget {
  const StoreDetailsPage({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  final String storeId;
  final String storeName;

  @override
  State<StoreDetailsPage> createState() => _StoreDetailsPageState();
}

final class _StoreDetailsPageState extends State<StoreDetailsPage> {
  Future<StoreDetails>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).loadStoreDetails(widget.storeId);
  }

  void _retry() => setState(
    () => _future = AppScope.of(context).loadStoreDetails(widget.storeId),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.storeName)),
    body: FutureBuilder<StoreDetails>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _LoadFailure(onRetry: _retry);
        }
        return _StoreContent(details: snapshot.data!);
      },
    ),
  );
}

final class ListingDetailsPage extends StatefulWidget {
  const ListingDetailsPage({
    super.key,
    required this.listingId,
    required this.title,
  });

  final String listingId;
  final String title;

  @override
  State<ListingDetailsPage> createState() => _ListingDetailsPageState();
}

final class _ListingDetailsPageState extends State<ListingDetailsPage> {
  Future<ListingDetails>? _future;
  bool _isFavorite = false;
  bool _favoriteBusy = false;

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    setState(() => _favoriteBusy = true);
    try {
      final next = !_isFavorite;
      final confirmed = await AppScope.of(context).setMarketplaceFavorite(
        listingId: widget.listingId,
        enabled: next,
      );
      if (mounted) setState(() => _isFavorite = confirmed);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _loadDetails();
  }

  Future<ListingDetails> _loadDetails() async {
    final details = await AppScope.of(context).loadListingDetails(widget.listingId);
    if (mounted) setState(() => _isFavorite = details.listing.isFavorite);
    return details;
  }

  void _retry() => setState(() => _future = _loadDetails());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('تفاصيل الإعلان'),
      actions: [
        IconButton(
          tooltip: _isFavorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
          onPressed: _favoriteBusy ? null : _toggleFavorite,
          icon: Icon(
            _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          ),
        ),
      ],
    ),
    body: FutureBuilder<ListingDetails>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _LoadFailure(onRetry: _retry);
        }
        return _ListingContent(details: snapshot.data!, onCommentsChanged: _retry);
      },
    ),
  );
}

final class ProductDetailsPage extends StatefulWidget {
  const ProductDetailsPage({
    super.key,
    required this.productId,
    required this.title,
  });
  final String productId;
  final String title;

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

final class _ProductDetailsPageState extends State<ProductDetailsPage> {
  Future<ProductDetails>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).loadProductDetails(widget.productId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<ProductDetails>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData)
          return _LoadFailure(
            onRetry: () => setState(
              () =>
                  _future = AppScope.of(context)
                      .loadProductDetails(widget.productId),
            ),
          );
        final details = snapshot.data!;
        final product = details.product;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            if (details.isStale)
              _StaleBanner(lastSyncedAt: details.lastSyncedAt),
            if (product.mediaPublicId != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 1.25,
                  child: CachedMediaImage(
                    mediaPublicId: product.mediaPublicId!,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              product.name,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _price(product.effectivePrice, product.currencyCode),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 21,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            if (product.description?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  product.description!,
                  style: const TextStyle(height: 1.6),
                ),
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.visibility_outlined,
                  label: '${product.viewCount} مشاهدة',
                ),
                _InfoChip(
                  icon: Icons.forum_outlined,
                  label: '${product.commentCount} تعليق',
                ),
                _InfoChip(
                  icon: Icons.inventory_2_outlined,
                  label: 'المتاح ${product.stockQuantity}',
                ),
              ],
            ),
            const SizedBox(height: 22),
            _ProductCommentsSection(productId: product.publicId, initialCount: product.commentCount),
            if (AppScope.of(context).session?.roles.contains('admin') ==
                true) ...[
              const SizedBox(height: 10),
              _AdminContentDeleteButton(
                kind: 'product',
                publicId: product.publicId,
              ),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: product.fulfillmentMode == 'retail' && product.stockQuantity <= 0
                  ? null
                  : () async {
                      final app = AppScope.of(context);
                      if (!app.isCustomer) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سجّل الدخول بحساب عميل لإضافة المنتج إلى السلة.')));
                        return;
                      }
                      try {
                        await app.addProductToCart(product.publicId);
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المنتج إلى السلة.')));
                      } on ApiException catch (error) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
                      } catch (_) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر إضافة المنتج إلى السلة.')));
                      }
                    },
              icon: Icon(product.fulfillmentMode == 'retail' && product.stockQuantity <= 0 ? Icons.inventory_2_outlined : Icons.add_shopping_cart_rounded),
              label: Text(product.fulfillmentMode == 'retail' && product.stockQuantity <= 0 ? 'نفد المخزون' : 'أضف إلى السلة'),
            ),
          ],
        );
      },
    ),
  );
}

final class _ProductCommentsSection extends StatefulWidget {
  const _ProductCommentsSection({required this.productId, required this.initialCount});
  final String productId;
  final int initialCount;
  @override
  State<_ProductCommentsSection> createState() => _ProductCommentsSectionState();
}

final class _ProductCommentsSectionState extends State<_ProductCommentsSection> {
  Future<List<ContentComment>>? _future;
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).loadContentComments(kind: 'product', publicId: widget.productId);
  }

  @override
  void dispose() { _body.dispose(); super.dispose(); }

  void _reload() => setState(() => _future = AppScope.of(context).loadContentComments(kind: 'product', publicId: widget.productId));

  Future<void> _send() async {
    if (_body.text.trim().isEmpty) return;
    if (AppScope.of(context).session == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سجّل الدخول لإضافة تعليق.')));
      return;
    }
    setState(() => _sending = true);
    try {
      await AppScope.of(context).addContentComment(kind: 'product', publicId: widget.productId, body: _body.text);
      _body.clear(); _reload();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ContentComment>>(
    future: _future,
    builder: (context, snapshot) {
      final comments = snapshot.data ?? const <ContentComment>[];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('التعليقات (${snapshot.hasData ? comments.length : widget.initialCount})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))), IconButton(onPressed: _sending ? null : _reload, tooltip: 'تحديث التعليقات', icon: const Icon(Icons.refresh_rounded))]),
        if (snapshot.connectionState != ConnectionState.done)
          const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()))
        else if (snapshot.hasError)
          OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), label: const Text('تعذر تحميل التعليقات — إعادة المحاولة'))
        else if (comments.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('لا توجد تعليقات بعد. كن أول من يكتب تعليقاً.'))
        else
          ...comments.map((comment) => Card(
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _InlineCommentAvatar(name: comment.authorName, mediaPublicId: comment.authorAvatarMediaPublicId),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(comment.authorName, style: const TextStyle(fontWeight: FontWeight.w900))), if (comment.authorIsAdmin) const Icon(Icons.verified_rounded, size: 17, color: Color(0xFF1671C6))]),
                  const SizedBox(height: 5), Text(comment.body, style: const TextStyle(height: 1.55)),
                ])),
              ]),
            ),
          )),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(controller: _body, enabled: !_sending, maxLength: 1500, minLines: 1, maxLines: 4, decoration: const InputDecoration(counterText: '', hintText: 'اكتب تعليقاً محترماً…'))),
          const SizedBox(width: 8), IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded)),
        ]),
      ]);
    },
  );
}

final class _InlineCommentAvatar extends StatelessWidget {
  const _InlineCommentAvatar({required this.name, this.mediaPublicId});
  final String name; final String? mediaPublicId;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 21,
    backgroundColor: const Color(0xFFD9F0E8),
    child: ClipOval(child: SizedBox.square(dimension: 42, child: mediaPublicId?.trim().isNotEmpty == true ? CachedMediaImage(mediaPublicId: mediaPublicId!, fit: BoxFit.cover) : Center(child: Text(name.trim().isEmpty ? 'م' : name.trim().substring(0, 1), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900))))),
  );
}

final class _ProductStockBadge extends StatelessWidget {
  const _ProductStockBadge({required this.product});
  final StoreProduct product;
  @override
  Widget build(BuildContext context) {
    final preorder = product.fulfillmentMode == 'preorder';
    final empty = !preorder && product.stockQuantity <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: empty ? const Color(0xFFC63C32) : Colors.white.withOpacity(.94), borderRadius: BorderRadius.circular(9)),
      child: Text(preorder ? 'طلب مسبق' : empty ? 'نفد' : 'متاح: ${product.stockQuantity}', style: TextStyle(color: empty ? Colors.white : const Color(0xFF196B50), fontWeight: FontWeight.w900, fontSize: 10)),
    );
  }
}

final class _StoreContent extends StatefulWidget {
  const _StoreContent({required this.details});
  final StoreDetails details;
  @override
  State<_StoreContent> createState() => _StoreContentState();
}

final class _StoreContentState extends State<_StoreContent> {
  final _search = TextEditingController();
  bool _availableOnly = false;

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    final store = details.store;
    final needle = _search.text.trim().toLowerCase();
    final products = details.products.where((product) {
      final matches = needle.isEmpty || product.name.toLowerCase().contains(needle) || (product.categoryName ?? '').toLowerCase().contains(needle);
      final available = product.fulfillmentMode == 'preorder' || product.stockQuantity > 0;
      return matches && (!_availableOnly || available);
    }).toList(growable: false);
    final address = [store.addressLine1, store.addressDistrict, store.addressCity, store.addressCountryCode].whereType<String>().where((part) => part.trim().isNotEmpty).join('، ');
    return ColoredBox(
      color: const Color(0xFFF9FAFB),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          if (details.isStale) _StaleBanner(lastSyncedAt: details.lastSyncedAt),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            _StoreAvatar(store: store, radius: 41),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(store.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: const Color(0xFF102D45)))), if (store.isVerified) const Padding(padding: EdgeInsetsDirectional.only(start: 6), child: Icon(Icons.verified_rounded, color: Color(0xFF16A28A), size: 23))]),
              const SizedBox(height: 4), Text(store.categoryName ?? 'متجر محلي', style: const TextStyle(color: Color(0xFF687782), fontSize: 16)),
              if (store.discoveryTagline?.trim().isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 4), child: Text(store.discoveryTagline!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF49616B)))),
            ])),
          ]),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
            decoration: BoxDecoration(color: const Color(0xFFF0FAF8), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              _StoreOverviewMetric(icon: Icons.visibility_outlined, value: '${store.viewCount}', label: 'زيارة'),
              _StoreOverviewMetric(icon: Icons.people_outline_rounded, value: '${store.followerCount}', label: 'متابع'),
              _StoreOverviewMetric(icon: Icons.inventory_2_outlined, value: '${store.productCount}', label: 'منتج'),
            ]),
          ),
          const SizedBox(height: 15),
          _StoreTodayHoursCard(hours: store.businessHours, holidays: store.holidays),
          const SizedBox(height: 14),
          _StoreContactPanel(phone: store.phone, whatsapp: store.whatsappPhone, address: address),
          const SizedBox(height: 14),
          _StoreReviewSummary(rating: store.averageRating, count: store.reviewCount),
          if (store.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE7ECEB))), child: Text(store.description!, style: const TextStyle(height: 1.65, color: Color(0xFF475861)))),
          ],
          if (details.banners.isNotEmpty) ...[
            const SizedBox(height: 17), StoreBannerStrip(banners: details.banners, title: 'إعلانات المتجر'),
          ],
          const SizedBox(height: 22),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'ابحث داخل منتجات ${store.name}',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFFD6DFDE))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFFD6DFDE))),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            FilterChip(
              avatar: const Icon(Icons.inventory_2_outlined, size: 17),
              label: const Text('المتاح فقط'),
              selected: _availableOnly,
              onSelected: (value) => setState(() => _availableOnly = value),
              selectedColor: const Color(0xFFDDF5EB),
            ),
            const Spacer(),
            Text('${products.length} منتج', style: const TextStyle(color: Color(0xFF237A69), fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          if (products.isEmpty)
            const _EmptyDetail(icon: Icons.inventory_2_outlined, title: 'لا توجد منتجات مطابقة', body: 'جرّب عبارة بحث أخرى أو اعرض جميع المنتجات.')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: products.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 11, mainAxisSpacing: 11, childAspectRatio: .64),
              itemBuilder: (_, index) => _ProductCard(
                product: products[index],
                onOpen: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProductDetailsPage(productId: products[index].publicId, title: products[index].name))),
                onAdd: () async {
                  final controller = AppScope.of(context);
                  if (!controller.isCustomer) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سجّل الدخول بحساب عميل لإضافة المنتج إلى السلة.')));
                    return;
                  }
                  try {
                    await controller.addProductToCart(products[index].publicId);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المنتج إلى سلة المشتريات.')));
                  } on ApiException catch (error) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
                  }
                },
              ),
            ),
          const SizedBox(height: 24),
          StoreEngagementPanel(storeId: store.publicId),
        ],
      ),
    );
  }
}

final class _StoreOverviewMetric extends StatelessWidget {
  const _StoreOverviewMetric({required this.icon, required this.value, required this.label});
  final IconData icon; final String value; final String label;
  @override
  Widget build(BuildContext context) => Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: const Color(0xFF149D8C), size: 23), const SizedBox(width: 5), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF153246))), Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6D7E87)))]) ]));
}

final class _StoreTodayHoursCard extends StatelessWidget {
  const _StoreTodayHoursCard({required this.hours, required this.holidays});
  final Map<String, dynamic> hours; final List<Map<String, dynamic>> holidays;
  static const _days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  @override
  Widget build(BuildContext context) {
    final day = _days[DateTime.now().weekday - 1];
    final raw = hours[day] is Map ? Map<String, dynamic>.from(hours[day] as Map) : const <String, dynamic>{};
    final closed = raw['closed'] == true || holidays.any((holiday) => '${holiday['date']}' == _dateValue(DateTime.now()));
    final opens = raw['opens_at'] as String? ?? '—'; final closes = raw['closes_at'] as String? ?? '—';
    final hasHours = raw.isNotEmpty && !closed;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: const Color(0xFFFFF8EC), borderRadius: BorderRadius.circular(22)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.schedule_rounded, color: Color(0xFF9B7320), size: 30), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('أوقات الدوام', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF153246))),
          const SizedBox(height: 6), Text(closed ? 'مغلق اليوم' : hasHours ? '$opens — $closes' : 'لم يعلن المتجر أوقات الدوام بعد', style: TextStyle(fontWeight: FontWeight.w900, fontSize: hasHours ? 20 : 14, color: const Color(0xFF1B3446))),
          const SizedBox(height: 5), Text(closed ? 'العطلة أو الإغلاق اليومي' : 'الأوقات المعروضة بحسب يومك الحالي', style: const TextStyle(color: Color(0xFF78838A))),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: closed ? const Color(0xFFFCE7E3) : const Color(0xFFDDF8E8), borderRadius: BorderRadius.circular(20)), child: Text(closed ? 'مغلق' : 'متاح اليوم', style: TextStyle(color: closed ? const Color(0xFFAC3D34) : const Color(0xFF248551), fontWeight: FontWeight.w900))),
      ]),
    );
  }
  String _dateValue(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

final class _StoreContactPanel extends StatelessWidget {
  const _StoreContactPanel({this.phone, this.whatsapp, required this.address});
  final String? phone; final String? whatsapp; final String address;
  Future<void> _open(BuildContext context, String uri) async { if (!await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication) && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح وسيلة الاتصال.'))); }
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: const Color(0xFFF0FBF8), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFB8E6DB))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.phone_in_talk_outlined, color: Color(0xFF169D8B)), const SizedBox(width: 9), const Text('رقم المتجر', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), const Spacer(), SelectableText(phone?.trim().isNotEmpty == true ? phone! : 'غير معلن', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF102D45)))]),
      if (address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF637680)))),
      if (phone?.trim().isNotEmpty == true || whatsapp?.trim().isNotEmpty == true) ...[
        const SizedBox(height: 13), Row(children: [
          if (phone?.trim().isNotEmpty == true) Expanded(child: OutlinedButton.icon(onPressed: () => _open(context, 'tel:${phone!.replaceAll(RegExp(r'[^0-9+]'), '')}'), icon: const Icon(Icons.phone_outlined), label: const Text('اتصال'))),
          if (phone?.trim().isNotEmpty == true && whatsapp?.trim().isNotEmpty == true) const SizedBox(width: 9),
          if (whatsapp?.trim().isNotEmpty == true) Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF20AE74)), onPressed: () => _open(context, 'https://wa.me/${whatsapp!.replaceAll(RegExp(r'[^0-9]'), '')}'), icon: const Icon(Icons.chat_bubble_outline_rounded), label: const Text('واتساب'))),
        ]),
      ],
    ]),
  );
}

final class _StoreReviewSummary extends StatelessWidget {
  const _StoreReviewSummary({required this.rating, required this.count});
  final num rating; final int count;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x0A112E40), blurRadius: 14, offset: Offset(0, 5))]),
    child: Row(children: [
      const Icon(Icons.star_rounded, color: Color(0xFFF3AB48), size: 32), const SizedBox(width: 9), Text('${rating.toStringAsFixed(1)} من 5', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF153246))), const SizedBox(width: 8), Text('($count مراجعة)', style: const TextStyle(color: Color(0xFF697983))), const Spacer(), TextButton(onPressed: () {}, child: const Text('تحديث')),
    ]),
  );
}

final class _StoreTrustBadge extends StatelessWidget {
  const _StoreTrustBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: const Color(0xFFE1F2FF), borderRadius: BorderRadius.circular(99)),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.verified_rounded, size: 15, color: Color(0xFF1671C6)), SizedBox(width: 4), Text('متجر موثّق', style: TextStyle(color: Color(0xFF1264B1), fontSize: 11, fontWeight: FontWeight.w900))]),
  );
}

final class _StoreModeBadge extends StatelessWidget {
  const _StoreModeBadge({required this.icon, required this.label});
  final IconData icon; final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(color: const Color(0x22FFFFFF), border: Border.all(color: const Color(0x44FFFFFF)), borderRadius: BorderRadius.circular(11)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: Colors.white), const SizedBox(width: 5), Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))]),
  );
}

final class _StoreMetric extends StatelessWidget {
  const _StoreMetric({required this.icon, required this.value, required this.label});
  final IconData icon; final String value; final String label;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 104),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(13)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 17, color: const Color(0xFFD9F9E4)), const SizedBox(width: 6), Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: Color(0xFFD8F4E1), fontSize: 10))])]),
  );
}

final class _StoreSalesBadge extends StatelessWidget {
  const _StoreSalesBadge({required this.count}); final int count;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(11)), child: Text('$count مبيعات', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 11)));
}

final class _ListingContent extends StatelessWidget {
  const _ListingContent({required this.details, required this.onCommentsChanged});
  final ListingDetails details;
  final VoidCallback onCommentsChanged;

  @override
  Widget build(BuildContext context) {
    final listing = details.listing;
    final location = [
      listing.district,
      listing.city,
      listing.countryCode,
    ].whereType<String>().where((item) => item.trim().isNotEmpty).join('، ');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (details.isStale) _StaleBanner(lastSyncedAt: details.lastSyncedAt),
        _ListingGallery(mediaIds: details.mediaPublicIds),
        const SizedBox(height: 18),
        Text(
          listing.categoryName ?? 'الحراج',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          listing.title,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900, height: 1.25),
        ),
        const SizedBox(height: 10),
        Text(
          _price(listing.priceAmount, listing.currencyCode),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        if (listing.isNegotiable) ...[
          const SizedBox(height: 4),
          const Text('السعر قابل للتفاوض', style: TextStyle(fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 18),
        Text('وصف الإعلان', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 7),
        Text(
          listing.description?.trim().isNotEmpty == true
              ? listing.description!
              : 'لم يضف البائع وصفاً إضافياً لهذا الإعلان.',
          style: const TextStyle(height: 1.7, fontSize: 16),
        ),
        const SizedBox(height: 18),
        _ListingStatistics(viewCount: listing.viewCount, commentCount: listing.commentCount),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('معلومات الإعلان', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                _ListingFact(icon: Icons.category_outlined, label: 'القسم', value: listing.categoryName ?? 'غير محدد'),
                _ListingFact(icon: Icons.sell_outlined, label: 'نوع الإعلان', value: _listingType(listing.listingType)),
                _ListingFact(icon: Icons.location_on_outlined, label: 'الموقع', value: location.isEmpty ? 'لم يحدد البائع الموقع بدقة' : location),
                if (listing.itemCondition?.isNotEmpty == true)
                  _ListingFact(icon: Icons.verified_outlined, label: 'الحالة', value: _condition(listing.itemCondition!)),
                if (listing.fulfillmentMethod?.isNotEmpty == true)
                  _ListingFact(icon: Icons.local_shipping_outlined, label: 'الاستلام', value: _fulfillment(listing.fulfillmentMethod!)),
                if (listing.publishedAt?.isNotEmpty == true)
                  _ListingFact(icon: Icons.schedule_outlined, label: 'تاريخ النشر', value: _dateLabel(listing.publishedAt!)),
              ],
            ),
          ),
        ),
        if (details.attributes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('المواصفات', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  ...details.attributes.map((attribute) => _ListingFact(
                    icon: Icons.tune_rounded,
                    label: attribute.label,
                    value: _attributeValue(attribute),
                  )),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('البائع', style: TextStyle(fontSize: 12)),
                      Text(
                        listing.sellerName ?? 'مستخدم تجارتي',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.verified_user_outlined),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CommentsPage(
                  kind: 'listing',
                  publicId: listing.publicId,
                  title: listing.title,
                ),
              ),
            );
            onCommentsChanged();
          }, 
          icon: const Icon(Icons.forum_outlined),
          label: Text('التعليقات (${listing.commentCount})'),
        ),
        if (AppScope.of(context).session?.roles.contains('admin') == true) ...[
          const SizedBox(height: 9),
          _AdminContentDeleteButton(
            kind: 'listing',
            publicId: listing.publicId,
          ),
        ],
        const SizedBox(height: 9),
        OutlinedButton.icon(
          onPressed: () async {
            final reason = TextEditingController();
            final details = TextEditingController();
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('الإبلاغ عن الإعلان'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: reason, decoration: const InputDecoration(labelText: 'سبب البلاغ *')),
                    const SizedBox(height: 8),
                    TextField(controller: details, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'تفاصيل إضافية')),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
                  FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('إرسال البلاغ')),
                ],
              ),
            );
            final reasonText = reason.text.trim();
            final detailsText = details.text.trim();
            reason.dispose();
            details.dispose();
            if (confirmed != true || reasonText.length < 2 || !context.mounted) return;
            try {
              await AppScope.of(context).reportMarketplaceListing(
                listingId: listing.publicId,
                reasonCode: reasonText,
                details: detailsText,
              );
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال البلاغ للمراجعة.')));
            } on ApiException catch (error) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
            }
          },
          icon: const Icon(Icons.flag_outlined),
          label: const Text('الإبلاغ عن الإعلان'),
        ),
        if (listing.sellerPublicId?.isNotEmpty == true) ...[
          const SizedBox(height: 9),
          TextButton.icon(
            onPressed: () async {
              final blocked = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('حظر المستخدم'),
                  content: const Text('لن تتمكن من مراسلة هذا المستخدم أو تقديم عروض لإعلاناته بعد الحظر.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
                    FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('حظر')),
                  ],
                ),
              );
              if (blocked != true || !context.mounted) return;
              try {
                await AppScope.of(context).setMarketplaceUserBlock(
                  userId: listing.sellerPublicId!,
                  blocked: true,
                );
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حظر المستخدم.')));
              } on ApiException catch (error) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
              }
            },
            icon: const Icon(Icons.block_outlined),
            label: const Text('حظر المستخدم'),
          ),
        ],
        const SizedBox(height: 9),
        FilledButton.icon(
          onPressed: () async { 
            try {
              final conversation = await AppScope.of(context)
                  .startMarketplaceConversation(listing.publicId);
              final conversationId = conversation['public_id'] as String? ?? '';
              if (!context.mounted || conversationId.isEmpty) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MarketplaceConversationPage(
                    conversationId: conversationId,
                    title: listing.title,
                  ),
                ),
              );
            } on ApiException catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error.message)),
                );
              }
            }
          },
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('مراسلة البائع'),
        ),
      ],
    );
  }

  String _condition(String value) => switch (value) {
    'new' => 'جديد',
    'used' => 'مستعمل',
    'not_applicable' => 'غير محددة',
    _ => 'غير محددة',
  };

  String _fulfillment(String value) => switch (value) {
    'delivery' => 'توصيل',
    'pickup' => 'استلام مباشر',
    'not_applicable' => 'غير محددة',
    _ => 'غير محددة',
  };

  String _listingType(String? value) => switch (value) {
    'service' => 'خدمة',
    'goods' => 'سلعة',
    _ => 'إعلان حراج',
  };

  String _attributeValue(ListingAttribute attribute) {
    if (attribute.fieldType == 'boolean') {
      return ['true', '1', 'yes'].contains(attribute.value.toLowerCase()) ? 'نعم' : 'لا';
    }
    return attribute.value;
  }

  String _dateLabel(String value) => value.replaceFirst('T', ' ').replaceFirst('.000000Z', '').replaceFirst('Z', '');
}

final class _ListingStatistics extends StatelessWidget {
  const _ListingStatistics({required this.viewCount, required this.commentCount});
  final int viewCount;
  final int commentCount;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _stat(context, Icons.visibility_outlined, '$viewCount')),
      const SizedBox(width: 10),
      Expanded(child: _stat(context, Icons.forum_outlined, '$commentCount')),
    ],
  );

  Widget _stat(BuildContext context, IconData icon, String number) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 9),
        Text(number, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
      ],
    ),
  );
}

final class _ListingFact extends StatelessWidget {
  const _ListingFact({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 9),
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(width: 10),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

final class _ListingGallery extends StatefulWidget {
  const _ListingGallery({required this.mediaIds});
  final List<String> mediaIds;

  @override
  State<_ListingGallery> createState() => _ListingGalleryState();
}

final class _ListingGalleryState extends State<_ListingGallery> {
  int _active = 0;

  @override
  Widget build(BuildContext context) {
    final mediaIds = widget.mediaIds;
    if (mediaIds.isEmpty) {
      return Container(
        height: 280,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFE7EEE9),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, size: 52, color: Color(0xFF719286)),
            SizedBox(height: 8),
            Text('لم يضف البائع صورة لهذا الإعلان بعد.'),
          ],
        ),
      );
    }
    return SizedBox(
      height: 285,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              itemCount: mediaIds.length,
              onPageChanged: (index) => setState(() => _active = index),
              itemBuilder: (context, index) => SizedBox.expand(
                child: CachedMediaImage(
                  mediaPublicId: mediaIds[index],
                  fit: BoxFit.cover,
                  errorIcon: Icons.broken_image_outlined,
                ),
              ),
            ),
            if (mediaIds.length > 1)
              PositionedDirectional(
                end: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Text('${_active + 1} / ${mediaIds.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onAdd,
    required this.onOpen,
  });
  final StoreProduct product;
  final Future<void> Function() onAdd;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    color: product.isActiveSpecialOffer ? const Color(0xFFFFF6F4) : null,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: product.isActiveSpecialOffer ? const Color(0xFFFF4C3D) : Colors.transparent, width: product.isActiveSpecialOffer ? 2 : 0)),
    elevation: product.isActiveSpecialOffer ? 7 : 1,
    shadowColor: product.isActiveSpecialOffer ? const Color(0x99FF4234) : null,
    child: InkWell(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                  product.mediaPublicId == null ? const ColoredBox(color: Color(0xFFE7EEE9), child: Icon(Icons.inventory_2_outlined, color: Color(0xFF719286))) : CachedMediaImage(mediaPublicId: product.mediaPublicId!, fit: BoxFit.cover),
                  if (product.isActiveSpecialOffer) const PositionedDirectional(top: 8, start: 8, child: _OfferBadge()),
                  if (product.isActiveSpecialOffer && product.saleEndsAt != null) PositionedDirectional(bottom: 7, end: 7, child: _OfferCountdown(endsAt: product.saleEndsAt!)),
                  PositionedDirectional(top: 8, end: 8, child: _ProductStockBadge(product: product)),
                ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(product.storeName?.trim().isNotEmpty == true ? product.storeName! : product.categoryName ?? 'منتج متجر', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))),
                  if (product.storeAverageRating != null && product.storeAverageRating! > 0) Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: Text('★ ${product.storeAverageRating!.toStringAsFixed(1)}', style: const TextStyle(fontSize: 10, color: Color(0xFF9A6814), fontWeight: FontWeight.w900))),
                ]),
                const SizedBox(height: 4),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_price(product.effectivePrice, product.currencyCode), style: TextStyle(color: product.isActiveSpecialOffer ? const Color(0xFFD83128) : Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900)),
                      if (product.isActiveSpecialOffer) Text(_price(product.price, product.currencyCode), style: const TextStyle(decoration: TextDecoration.lineThrough, color: Color(0xFF8C7774), fontSize: 11)),
                    ])),
                    IconButton.filledTonal(
                      tooltip: product.fulfillmentMode == 'retail' && product.stockQuantity <= 0 ? 'نفد المخزون' : 'أضف إلى السلة',
                      onPressed: product.fulfillmentMode == 'retail' && product.stockQuantity <= 0 ? null : onAdd,
                      icon: Icon(product.fulfillmentMode == 'retail' && product.stockQuantity <= 0 ? Icons.inventory_2_outlined : Icons.add_shopping_cart_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}


final class _StoreAvatar extends StatelessWidget {
  const _StoreAvatar({required this.store, required this.radius});
  final StoreSummary store; final double radius;
  @override Widget build(BuildContext context) => CircleAvatar(radius: radius, backgroundColor: const Color(0xFFD9F0E8), child: ClipOval(child: SizedBox(width: radius * 2, height: radius * 2, child: store.logoMediaPublicId?.trim().isEmpty != false ? Center(child: Text(_initial(store.name), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900, fontSize: radius * .82))) : CachedMediaImage(mediaPublicId: store.logoMediaPublicId!, fit: BoxFit.cover))));
}

final class _StoreContactActions extends StatelessWidget {
  const _StoreContactActions({this.phone, this.whatsapp}); final String? phone; final String? whatsapp;
  Future<void> _open(BuildContext context, String scheme, String value) async { final uri = Uri.parse('$scheme:$value'); if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح تطبيق الاتصال.'))); }
  @override Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
    if (phone?.trim().isNotEmpty == true) FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2774C7)), onPressed: () => _open(context, 'tel', phone!.replaceAll(RegExp(r'[^0-9+]'), '')), icon: const Icon(Icons.phone_in_talk_rounded), label: const Text('اتصال')),
    if (whatsapp?.trim().isNotEmpty == true) FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25A45A)), onPressed: () => launchUrl(Uri.parse('https://wa.me/${whatsapp!.replaceAll(RegExp(r'[^0-9]'), '')}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.chat_rounded), label: const Text('WhatsApp')),
  ]);
}

final class _StoreHoursCard extends StatelessWidget {
  const _StoreHoursCard({required this.hours, required this.holidays});
  final Map<String, dynamic> hours;
  final List<Map<String, dynamic>> holidays;

  @override
  Widget build(BuildContext context) {
    if (hours.isEmpty && holidays.isEmpty) return const SizedBox.shrink();
    const names = <String, String>{'saturday':'السبت','sunday':'الأحد','monday':'الاثنين','tuesday':'الثلاثاء','wednesday':'الأربعاء','thursday':'الخميس','friday':'الجمعة'};
    final rows = hours.entries.map((entry) {
      final row = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : const <String, dynamic>{};
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(names[entry.key] ?? entry.key),
          Text(row['closed'] == true ? 'عطلة' : '${row['opens_at'] ?? ''} — ${row['closes_at'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
    }).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFFF3E1), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFF5D29B))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.schedule_rounded, color: Color(0xFF9A5B12)), SizedBox(width: 7), Text('الدوام والعطل', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7C4915)))]),
        if (hours.isNotEmpty) ExpansionTile(tilePadding: EdgeInsets.zero, childrenPadding: EdgeInsets.zero, title: const Text('عرض أوقات الدوام'), children: rows),
        if (holidays.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: holidays.take(3).map((item) => Chip(label: Text('${item['label'] ?? 'عطلة'} · ${item['date'] ?? ''}'), visualDensity: VisualDensity.compact, backgroundColor: const Color(0xFFFFE6C3), side: BorderSide.none)).toList()),
      ]),
    );
  }
}

/// Shared, swipeable banner surface for the main store directory and individual stores.
final class StoreBannerStrip extends StatelessWidget {
  const StoreBannerStrip({super.key, required this.banners, required this.title});
  final List<StoreBanner> banners;
  final String title;

  Future<void> _open(BuildContext context, StoreBanner banner) async {
    if (banner.destinationType == 'product' && banner.destinationProductId != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProductDetailsPage(productId: banner.destinationProductId!, title: banner.title ?? 'تفاصيل المنتج')));
    } else if (banner.destinationType == 'store' && banner.destinationStoreId != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoreDetailsPage(storeId: banner.destinationStoreId!, storeName: banner.title ?? 'المتجر')));
    } else if (banner.destinationType == 'external' && banner.externalUrl != null) {
      await launchUrl(Uri.parse(banner.externalUrl!), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 9),
      SizedBox(
        height: 148,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: banners.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final banner = banners[index];
            return SizedBox(
              width: 300,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _open(context, banner),
                  child: Stack(fit: StackFit.expand, children: [
                    CachedMediaImage(mediaPublicId: banner.mediaPublicId, fit: BoxFit.cover),
                    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xB8000000), Color(0x00000000)], begin: AlignmentDirectional.bottomStart, end: AlignmentDirectional.topEnd))),
                    if (banner.title?.isNotEmpty == true) PositionedDirectional(bottom: 12, start: 12, end: 12, child: Text(banner.title!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, shadows: [Shadow(blurRadius: 4, color: Colors.black)]))),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

final class _OfferBadge extends StatelessWidget { const _OfferBadge(); @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:const Color(0xFFD92D26),borderRadius:BorderRadius.circular(8),boxShadow:const [BoxShadow(color:Color(0x88380000),blurRadius:9)]),child:const Text('عرض',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:11))); }
final class _OfferCountdown extends StatefulWidget { const _OfferCountdown({required this.endsAt}); final String endsAt; @override State<_OfferCountdown> createState()=>_OfferCountdownState(); }
final class _OfferCountdownState extends State<_OfferCountdown> { Timer? _timer; Duration _remaining=Duration.zero; @override void initState(){super.initState();_tick();_timer=Timer.periodic(const Duration(seconds:1),(_)=>_tick());} void _tick(){final end=DateTime.tryParse(widget.endsAt)?.toLocal();final next=end==null?Duration.zero:end.difference(DateTime.now());if(mounted)setState(()=>_remaining=next.isNegative?Duration.zero:next);} @override void dispose(){_timer?.cancel();super.dispose();} @override Widget build(BuildContext context){final h=_remaining.inHours;final m=_remaining.inMinutes.remainder(60);final sec=_remaining.inSeconds.remainder(60);return Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:3),decoration:BoxDecoration(color:const Color(0xA9000000),borderRadius:BorderRadius.circular(7)),child:Text(_remaining==Duration.zero?'انتهى العرض':'${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}',style:const TextStyle(color:Colors.white,fontSize:10,fontWeight:FontWeight.w800)));} }

final class _AdminContentDeleteButton extends StatelessWidget {
  const _AdminContentDeleteButton({required this.kind, required this.publicId});
  final String kind;
  final String publicId;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.error,
    ),
    onPressed: () async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('حذف ${kind == 'listing' ? 'الإعلان' : 'المنتج'}؟'),
          content: const Text('سيتم إخفاء المحتوى بشكل آمن من العرض العام.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      );
      if (yes != true || !context.mounted) return;
      try {
        final app = AppScope.of(context);
        if (kind == 'listing') {
          await app.adminDeleteListing(publicId);
        } else {
          await app.adminDeleteProduct(publicId);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حذف المحتوى من العرض.')),
          );
          Navigator.of(context).pop();
        }
      } catch (_) {
        if (context.mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('تعذر حذف المحتوى.')));
      }
    },
    icon: const Icon(Icons.delete_outline_rounded),
    label: Text('حذف ${kind == 'listing' ? 'الإعلان' : 'المنتج'}'),
  );
}

final class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    backgroundColor: const Color(0xFFF1F7F3),
    side: BorderSide.none,
  );
}

final class _StaleBanner extends StatelessWidget {
  const _StaleBanner({this.lastSyncedAt});
  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) {
    final stamp = lastSyncedAt == null
        ? ''
        : ' آخر تحديث محفوظ: ${MaterialLocalizations.of(context).formatShortDate(lastSyncedAt!)}، ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(lastSyncedAt!))}.';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2CC),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'تعذر التحديث، لذلك تظهر آخر بيانات محفوظة على جهازك.$stamp',
            ),
          ),
        ],
      ),
    );
  }
}

final class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: _EmptyDetail(
        icon: Icons.cloud_off_outlined,
        title: 'تعذر تحميل التفاصيل',
        body: 'تحقق من اتصالك بالإنترنت ثم حاول مرة أخرى.',
        action: FilledButton(
          onPressed: onRetry,
          child: const Text('إعادة المحاولة'),
        ),
      ),
    ),
  );
}

final class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 11),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 15), action!],
        ],
      ),
    ),
  );
}

String _initial(String value) =>
    value.trim().isEmpty ? 'ت' : value.trim().substring(0, 1);

String _price(num? amount, String currency) =>
    amount == null ? 'تواصل للسعر' : '${amount.toStringAsFixed(2)} $currency';
