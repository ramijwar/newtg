final class StoreSummary {
  const StoreSummary({
    required this.publicId,
    required this.name,
    required this.description,
    required this.discoveryTagline,
    required this.logoMediaPublicId,
    required this.categoryName,
    required this.acceptsDelivery,
    required this.acceptsPickup,
    required this.currencyCode,
    required this.merchantName,
    this.allowsRetail = true,
    this.allowsPreorder = false,
    this.isWeeklyMostVisited = false,
    this.isBestSeller = false,
    this.viewCount = 0,
    this.salesCount = 0,
    this.isFollowing = false,
    this.productCount = 0,
    this.verificationStatus = 'not_submitted',
    this.whatsappPhone,
    this.phone,
    this.businessHours = const {},
    this.holidays = const [],
    this.followerCount = 0,
    this.reviewCount = 0,
    this.averageRating = 0,
    this.weeklyVisitCount = 0,
    this.addressCountryCode,
    this.addressCity,
    this.addressDistrict,
    this.addressLine1,
    this.createdAt,
  });

  final String publicId;
  final String name;
  final String? description;
  final String? discoveryTagline;
  final String? logoMediaPublicId;
  final String? categoryName;
  final bool acceptsDelivery;
  final bool acceptsPickup;
  final String currencyCode;
  final String? merchantName;
  final bool allowsRetail;
  final bool allowsPreorder;
  final bool isWeeklyMostVisited;
  final bool isBestSeller;
  final int viewCount;
  final int salesCount;
  final bool isFollowing;
  final int productCount;
  final String verificationStatus;
  final String? whatsappPhone;
  final String? phone;
  final Map<String, dynamic> businessHours;
  final List<Map<String, dynamic>> holidays;
  final int followerCount;
  final int reviewCount;
  final num averageRating;
  final int weeklyVisitCount;
  final String? addressCountryCode;
  final String? addressCity;
  final String? addressDistrict;
  final String? addressLine1;
  final String? createdAt;
  bool get isVerified => verificationStatus == 'verified';

  factory StoreSummary.fromJson(Map<String, dynamic> json) => StoreSummary(
    publicId: json['public_id'] as String? ?? '',
    name: json['name'] as String? ?? 'متجر محلي',
    description: json['description'] as String?,
    discoveryTagline: json['discovery_tagline'] as String?,
    logoMediaPublicId: json['logo_media_public_id'] as String?,
    categoryName: json['category_name'] as String?,
    acceptsDelivery: json['accepts_delivery'] != false,
    acceptsPickup: json['accepts_pickup'] != false,
    currencyCode: json['currency_code'] as String? ?? 'USD',
    merchantName: json['merchant_name'] as String?,
    allowsRetail: json['allows_retail'] != false,
    allowsPreorder: json['allows_preorder'] == true,
    isWeeklyMostVisited: json['is_weekly_most_visited'] == true,
    isBestSeller: json['is_best_seller'] == true,
    viewCount: (json['view_count'] as num?)?.toInt() ?? int.tryParse('${json['view_count'] ?? ''}') ?? 0,
    salesCount: (json['sales_count'] as num?)?.toInt() ?? int.tryParse('${json['sales_count'] ?? ''}') ?? 0,
    isFollowing: json['is_following'] == true,
    productCount: (json['product_count'] as num?)?.toInt() ?? int.tryParse('${json['product_count'] ?? ''}') ?? 0,
    verificationStatus: json['verification_status'] as String? ?? 'not_submitted',
    whatsappPhone: json['whatsapp_phone'] as String?,
    phone: json['phone'] as String?,
    businessHours: json['business_hours'] is Map ? Map<String, dynamic>.from(json['business_hours'] as Map) : const {},
    holidays: (json['holidays'] as List? ?? const []).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(growable: false),
    followerCount: (json['follower_count'] as num?)?.toInt() ?? int.tryParse('${json['follower_count'] ?? ''}') ?? 0,
    reviewCount: (json['review_count'] as num?)?.toInt() ?? int.tryParse('${json['review_count'] ?? ''}') ?? 0,
    averageRating: (json['average_rating'] as num?) ?? num.tryParse('${json['average_rating'] ?? ''}') ?? 0,
    weeklyVisitCount: (json['weekly_visit_count'] as num?)?.toInt() ?? int.tryParse('${json['weekly_visit_count'] ?? ''}') ?? 0,
    addressCountryCode: json['address_country_code'] as String?,
    addressCity: json['address_city'] as String?,
    addressDistrict: json['address_district'] as String?,
    addressLine1: json['address_line1'] as String?,
    createdAt: json['created_at'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'public_id': publicId,
    'name': name,
    'description': description,
    'discovery_tagline': discoveryTagline,
    'logo_media_public_id': logoMediaPublicId,
    'category_name': categoryName,
    'accepts_delivery': acceptsDelivery,
    'accepts_pickup': acceptsPickup,
    'currency_code': currencyCode,
    'merchant_name': merchantName,
    'allows_retail': allowsRetail,
    'allows_preorder': allowsPreorder,
    'is_weekly_most_visited': isWeeklyMostVisited,
    'is_best_seller': isBestSeller,
    'view_count': viewCount,
    'sales_count': salesCount,
    'is_following': isFollowing,
    'product_count': productCount,
    'verification_status': verificationStatus,
    'whatsapp_phone': whatsappPhone,
    'phone': phone,
    'business_hours': businessHours,
    'holidays': holidays,
    'follower_count': followerCount,
    'review_count': reviewCount,
    'average_rating': averageRating,
    'weekly_visit_count': weeklyVisitCount,
    'address_country_code': addressCountryCode,
    'address_city': addressCity,
    'address_district': addressDistrict,
    'address_line1': addressLine1,
    'created_at': createdAt,
  };
}

final class MarketplaceListing {
  const MarketplaceListing({
    required this.publicId,
    required this.title,
    required this.priceAmount,
    required this.currencyCode,
    required this.city,
    required this.categoryName,
    required this.mediaPublicId,
    required this.description,
    required this.sellerName,
    required this.sellerPublicId,
    required this.itemCondition,
    required this.fulfillmentMethod,
    required this.viewCount,
    required this.commentCount,
    this.countryCode,
    this.district,
    this.addressText,
    this.phone,
    this.listingType,
    this.isNegotiable = false,
    this.isFavorite = false,
    this.listingStatus,
    this.publishedAt,
    this.expiresAt,
  });

  final String publicId;
  final String title;
  final num? priceAmount;
  final String currencyCode;
  final String? city;
  final String? categoryName;
  final String? mediaPublicId;
  final String? description;
  final String? sellerName;
  final String? sellerPublicId;
  final String? itemCondition;
  final String? fulfillmentMethod;
  final int viewCount;
  final int commentCount;
  final String? countryCode;
  final String? district;
  final String? addressText;
  final String? phone;
  final String? listingType;
  final bool isNegotiable;
  final bool isFavorite;
  final String? listingStatus;
  final String? publishedAt;
  final String? expiresAt;

  factory MarketplaceListing.fromJson(Map<String, dynamic> json) =>
      MarketplaceListing(
        publicId: json['public_id'] as String? ?? '',
        title: json['title'] as String? ?? 'إعلان حراج',
        priceAmount: json['price_amount'] is num
            ? json['price_amount'] as num
            : num.tryParse('${json['price_amount'] ?? ''}'),
        currencyCode: json['currency_code'] as String? ?? 'USD',
        city: json['city'] as String?,
        categoryName: json['category_name'] as String?,
        mediaPublicId: json['primary_media_public_id'] as String?,
        description: json['description'] as String?,
        sellerName: json['seller_name'] as String?,
        sellerPublicId: json['seller_public_id'] as String?,
        itemCondition: json['item_condition'] as String?,
        fulfillmentMethod: json['fulfillment_method'] as String?,
        viewCount:
            (json['view_count'] as num?)?.toInt() ??
            int.tryParse('${json['view_count'] ?? ''}') ??
            0,
        commentCount:
            (json['comment_count'] as num?)?.toInt() ??
            int.tryParse('${json['comment_count'] ?? ''}') ??
            0,
        countryCode: json['country_code'] as String?,
        district: json['district'] as String?,
        addressText: json['address_text'] as String?,
        phone: json['phone'] as String?,
        listingType: json['listing_type'] as String?,
        isNegotiable: json['is_negotiable'] == true || json['is_negotiable'] == 1,
        isFavorite: json['is_favorite'] == true || json['is_favorite'] == 1 || json['is_favorite'] == '1',
        listingStatus: json['listing_status'] as String?,
        publishedAt: json['published_at'] as String?,
        expiresAt: json['expires_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'public_id': publicId,
    'title': title,
    'price_amount': priceAmount,
    'currency_code': currencyCode,
    'city': city,
    'category_name': categoryName,
    'primary_media_public_id': mediaPublicId,
    'description': description,
    'seller_name': sellerName,
    'seller_public_id': sellerPublicId,
    'item_condition': itemCondition,
    'fulfillment_method': fulfillmentMethod,
    'view_count': viewCount,
    'comment_count': commentCount,
    'country_code': countryCode,
    'district': district,
    'address_text': addressText,
    'phone': phone,
    'listing_type': listingType,
    'is_negotiable': isNegotiable,
    'is_favorite': isFavorite,
    'listing_status': listingStatus,
    'published_at': publishedAt,
    'expires_at': expiresAt,
  };
}

final class StoreProduct {
  const StoreProduct({
    required this.publicId,
    required this.name,
    required this.description,
    required this.price,
    required this.effectivePrice,
    required this.currencyCode,
    required this.stockQuantity,
    required this.categoryName,
    required this.categoryPublicId,
    required this.sku,
    required this.lowStockThreshold,
    required this.productStatus,
    required this.mediaPublicId,
    required this.viewCount,
    required this.commentCount,
    this.salePrice,
    this.saleStartsAt,
    this.saleEndsAt,
    this.isSpecialOffer = false,
    this.fulfillmentMode = 'retail',
    this.preorderMinQuantity,
    this.preorderMaxQuantity,
    this.preorderLeadDays,
    this.storeName,
    this.storeAverageRating,
  });

  final String publicId;
  final String name;
  final String? description;
  final num price;
  final num effectivePrice;
  final String currencyCode;
  final int stockQuantity;
  final String? categoryName;
  final String? categoryPublicId;
  final String? sku;
  final int lowStockThreshold;
  final String productStatus;
  final String? mediaPublicId;
  final int viewCount;
  final int commentCount;
  final num? salePrice;
  final String? saleStartsAt;
  final String? saleEndsAt;
  final bool isSpecialOffer;
  final String fulfillmentMode;
  final int? preorderMinQuantity;
  final int? preorderMaxQuantity;
  final int? preorderLeadDays;
  final String? storeName;
  final num? storeAverageRating;
  static num _number(Object? value, [num fallback = 0]) => value is num ? value : num.tryParse('${value ?? ''}') ?? fallback;
  static num? _nullableNumber(Object? value) { if (value == null || '$value'.trim().isEmpty) return null; return value is num ? value : num.tryParse('$value'); }
  static int? _nullableInteger(Object? value) { final number = _nullableNumber(value); return number?.toInt(); }

  bool get isActiveSpecialOffer {
    if (!isSpecialOffer || salePrice == null || saleEndsAt == null) return false;
    final now = DateTime.now();
    final ending = DateTime.tryParse(saleEndsAt!);
    final starting = saleStartsAt == null ? null : DateTime.tryParse(saleStartsAt!);
    return ending != null && ending.isAfter(now) && (starting == null || !starting.isAfter(now));
  }

  factory StoreProduct.fromJson(Map<String, dynamic> json) => StoreProduct(
    publicId: json['public_id'] as String? ?? '',
    name: json['name'] as String? ?? 'منتج متجر',
    description: json['description'] as String?,
    price: _number(json['price']),
    effectivePrice: _number(json['effective_price'], _number(json['price'])),
    currencyCode: json['currency_code'] as String? ?? 'USD',
    stockQuantity: (json['stock_quantity'] as num?)?.toInt() ?? 0,
    categoryName: json['category_name'] as String?,
    categoryPublicId: json['category_public_id'] as String?,
    sku: json['sku'] as String?,
    lowStockThreshold: (json['low_stock_threshold'] as num?)?.toInt() ?? 0,
    productStatus: json['product_status'] as String? ?? 'active',
    mediaPublicId: json['primary_media_public_id'] as String?,
    viewCount:
        (json['view_count'] as num?)?.toInt() ??
        int.tryParse('${json['view_count'] ?? ''}') ??
        0,
    commentCount:
        (json['comment_count'] as num?)?.toInt() ??
        int.tryParse('${json['comment_count'] ?? ''}') ??
        0,
    salePrice: _nullableNumber(json['sale_price']),
    saleStartsAt: json['sale_starts_at'] as String?,
    saleEndsAt: json['sale_ends_at'] as String?,
    isSpecialOffer: json['is_special_offer'] == true || json['is_special_offer'] == 1 || json['is_special_offer'] == '1',
    fulfillmentMode: json['fulfillment_mode'] as String? ?? 'retail',
    preorderMinQuantity: _nullableInteger(json['preorder_min_quantity']),
    preorderMaxQuantity: _nullableInteger(json['preorder_max_quantity']),
    preorderLeadDays: _nullableInteger(json['preorder_lead_days']),
    storeName: json['store_name'] as String?,
    storeAverageRating: _nullableNumber(json['store_average_rating']),
  );

  Map<String, dynamic> toJson() => {
    'public_id': publicId,
    'name': name,
    'description': description,
    'price': price,
    'effective_price': effectivePrice,
    'currency_code': currencyCode,
    'stock_quantity': stockQuantity,
    'category_name': categoryName,
    'category_public_id': categoryPublicId,
    'sku': sku,
    'low_stock_threshold': lowStockThreshold,
    'product_status': productStatus,
    'primary_media_public_id': mediaPublicId,
    'view_count': viewCount,
    'comment_count': commentCount,
    'sale_price': salePrice,
    'sale_starts_at': saleStartsAt,
    'sale_ends_at': saleEndsAt,
    'is_special_offer': isSpecialOffer,
    'fulfillment_mode': fulfillmentMode,
    'preorder_min_quantity': preorderMinQuantity,
    'preorder_max_quantity': preorderMaxQuantity,
    'preorder_lead_days': preorderLeadDays,
    'store_name': storeName,
    'store_average_rating': storeAverageRating,
  };
}

final class ContentComment {
  const ContentComment({
    required this.publicId,
    required this.body,
    required this.authorName,
    required this.authorPublicId,
    required this.authorIsAdmin,
    required this.createdAt,
    this.authorAvatarMediaPublicId,
  });
  final String publicId;
  final String body;
  final String authorName;
  final String authorPublicId;
  final bool authorIsAdmin;
  final String? createdAt;
  final String? authorAvatarMediaPublicId;

  factory ContentComment.fromJson(Map<String, dynamic> json) {
    final author = json['author'] is Map
        ? Map<String, dynamic>.from(json['author'] as Map)
        : const <String, dynamic>{};
    return ContentComment(
      publicId: json['public_id'] as String? ?? '',
      body: json['body'] as String? ?? '',
      authorName: author['full_name'] as String? ?? 'مستخدم',
      authorPublicId: author['public_id'] as String? ?? '',
      authorIsAdmin: author['is_admin'] == true,
      createdAt: json['created_at'] as String?,
    );
  }
}

final class ProductDetails {
  const ProductDetails({
    required this.product,
    this.isStale = false,
    this.lastSyncedAt,
  });
  final StoreProduct product;
  final bool isStale;
  final DateTime? lastSyncedAt;
}

final class StoreBanner {
  const StoreBanner({required this.publicId, required this.mediaPublicId, required this.destinationType, this.title, this.body, this.destinationProductId, this.destinationStoreId, this.externalUrl});
  final String publicId; final String mediaPublicId; final String destinationType; final String? title; final String? body; final String? destinationProductId; final String? destinationStoreId; final String? externalUrl;
  factory StoreBanner.fromJson(Map<String, dynamic> json) => StoreBanner(publicId: json['public_id'] as String? ?? '', mediaPublicId: json['media_public_id'] as String? ?? '', destinationType: json['destination_type'] as String? ?? 'none', title: json['title'] as String?, body: json['body'] as String?, destinationProductId: json['destination_product_id'] as String?, destinationStoreId: json['destination_store_id'] as String?, externalUrl: json['external_url'] as String?);
}

final class StoreDetails {
  const StoreDetails({
    required this.store,
    required this.products,
    this.banners = const [],
    this.isStale = false,
    this.lastSyncedAt,
  });

  final StoreSummary store;
  final List<StoreProduct> products;
  final List<StoreBanner> banners;
  final bool isStale;
  final DateTime? lastSyncedAt;
}

final class ListingAttribute {
  const ListingAttribute({
    required this.publicId,
    required this.label,
    required this.value,
    required this.fieldType,
  });

  final String publicId;
  final String label;
  final String value;
  final String fieldType;

  factory ListingAttribute.fromJson(Map<String, dynamic> json) => ListingAttribute(
    publicId: json['public_id'] as String? ?? '',
    label: json['label'] as String? ?? 'خاصية الإعلان',
    value: json['value']?.toString() ?? '',
    fieldType: json['field_type'] as String? ?? 'text',
  );
}

final class ListingDetails {
  const ListingDetails({
    required this.listing,
    required this.mediaPublicIds,
    required this.attributes,
    this.isStale = false,
    this.lastSyncedAt,
  });

  final MarketplaceListing listing;
  final List<String> mediaPublicIds;
  final List<ListingAttribute> attributes;
  final bool isStale;
  final DateTime? lastSyncedAt;
}

final class HomeFeed {
  const HomeFeed({
    required this.stores,
    required this.listings,
    this.isStale = false,
    this.lastSyncedAt,
  });

  final List<StoreSummary> stores;
  final List<MarketplaceListing> listings;
  final bool isStale;
  final DateTime? lastSyncedAt;
}
