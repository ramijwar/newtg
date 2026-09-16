import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/network/api_exception.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_models.dart';
import 'catalog_detail_pages.dart';
import 'marketplace_listing_editor_page.dart';

/// A responsive marketplace discovery surface: live search, compact filters,
/// animated results and explicit empty/error states all use the existing API.
final class MarketplaceBrowsePage extends StatefulWidget {
  const MarketplaceBrowsePage({super.key});

  @override
  State<MarketplaceBrowsePage> createState() => _MarketplaceBrowsePageState();
}

final class _MarketplaceBrowsePageState extends State<MarketplaceBrowsePage> {
  final _search = TextEditingController();
  Future<CatalogPage<MarketplaceListing>>? _listings;
  Future<List<Map<String, dynamic>>>? _categories;
  Timer? _searchDebounce;
  String _categoryId = '';
  String _city = '';
  String _sort = 'newest';
  int _page = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _categories ??= AppScope.of(context).loadMarketplaceCategories();
    _listings ??= _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters => _search.text.trim().isNotEmpty || _categoryId.isNotEmpty || _city.isNotEmpty || _sort != 'newest';
  int get _filterCount => [_categoryId, _city].where((value) => value.isNotEmpty).length;

  Future<CatalogPage<MarketplaceListing>> _load() => AppScope.of(context).browseMarketplacePage(
        search: _search.text.trim(),
        city: _city,
        categoryId: _categoryId,
        sort: _sort,
        page: _page,
      );

  void _apply({bool resetPage = true}) => setState(() {
        if (resetPage) _page = 1;
        _listings = _load();
      });

  void _scheduleSearch(String _) {
    // Rebuild immediately so the clear affordance reacts while results debounce.
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 360), _apply);
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    setState(() {
      _search.clear();
      _categoryId = '';
      _city = '';
      _sort = 'newest';
      _page = 1;
      _listings = _load();
    });
  }

  Future<void> _openFilters() async {
    List<Map<String, dynamic>> categories = const [];
    try {
      categories = await (_categories ?? AppScope.of(context).loadMarketplaceCategories());
    } catch (_) {
      // A search can still run even if categories fail to load.
    }
    if (!mounted) return;
    final values = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MarketplaceFilterSheet(
        categories: categories,
        categoryId: _categoryId,
        city: _city,
        sort: _sort,
      ),
    );
    if (values == null || !mounted) return;
    setState(() {
      _categoryId = values['category_id'] ?? '';
      _city = values['city'] ?? '';
      _sort = values['sort'] ?? 'newest';
      _page = 1;
      _listings = _load();
    });
  }

  Future<void> _createListing() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const MarketplaceListingEditorPage()),
    );
    if (changed == true && mounted) _apply(resetPage: false);
  }

  String _sortLabel() => switch (_sort) {
        'views' => 'الأكثر زيارة',
        'price_low' => 'الأقل سعراً',
        'price_high' => 'الأعلى سعراً',
        _ => 'الأحدث',
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('الحراج'),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: IconButton.filledTonal(
                tooltip: 'إضافة إعلان',
                onPressed: _createListing,
                icon: const Icon(Icons.add_rounded),
              ),
            ),
          ],
        ),
        body: FutureBuilder<CatalogPage<MarketplaceListing>>(
          future: _listings,
          builder: (context, snapshot) {
            final result = snapshot.data;
            return RefreshIndicator(
              onRefresh: () async => _apply(resetPage: false),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(child: _MarketplaceHero(onCreate: _createListing)),
                  SliverToBoxAdapter(child: _searchAndControls()),
                  if (snapshot.connectionState != ConnectionState.done)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 28),
                      sliver: _MarketplaceLoadingGrid(),
                    )
                  else if (snapshot.hasError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _MarketplaceStatePanel(
                        icon: Icons.cloud_off_rounded,
                        title: 'تعذر تحديث الحراج',
                        body: snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تحقق من اتصالك ثم أعد المحاولة.',
                        actionLabel: 'إعادة المحاولة',
                        onAction: _apply,
                      ),
                    )
                  else if (result == null || result.items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _MarketplaceStatePanel(
                        icon: _hasActiveFilters ? Icons.search_off_rounded : Icons.storefront_outlined,
                        title: _hasActiveFilters ? 'لا توجد نتائج مطابقة' : 'لا توجد إعلانات منشورة بعد',
                        body: _hasActiveFilters ? 'جرّب تعديل البحث أو المدينة أو الفلاتر لتوسيع النتائج.' : 'ستظهر هنا الإعلانات النشطة فور نشرها واعتمادها.',
                        actionLabel: _hasActiveFilters ? 'مسح البحث والفلاتر' : 'نشر أول إعلان',
                        onAction: _hasActiveFilters ? _clearFilters : _createListing,
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(child: _resultHeader(result)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      sliver: SliverGrid.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisExtent: 322,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: result.items.length,
                        itemBuilder: (context, index) => _RevealListingCard(
                          key: ValueKey(result.items[index].publicId),
                          listing: result.items[index],
                          index: index,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _BrowsePager(
                        page: result.page,
                        totalPages: result.totalPages,
                        total: result.total,
                        onPage: (page) {
                          if (page < 1) return;
                          setState(() { _page = page; _listings = _load(); });
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );

  Widget _searchAndControls() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Column(children: [
          TextField(
            controller: _search,
            maxLength: 100,
            textInputAction: TextInputAction.search,
            onChanged: _scheduleSearch,
            onSubmitted: (_) { _searchDebounce?.cancel(); _apply(); },
            decoration: InputDecoration(
              counterText: '',
              hintText: 'ابحث عن سيارة، خدمة، أثاث…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty ? null : IconButton(
                tooltip: 'مسح البحث',
                onPressed: () { _search.clear(); _apply(); },
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _CategoryStrip(
              categories: _categories,
              selectedId: _categoryId,
              onSelected: (id) { _categoryId = id; _apply(); },
            )),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: _filterCount > 0,
              label: Text('$_filterCount'),
              child: IconButton.filledTonal(
                tooltip: 'الفلاتر والترتيب',
                onPressed: _openFilters,
                icon: const Icon(Icons.tune_rounded),
              ),
            ),
          ]),
          if (_city.isNotEmpty || _sort != 'newest')
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(spacing: 7, runSpacing: 7, children: [
                  if (_city.isNotEmpty) _ActiveFilterChip(icon: Icons.location_on_outlined, label: _city, onDeleted: () { _city = ''; _apply(); }),
                  if (_sort != 'newest') _ActiveFilterChip(icon: Icons.sort_rounded, label: _sortLabel(), onDeleted: () { _sort = 'newest'; _apply(); }),
                ]),
              ),
            ),
        ]),
      );

  Widget _resultHeader(CatalogPage<MarketplaceListing> result) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_sort == 'newest' ? 'إعلانات جديدة لك' : _sortLabel(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(_hasActiveFilters ? 'نتائج حسب اختيارك' : 'تصفح أحدث ما نُشر في الحراج', style: Theme.of(context).textTheme.bodySmall),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Text('${result.total} إعلان', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ]),
      );
}

