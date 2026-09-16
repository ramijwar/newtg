import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/local_database.dart';
import '../domain/catalog_models.dart';

/// The common API pagination envelope retained by browse screens instead of
/// silently discarding results after a fixed first-page limit.
final class CatalogPage<T> {
  const CatalogPage({required this.items, required this.page, required this.perPage, required this.total, required this.totalPages, this.banners = const []});
  final List<T> items;
  final List<StoreBanner> banners;
  final int page;
  final int perPage;
  final int total;
  final int totalPages;
}

int _pageNumber(Object? value, [int fallback = 1]) => (value as num?)?.toInt() ?? int.tryParse('$value') ?? fallback;

/// Public catalogue data is cached locally for read-only offline browsing.
/// Server state remains authoritative whenever a connection is available.
final class CatalogRepository {
  CatalogRepository(this._api, this._database);

  final ApiClient _api;
  final LocalDatabase _database;

  Future<HomeFeed> loadHome() async {
    try {
      final results = await Future.wait([
        _api.get('/stores', query: const {'per_page': 8}),
        _api.get('/marketplace/listings', query: const {'per_page': 8}),
      ]);
      final stores = _stores(results[0]);
      final listings = _listings(results[1]);
      await Future.wait([
        _database.putCache('home_stores', results[0]),
        _database.putCache('home_listings', results[1]),
      ]);
      final entries = await Future.wait([
        _database.readCacheEntry('home_stores'),
        _database.readCacheEntry('home_listings'),
      ]);
      return HomeFeed(
        stores: stores,
        listings: listings,
        lastSyncedAt: _latestAt(entries),
      );
    } catch (_) {
      final entries = await Future.wait([
        _database.readCacheEntry('home_stores'),
        _database.readCacheEntry('home_listings'),
      ]);
      final cachedStores = entries[0];
      final cachedListings = entries[1];
      if (cachedStores == null && cachedListings == null) rethrow;
      return HomeFeed(
        stores: cachedStores == null ? const [] : _stores(cachedStores.payload),
        listings: cachedListings == null
            ? const []
            : _listings(cachedListings.payload),
        isStale: true,
        lastSyncedAt: _latestAt(entries),
      );
    }
  }

