import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../domain/catalog_models.dart';
import 'catalog_detail_pages.dart';

/// Web-equivalent product discovery rows, kept independent from store loading.
final class FeaturedProductsPanel extends StatelessWidget {
  const FeaturedProductsPanel({super.key, required this.kind, required this.title, required this.emptyText});
  final String kind; final String title; final String emptyText;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<StoreProduct>>(
    future: AppScope.of(context).loadFeaturedProducts(kind),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
      final products = snapshot.data ?? const <StoreProduct>[];
      if (products.isEmpty) return Padding(padding: const EdgeInsets.only(top: 12), child: Text(emptyText));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 9),
        SizedBox(height: 190, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: products.length, separatorBuilder: (_, _) => const SizedBox(width: 10), itemBuilder: (context, i) { final product = products[i]; return SizedBox(width: 160, child: Card(clipBehavior: Clip.antiAlias, child: InkWell(onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProductDetailsPage(productId: product.publicId, title: product.name))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: SizedBox(width: double.infinity, child: product.mediaPublicId == null ? const ColoredBox(color: Color(0xFFE7ECE8), child: Icon(Icons.inventory_2_outlined)) : CachedMediaImage(mediaPublicId: product.mediaPublicId!, fit: BoxFit.cover))),
          Padding(padding: const EdgeInsets.fromLTRB(10, 7, 10, 1), child: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
          Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 8), child: Text('${product.effectivePrice} ${product.currencyCode}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900))),
        ])))); }),),
      ]);
    },
  );
}