final class _MarketplaceHero extends StatelessWidget {
  const _MarketplaceHero({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(colors: [Color(0xFF0E6250), Color(0xFF1C8A70), Color(0xFF55B68E)], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
          boxShadow: const [BoxShadow(color: Color(0x33125F4F), blurRadius: 22, offset: Offset(0, 10))],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('الحراج المحلي', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text('اكتشف شيئًا مميزًا بالقرب منك', style: TextStyle(color: Colors.white, fontSize: 22, height: 1.2, fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            const Text('إعلانات حديثة، تواصل مباشر، وتجربة شراء أبسط.', style: TextStyle(color: Colors.white70, height: 1.4)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0E6250), minimumSize: const Size(0, 42)),
              onPressed: onCreate,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('أضف إعلانك'),
            ),
          ])),
          const SizedBox(width: 12),
          const Icon(Icons.auto_awesome_rounded, color: Color(0xCCFFFFFF), size: 58),
        ]),
      );
}

final class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.categories, required this.selectedId, required this.onSelected});
  final Future<List<Map<String, dynamic>>>? categories;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 39,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: categories,
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <Map<String, dynamic>>[];
            return ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _chip(context, '', 'الكل'),
                ...rows.take(12).map((row) => _chip(context, row['public_id'] as String? ?? '', row['name'] as String? ?? 'قسم')),
              ],
            );
          },
        ),
      );

  Widget _chip(BuildContext context, String id, String label) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 7),
        child: ChoiceChip(
          label: Text(label),
          selected: selectedId == id,
          onSelected: (_) => onSelected(id),
          visualDensity: VisualDensity.compact,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      );
}

final class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.icon, required this.label, required this.onDeleted});
  final IconData icon;
  final String label;
  final VoidCallback onDeleted;
  @override
  Widget build(BuildContext context) => InputChip(
    avatar: Icon(icon, size: 16),
    label: Text(label),
    onDeleted: onDeleted,
    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
  );
}

final class _MarketplaceFilterSheet extends StatefulWidget {
  const _MarketplaceFilterSheet({required this.categories, required this.categoryId, required this.city, required this.sort});
  final List<Map<String, dynamic>> categories;
  final String categoryId;
  final String city;
  final String sort;
  @override State<_MarketplaceFilterSheet> createState() => _MarketplaceFilterSheetState();
}