  /// Loads every active store using the API pagination contract. The shared
  /// directory and the stores tab use this rather than the short home preview.
  Future<List<StoreSummary>> loadStoreDirectory({String mode = ''}) async {
    final normalizedMode = mode == 'retail' || mode == 'preorder' ? mode : '';
    final first = await _api.get('/stores', query: {
      'page': 1,
      'per_page': 50,
      'sort': 'popular',
      if (normalizedMode.isNotEmpty) 'mode': normalizedMode,
    });
    final pagination = first['pagination'] is Map
        ? Map<String, dynamic>.from(first['pagination'] as Map)
        : const <String, dynamic>{};
    final totalPages = (pagination['total_pages'] as num?)?.toInt() ??
        int.tryParse('${pagination['total_pages'] ?? ''}') ??
        1;
    final pages = await Future.wait([
      for (var page = 2; page <= totalPages; page++)
        _api.get('/stores', query: {
          'page': page,
          'per_page': 50,
          'sort': 'popular',
          if (normalizedMode.isNotEmpty) 'mode': normalizedMode,
        }),
    ]);
    final raw = <dynamic>[
      ...(first['items'] as List? ?? const []),
      for (final page in pages) ...(page['items'] as List? ?? const []),
    ];
    return raw
        .whereType<Map>()
        .map((item) => StoreSummary.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<CatalogPage<StoreSummary>> browseStoresPage({
    String search = '', String categoryId = '', String mode = '', String sort = 'popular', int page = 1,
  }) async {
    final data = await _api.get('/stores', query: {
      'page': page < 1 ? 1 : page, 'per_page': 24,
      if (search.trim().isNotEmpty) 'search': search.trim(), if (categoryId.isNotEmpty) 'category_id': categoryId,
      if (mode.isNotEmpty) 'mode': mode, if (sort != 'popular') 'sort': sort,
    });
    final pagination = data['pagination'] is Map ? Map<String, dynamic>.from(data['pagination'] as Map) : const <String, dynamic>{};
    return CatalogPage(items: _stores(data), banners: _storeBanners(data['banners']), page: _pageNumber(pagination['page'], page), perPage: _pageNumber(pagination['per_page'], 24), total: _pageNumber(pagination['total'], 0), totalPages: _pageNumber(pagination['total_pages'], 1));
  }

  Future<List<StoreSummary>> browseStores({String search = '', String categoryId = '', String mode = '', String sort = 'popular'}) async =>
      (await browseStoresPage(search: search, categoryId: categoryId, mode: mode, sort: sort)).items;

  Future<List<Map<String, dynamic>>> loadPublicStoreCategories() async =>
      _mapItems(await _api.get('/store-categories', query: const {'type': 'store'}));

  Future<List<StoreProduct>> loadFeaturedProducts(String kind) async {
    final data = await _api.get('/products/featured', query: {'kind': kind});
    return ((data['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => StoreProduct.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> loadStoreReviews(String storeId) async =>
      _mapItems(
        await _api.get(
          '/stores/${Uri.encodeComponent(storeId)}/reviews',
          query: const {'per_page': 8},
        ),
      );

  Future<List<Map<String, dynamic>>> loadStoreReviewEligibility(String storeId) async =>
      _mapItems(
        await _api.get('/stores/${Uri.encodeComponent(storeId)}/review-eligibility'),
      );

  Future<void> setStoreFollowing({
    required String storeId,
    required bool following,
  }) async {
    await _api.patch(
      '/stores/${Uri.encodeComponent(storeId)}/follow',
      body: {'following': following},
    );
  }

  Future<void> createStoreReview({
    required String storeId,
    required String orderId,
    required int rating,
    String comment = '',
  }) async {
    await _api.post(
      '/stores/${Uri.encodeComponent(storeId)}/reviews',
      body: {'order_id': orderId, 'rating': rating, 'comment': comment.trim()},
    );
  }

  Future<CatalogPage<MarketplaceListing>> browseMarketplacePage({
    String search = '', String city = '', String categoryId = '', String sort = 'newest', int page = 1,
  }) async {
    final data = await _api.get('/marketplace/listings', query: {
      'page': page < 1 ? 1 : page, 'per_page': 24,
      if (search.trim().isNotEmpty) 'search': search.trim(), if (city.trim().isNotEmpty) 'city': city.trim(), if (categoryId.isNotEmpty) 'category_id': categoryId, if (sort != 'newest') 'sort': sort,
    });
    final pagination = data['pagination'] is Map ? Map<String, dynamic>.from(data['pagination'] as Map) : const <String, dynamic>{};
    return CatalogPage(items: _listings(data), page: _pageNumber(pagination['page'], page), perPage: _pageNumber(pagination['per_page'], 24), total: _pageNumber(pagination['total'], 0), totalPages: _pageNumber(pagination['total_pages'], 1));
  }

  Future<List<MarketplaceListing>> browseMarketplace({String search = '', String city = '', String categoryId = '', String sort = 'newest'}) async =>
      (await browseMarketplacePage(search: search, city: city, categoryId: categoryId, sort: sort)).items;

  Future<List<Map<String, dynamic>>> loadMyMarketplaceListings() async =>
      _mapItems(await _api.get('/marketplace/my-listings'));

  Future<List<Map<String, dynamic>>> loadMarketplaceFavorites() async =>
      _mapItems(await _api.get('/marketplace/favorites'));

  Future<bool> setMarketplaceFavorite({
    required String listingId,
    required bool enabled,
  }) async {
    final data = await _api.patch(
      '/marketplace/listings/${Uri.encodeComponent(listingId)}/favorite',
      body: {'enabled': enabled},
    );
    return data['is_favorite'] == true || data['is_favorite'] == 1 || data['is_favorite'] == '1';
  }

  Future<List<Map<String, dynamic>>> loadMarketplaceConversations() async =>
      _mapItems(await _api.get('/marketplace/conversations'));

  Future<Map<String, dynamic>> startMarketplaceConversation(String listingId) async {
    final data = await _api.post(
      '/marketplace/listings/${Uri.encodeComponent(listingId)}/conversation',
    );
    return Map<String, dynamic>.from(data['conversation'] as Map? ?? const {});
  }

  Future<List<Map<String, dynamic>>> loadConversationMessages(
    String conversationId,
  ) async => _mapItems(
    await _api.get(
      '/marketplace/conversations/${Uri.encodeComponent(conversationId)}/messages',
    ),
  );

  Future<void> sendConversationMessage({
    required String conversationId,
    required String body,
  }) async {
    await _api.post(
      '/marketplace/conversations/${Uri.encodeComponent(conversationId)}/messages',
      body: {'body': body.trim()},
    );
  }

  Future<void> sendMarketplaceOffer({
    required String conversationId,
    required String amount,
  }) async {
    await _api.post(
      '/marketplace/conversations/${Uri.encodeComponent(conversationId)}/offers',
      body: {'amount': amount},
    );
  }

  Future<void> decideMarketplaceOffer({
    required String offerId,
    required String decision,
  }) async {
    await _api.post(
      '/marketplace/offers/${Uri.encodeComponent(offerId)}/decision',
      body: {'decision': decision},
    );
  }

  Future<List<Map<String, dynamic>>> loadMarketplaceTransactions() async =>
      _mapItems(await _api.get('/marketplace/transactions'));

  Future<void> updateMarketplaceTransaction({
    required String transactionId,
    required String action,
  }) async {
    await _api.post(
      '/marketplace/transactions/${Uri.encodeComponent(transactionId)}/action',
      body: {'action': action},
    );
  }

  Future<List<Map<String, dynamic>>> loadMarketplacePromotionPlans() async =>
      _mapItems(await _api.get('/marketplace/promotion-plans'));

  Future<Map<String, dynamic>> requestMarketplacePromotion({
    required String listingId,
    required String planCode,
  }) async {
    final data = await _api.post(
      '/marketplace/listings/${Uri.encodeComponent(listingId)}/promotions',
      body: {'plan_code': planCode},
    );
    return Map<String, dynamic>.from(data['promotion'] as Map? ?? const {});
  }

  Future<void> submitMarketplacePromotionPayment({
    required String promotionId,
    required String transferReference,
    required XFile receipt,
  }) async {
    final upload = await _api.postForm(
      '/media',
      body: FormData.fromMap({
        'visibility': 'private',
        'file': await MultipartFile.fromFile(receipt.path, filename: receipt.name),
      }),
    );
    final media = Map<String, dynamic>.from(upload['media'] as Map? ?? const {});
    final mediaId = media['public_id'] as String?;
    if (mediaId == null || mediaId.isEmpty) {
      throw const FormatException('لم يعد الخادم معرفاً صالحاً لسند التحويل.');
    }
    await _api.post(
      '/marketplace/promotions/${Uri.encodeComponent(promotionId)}/payment',
      body: {'transfer_reference': transferReference.trim(), 'receipt_media_id': mediaId},
    );
  }

  Future<void> setMarketplaceUserBlock({
    required String userId,
    required bool blocked,
  }) async {
    await _api.patch(
      '/marketplace/users/${Uri.encodeComponent(userId)}/block',
      body: {'blocked': blocked},
    );
  }

  Future<void> reportMarketplaceListing({
    required String listingId,
    required String reasonCode,
    String details = '',
  }) async {
    await _api.post(
      '/marketplace/listings/${Uri.encodeComponent(listingId)}/reports',
      body: {'reason_code': reasonCode.trim(), 'details': details.trim()},
    );
  }

  Future<void> confirmMarketplaceDelivery(String taskId) async {
    await _api.post(
      '/marketplace-tasks/${Uri.encodeComponent(taskId)}/confirm-delivery',
    );
  }

  Future<void> requestMarketplaceDelivery({
    required String transactionId,
    required Map<String, dynamic> pickupAddress,
    required Map<String, dynamic> deliveryAddress,
  }) async {
    await _api.post(
      '/marketplace/transactions/${Uri.encodeComponent(transactionId)}/delivery-request',
      body: {'pickup_address': pickupAddress, 'delivery_address': deliveryAddress},
    );
  }

  Future<void> openMarketplaceDispute({
    required String transactionId,
    required String reasonCode,
    required String details,
  }) async {
    await _api.post(
      '/marketplace/transactions/${Uri.encodeComponent(transactionId)}/disputes',
      body: {'reason_code': reasonCode.trim(), 'details': details.trim()},
    );
  }

  Future<List<Map<String, dynamic>>> loadMySupportTickets() async =>
      _mapItems(await _api.get('/support/tickets'));

  Future<void> createSupportTicket({
    required String subject,
    required String body,
  }) async {
    await _api.post('/support/tickets', body: {'subject': subject.trim(), 'body': body.trim()});
  }

  Future<Map<String, dynamic>> loadSupportTicket(String ticketId) async {
    final data = await _api.get('/support/tickets/${Uri.encodeComponent(ticketId)}');
    final ticket = data['ticket'];
    return ticket is Map ? Map<String, dynamic>.from(ticket) : const <String, dynamic>{};
  }

  Future<void> replySupportTicket({
    required String ticketId,
    required String body,
  }) async {
    await _api.post(
      '/support/tickets/${Uri.encodeComponent(ticketId)}/messages',
      body: {'body': body.trim()},
    );
  }

  Future<List<Map<String, dynamic>>> loadMarketplaceCategories() async =>
      _mapItems(await _api.get('/marketplace/categories'));

  Future<List<Map<String, dynamic>>> loadMarketplaceCountries() async =>
      _mapItems(await _api.get('/marketplace/locations/countries'));

  Future<List<Map<String, dynamic>>> loadMarketplaceLocationOptions() async =>
      _mapItems(await _api.get('/marketplace/locations/options'));

  Future<List<Map<String, dynamic>>> loadMarketplaceCities(String countryId) async =>
      _mapItems(
        await _api.get(
          '/marketplace/locations/cities',
          query: {'country_id': countryId},
        ),
      );

  Future<List<Map<String, dynamic>>> loadMarketplaceAttributes(String categoryId) async =>
      _mapItems(
        await _api.get(
          '/marketplace/categories/${Uri.encodeComponent(categoryId)}/attributes'),
      );

  Future<void> updateMarketplaceListing({
    required String listingId,
    required String title,
    required String description,
    String? priceAmount,
    bool submitForReview = false,
  }) async {
    await _api.patch(
      '/marketplace/listings/${Uri.encodeComponent(listingId)}',
      body: {
        'title': title.trim(),
        'description': description.trim(),
        'price_amount': (priceAmount == null || priceAmount.trim().isEmpty) ? null : priceAmount.trim(),
        if (submitForReview) 'submit_for_review': true,
      },
    );
  }

  Future<void> replaceMarketplaceListingImage({
    required String listingId,
    required XFile image,
  }) async {
    final mediaId = await _uploadMarketplaceImage(image);
    await _api.post(
      '/marketplace/listings/${Uri.encodeComponent(listingId)}/media',
      body: {'media_public_id': mediaId, 'is_primary': true},
    );
  }

  Future<void> createMarketplaceListing({
    required String title,
    required String description,
    required String categoryId,
    required String listingType,
    required String currencyCode,
    required String countryId,
    required String cityId,
    String? districtId,
    String? priceAmount,
    Map<String, dynamic> attributes = const {},
    XFile? image,
  }) async {
    String? mediaId;
    if (image != null) mediaId = await _uploadMarketplaceImage(image);
    await _api.post(
      '/marketplace/listings',
      body: {
        'title': title.trim(),
        'description': description.trim(),
        'category_id': categoryId,
        'listing_type': listingType,
        'currency_code': currencyCode,
        'country_id': countryId,
        'city_id': cityId,
        if (districtId != null && districtId.isNotEmpty) 'district_id': districtId,
        'price_amount': (priceAmount == null || priceAmount.trim().isEmpty)
            ? null
            : priceAmount.trim(),
        'attributes': attributes.entries
            .where((entry) => entry.value is bool || entry.value?.toString().trim().isNotEmpty == true)
            .map((entry) => {'attribute_id': entry.key, 'value': entry.value})
            .toList(growable: false),
        if (mediaId != null) 'primary_media_id': mediaId,
      },
    );
  }

  Future<String> _uploadMarketplaceImage(XFile image) async {
    final response = await _api.postForm(
      '/media',
      body: FormData.fromMap({
        'visibility': 'public',
        'file': await MultipartFile.fromFile(image.path, filename: image.name),
      }),
    );
    final media = Map<String, dynamic>.from(response['media'] as Map? ?? const {});
    final id = media['public_id'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('لم يعد الخادم معرفاً صالحاً للصورة المختارة.');
    }
    return id;
  }

  List<StoreBanner> _storeBanners(Object? raw) => (raw is List ? raw : const [])
      .whereType<Map>()
      .map((item) => StoreBanner.fromJson(Map<String, dynamic>.from(item)))
      .where((item) => item.publicId.isNotEmpty && item.mediaPublicId.isNotEmpty)
      .toList(growable: false);

  List<Map<String, dynamic>> _mapItems(Map<String, dynamic> data) =>
      ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);

  Future<StoreDetails> loadStore(String publicId) async {
    final cacheKey = 'store_$publicId';
    try {
      final results = await Future.wait([
        _api.get('/stores/${Uri.encodeComponent(publicId)}'),
        _api.get(
          '/stores/${Uri.encodeComponent(publicId)}/products',
          query: const {'per_page': 30},
        ),
      ]);
      final payload = <String, dynamic>{
        'store': results[0]['store'] ?? results[0],
        'products': results[1]['items'] ?? const [],
        'banners': (results[0]['store'] is Map ? (results[0]['store'] as Map)['banners'] : const []) ?? const [],
      };
      await _database.putCache(cacheKey, payload);
      final cache = await _database.readCacheEntry(cacheKey);
      return _storeDetails(payload, lastSyncedAt: cache?.lastSyncedAt);
    } catch (_) {
      final cached = await _database.readCacheEntry(cacheKey);
      if (cached == null) rethrow;
      return _storeDetails(
        cached.payload,
        isStale: true,
        lastSyncedAt: cached.lastSyncedAt,
      );
    }
  }

  Future<ProductDetails> loadProduct(String publicId) async {
    final cacheKey = 'product_$publicId';
    try {
      final data = await _api.get('/products/${Uri.encodeComponent(publicId)}');
      final raw = data['product'] ?? data;
      final payload = raw is Map
          ? Map<String, dynamic>.from(raw)
          : const <String, dynamic>{};
      await _database.putCache(cacheKey, payload);
      final cache = await _database.readCacheEntry(cacheKey);
      return ProductDetails(
        product: StoreProduct.fromJson(payload),
        lastSyncedAt: cache?.lastSyncedAt,
      );
    } catch (_) {
      final cached = await _database.readCacheEntry(cacheKey);
      if (cached == null) rethrow;
      return ProductDetails(
        product: StoreProduct.fromJson(cached.payload),
        isStale: true,
        lastSyncedAt: cached.lastSyncedAt,
      );
    }
  }

  Future<List<ContentComment>> loadComments({
    required String kind,
    required String publicId,
  }) async {
    final prefix = kind == 'listing' ? '/marketplace/listings' : '/products';
    final cacheKey = 'comments_${kind}_$publicId';
    try {
      final data = await _api.get(
        '$prefix/${Uri.encodeComponent(publicId)}/comments',
      );
      await _database.putCache(cacheKey, data);
      return _comments(data);
    } catch (_) {
      final cached = await _database.readCache(cacheKey);
      if (cached == null) rethrow;
      return _comments(cached);
    }
  }

  Future<void> addComment({
    required String kind,
    required String publicId,
    required String body,
  }) async {
    final prefix = kind == 'listing' ? '/marketplace/listings' : '/products';
    await _api.post(
      '$prefix/${Uri.encodeComponent(publicId)}/comments',
      body: {'body': body.trim()},
    );
  }

  Future<void> deleteComment(String publicId) =>
      _api.delete('/comments/${Uri.encodeComponent(publicId)}');

  Future<ListingDetails> loadListing(String publicId) async {
    final cacheKey = 'listing_$publicId';
    try {
      final data = await _api.get(
        '/marketplace/listings/${Uri.encodeComponent(publicId)}',
      );
      final payload = <String, dynamic>{'listing': data['listing'] ?? data};
      await _database.putCache(cacheKey, payload);
      final cache = await _database.readCacheEntry(cacheKey);
      return _listingDetails(payload, lastSyncedAt: cache?.lastSyncedAt);
    } catch (_) {
      final cached = await _database.readCacheEntry(cacheKey);
      if (cached == null) rethrow;
      return _listingDetails(
        cached.payload,
        isStale: true,
        lastSyncedAt: cached.lastSyncedAt,
      );
    }
  }

  StoreDetails _storeDetails(
    Map<String, dynamic> payload, {
    bool isStale = false,
    DateTime? lastSyncedAt,
  }) {
    final storeRaw = payload['store'];
    final store = storeRaw is Map
        ? StoreSummary.fromJson(Map<String, dynamic>.from(storeRaw))
        : StoreSummary.fromJson(const {});
    final productsRaw = payload['products'];
    final products = (productsRaw is List ? productsRaw : const [])
        .whereType<Map>()
        .map((item) => StoreProduct.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    return StoreDetails(
      store: store,
      products: products,
      banners: _storeBanners(payload['banners']),
      isStale: isStale,
      lastSyncedAt: lastSyncedAt,
    );
  }

  ListingDetails _listingDetails(
    Map<String, dynamic> payload, {
    bool isStale = false,
    DateTime? lastSyncedAt,
  }) {
    final raw = payload['listing'];
    final listingMap = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    final mediaRaw = listingMap['media'];
    final mediaPublicIds = (mediaRaw is List ? mediaRaw : const [])
        .whereType<Map>()
        .map((item) => item['public_id'] as String?)
        .whereType<String>()
        .toList(growable: false);
    final listing = MarketplaceListing.fromJson(listingMap);
    final attributesRaw = listingMap['attributes'];
    final attributes = (attributesRaw is List ? attributesRaw : const [])
        .whereType<Map>()
        .map((item) => ListingAttribute.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.value.trim().isNotEmpty)
        .toList(growable: false);
    return ListingDetails(
      listing: listing,
      attributes: attributes,
      mediaPublicIds: mediaPublicIds.isEmpty && listing.mediaPublicId != null
          ? [listing.mediaPublicId!]
          : mediaPublicIds,
      isStale: isStale,
      lastSyncedAt: lastSyncedAt,
    );
  }

  DateTime? _latestAt(Iterable<CachedEntry?> entries) {
    final dates = entries.whereType<CachedEntry>().map(
      (entry) => entry.lastSyncedAt,
    );
    if (dates.isEmpty) return null;
    return dates.reduce((newest, date) => date.isAfter(newest) ? date : newest);
  }

  List<ContentComment> _comments(Map<String, dynamic> data) =>
      ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => ContentComment.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);

  List<StoreSummary> _stores(Map<String, dynamic> data) =>
      ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => StoreSummary.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);

  List<MarketplaceListing> _listings(Map<String, dynamic> data) =>
      ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                MarketplaceListing.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
}