final class _MarketplaceFilterSheetState extends State<_MarketplaceFilterSheet> {
  late final TextEditingController _city;
  late String _categoryId;
  late String _sort;
  @override void initState() { super.initState(); _city = TextEditingController(text: widget.city); _categoryId = widget.categoryId; _sort = widget.sort; }
  @override void dispose() { _city.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + 22),
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('فلترة الحراج', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height:5),
            Text('خصص ما يظهر لك ثم طبّق الفلاتر فورًا.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height:18),
            TextField(controller:_city, maxLength:120, decoration:const InputDecoration(counterText:'', labelText:'المدينة', prefixIcon:Icon(Icons.location_on_outlined))),
            const SizedBox(height:16),
            const Text('القسم', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height:8),
            Wrap(spacing:8, runSpacing:8, children:[
              ChoiceChip(label:const Text('كل الأقسام'), selected:_categoryId.isEmpty, onSelected:(_)=>setState(()=>_categoryId='')),
              ...widget.categories.map((row){final id=row['public_id'] as String? ?? ''; return ChoiceChip(label:Text(row['name'] as String? ?? 'قسم'),selected:_categoryId==id,onSelected:(_)=>setState(()=>_categoryId=id));}),
            ]),
            const SizedBox(height:18),
            const Text('الترتيب', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height:8),
            Wrap(spacing:8, runSpacing:8, children:[
              _sortChip('newest','الأحدث'), _sortChip('views','الأكثر زيارة'), _sortChip('price_low','السعر الأقل'), _sortChip('price_high','السعر الأعلى'),
            ]),
            const SizedBox(height:24),
            Row(children:[
              TextButton(onPressed:()=>setState((){_city.clear();_categoryId='';_sort='newest';}),child:const Text('مسح الكل')),
              const Spacer(),
              FilledButton.icon(onPressed:()=>Navigator.of(context).pop({'category_id':_categoryId,'city':_city.text.trim(),'sort':_sort}),icon:const Icon(Icons.check_rounded),label:const Text('تطبيق الفلاتر')),
            ]),
          ])),
        ),
      );
  Widget _sortChip(String value,String label)=>ChoiceChip(label:Text(label),selected:_sort==value,onSelected:(_)=>setState(()=>_sort=value));
}

final class _MarketplaceLoadingGrid extends StatelessWidget {
  const _MarketplaceLoadingGrid();
  @override
  Widget build(BuildContext context) => SliverGrid(
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:260,mainAxisExtent:322,crossAxisSpacing:12,mainAxisSpacing:12),
    delegate: SliverChildBuilderDelegate((context,index)=>_MarketplaceSkeleton(delay:index*80),childCount:8),
  );
}

final class _MarketplaceSkeleton extends StatelessWidget {
  const _MarketplaceSkeleton({required this.delay});
  final int delay;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin:.35,end:.85), duration: Duration(milliseconds:850+delay), curve:Curves.easeInOut, builder:(_,opacity,__)=>Card(child:Opacity(opacity:opacity,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(flex:6,child:Container(decoration:BoxDecoration(color:const Color(0xFFE5ECE7),borderRadius:BorderRadius.circular(16)))),const SizedBox(height:12),Container(width:80,height:10,color:const Color(0xFFE5ECE7)),const SizedBox(height:8),Container(width:double.infinity,height:13,color:const Color(0xFFE5ECE7)),const SizedBox(height:8),Container(width:120,height:10,color:const Color(0xFFE5ECE7))])))),
  );
}

final class _MarketplaceStatePanel extends StatelessWidget {
  const _MarketplaceStatePanel({required this.icon,required this.title,required this.body,required this.actionLabel,required this.onAction});
  final IconData icon; final String title; final String body; final String actionLabel; final VoidCallback onAction;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.fromLTRB(28,30,28,50),child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:390),child:Card(child:Padding(padding:const EdgeInsets.all(25),child:Column(mainAxisSize:MainAxisSize.min,children:[Container(width:68,height:68,decoration:BoxDecoration(color:Theme.of(context).colorScheme.primaryContainer,borderRadius:BorderRadius.circular(24)),child:Icon(icon,size:34,color:Theme.of(context).colorScheme.primary)),const SizedBox(height:17),Text(title,textAlign:TextAlign.center,style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),const SizedBox(height:8),Text(body,textAlign:TextAlign.center,style:TextStyle(color:Theme.of(context).colorScheme.onSurfaceVariant,height:1.55)),const SizedBox(height:20),FilledButton.icon(onPressed:onAction,icon:const Icon(Icons.refresh_rounded),label:Text(actionLabel))]))))));
}

final class _BrowsePager extends StatelessWidget {
  const _BrowsePager({required this.page,required this.totalPages,required this.total,required this.onPage});
  final int page; final int totalPages; final int total; final ValueChanged<int> onPage;
  @override Widget build(BuildContext context){if(totalPages<=1)return const SizedBox(height:18);return SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,4,16,18),child:Row(children:[OutlinedButton.icon(onPressed:page<=1?null:()=>onPage(page-1),icon:const Icon(Icons.chevron_right_rounded),label:const Text('السابق')),Expanded(child:Text('صفحة $page من $totalPages',textAlign:TextAlign.center,style:Theme.of(context).textTheme.bodySmall)),OutlinedButton.icon(onPressed:page>=totalPages?null:()=>onPage(page+1),icon:const Icon(Icons.chevron_left_rounded),label:const Text('التالي'))])));}
}

final class _RevealListingCard extends StatefulWidget {
  const _RevealListingCard({super.key,required this.listing,required this.index});
  final MarketplaceListing listing; final int index;
  @override State<_RevealListingCard> createState()=>_RevealListingCardState();
}

final class _RevealListingCardState extends State<_RevealListingCard> {
  @override Widget build(BuildContext context)=>TweenAnimationBuilder<double>(
    tween:Tween(begin:0,end:1),duration:Duration(milliseconds:280+(widget.index.clamp(0,8).toInt()*55)),curve:Curves.easeOutCubic,
    builder:(_,value,child)=>Transform.translate(offset:Offset(0,18*(1-value)),child:Opacity(opacity:value,child:child)),child:_ListingCard(listing:widget.listing),
  );
}

final class _ListingCard extends StatefulWidget {
  const _ListingCard({required this.listing});
  final MarketplaceListing listing;
  @override State<_ListingCard> createState()=>_ListingCardState();
}

final class _ListingCardState extends State<_ListingCard> {
  late bool _favorite;
  bool _favoriteBusy=false;
  @override void initState(){super.initState();_favorite=widget.listing.isFavorite;}
  @override void didUpdateWidget(covariant _ListingCard old){super.didUpdateWidget(old);if(old.listing.publicId!=widget.listing.publicId)_favorite=widget.listing.isFavorite;}
  Future<void> _toggleFavorite() async {if(_favoriteBusy)return;setState(()=>_favoriteBusy=true);try{final next=await AppScope.of(context).setMarketplaceFavorite(listingId:widget.listing.publicId,enabled:!_favorite);if(mounted)setState(()=>_favorite=next);}on ApiException catch(error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error.message)));}finally{if(mounted)setState(()=>_favoriteBusy=false);}}
  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final location = [listing.district, listing.city]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .join('، ');

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ListingDetailsPage(
              listingId: listing.publicId,
              title: listing.title,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 156,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  listing.mediaPublicId == null
                      ? Container(
                          color: const Color(0xFFE1ECE5),
                          child: const Icon(
                            Icons.image_outlined,
                            size: 42,
                            color: Color(0xFF578B72),
                          ),
                        )
                      : CachedMediaImage(
                          mediaPublicId: listing.mediaPublicId!,
                          fit: BoxFit.cover,
                        ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Color(0x990B3328)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: 10,
                    start: 10,
                    child: _ImagePill(
                      icon: Icons.category_outlined,
                      text: listing.categoryName ?? 'الحراج',
                    ),
                  ),
                  if (listing.isNegotiable)
                    const PositionedDirectional(
                      bottom: 9,
                      start: 9,
                      child: _ImagePill(
                        icon: Icons.handshake_outlined,
                        text: 'قابل للتفاوض',
                      ),
                    ),
                  PositionedDirectional(
                    top: 5,
                    end: 5,
                    child: Material(
                      color: Colors.white.withOpacity(.94),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: _favorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                        onPressed: _favoriteBusy ? null : _toggleFavorite,
                        icon: _favoriteBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                _favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                color: _favorite ? Theme.of(context).colorScheme.error : null,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, height: 1.25),
                    ),
                    const Spacer(),
                    Text(
                      listing.priceAmount == null
                          ? 'السعر عند التواصل'
                          : '${listing.priceAmount} ${listing.currencyCode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(children: [
                      Icon(Icons.location_on_outlined, size: 15, color: muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          location.isEmpty ? 'الموقع غير محدد' : location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Icon(Icons.visibility_outlined, size: 15, color: muted),
                      const SizedBox(width: 3),
                      Text('${listing.viewCount}', style: TextStyle(color: muted, fontSize: 11)),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

final class _ImagePill extends StatelessWidget {
  const _ImagePill({required this.icon,required this.text}); final IconData icon; final String text;
  @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),decoration:BoxDecoration(color:const Color(0xCCFFFFFF),borderRadius:BorderRadius.circular(11)),child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:13,color:const Color(0xFF164D3D)),const SizedBox(width:4),ConstrainedBox(constraints:const BoxConstraints(maxWidth:100),child:Text(text,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Color(0xFF164D3D),fontSize:10,fontWeight:FontWeight.w900)))]));
}
