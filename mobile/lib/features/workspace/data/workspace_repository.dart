import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../catalog/domain/catalog_models.dart';

final class MerchantWorkspace {
  const MerchantWorkspace({
    required this.store,
    required this.products,
    required this.storeAccessState,
    this.pendingPayments = const [],
  });
  final Map<String, dynamic>? store;
  final List<StoreProduct> products;
  final String storeAccessState;
  final List<Map<String, dynamic>> pendingPayments;
}

final class CourierWorkspace {
  const CourierWorkspace({required this.profile, required this.tasks});
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> tasks;
}

final class AdminWorkspace {
  const AdminWorkspace({
    required this.stores,
    required this.listings,
    required this.verifications,
  });
  final List<Map<String, dynamic>> stores;
  final List<Map<String, dynamic>> listings;
  final List<Map<String, dynamic>> verifications;
}

/// Queues that require an explicit administrator decision. Manual payments are
/// a merchant-final workflow, so administrators receive an auditable read-only log.
final class AdminDecisionQueues {
  const AdminDecisionQueues({
    required this.payments,
    required this.withdrawals,
    required this.supportTickets,
    required this.reports,
    required this.disputes,
    required this.promotions,
  });

  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> withdrawals;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> disputes;
  final List<Map<String, dynamic>> promotions;
}

final class StoreCategoryOption {
  const StoreCategoryOption({required this.publicId, required this.name});
  final String publicId;
  final String name;

  factory StoreCategoryOption.fromJson(Map<String, dynamic> json) =>
      StoreCategoryOption(
        publicId: json['public_id'] as String? ?? '',
        name: json['name'] as String? ?? 'قسم',
      );
}

final class WorkspaceRepository {
  WorkspaceRepository(this._api);
  final ApiClient _api;
  int _operationCounter = 0;

  Future<MerchantWorkspace> merchantWorkspace() async {
    final storeData = await _api.get('/merchant/store');
    final storeRaw = storeData['store'];
    final store = storeRaw is Map ? Map<String, dynamic>.from(storeRaw) : null;
    if (store == null || (store['public_id'] as String? ?? '').isEmpty) {
      final state = storeData['store_access_state'] as String? ?? 'none';
      return MerchantWorkspace(store: null, products: const <StoreProduct>[], storeAccessState: state, pendingPayments: const <Map<String, dynamic>>[]);
    }
    final responses = await Future.wait([
      _api.get('/merchant/products', query: const {'per_page': 100}),
      _api.get('/merchant/payments/review-queue'),
    ]);
    final productRaw = responses[0]['items'];
    final paymentRaw = responses[1]['items'];
    return MerchantWorkspace(
      store: store,
      storeAccessState: 'available',
      products: (productRaw is List ? productRaw : const []).whereType<Map>().map((item) => StoreProduct.fromJson(Map<String, dynamic>.from(item))).toList(growable: false),
      pendingPayments: (paymentRaw is List ? paymentRaw : const []).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(growable: false),
    );
  }

  Future<AdminWorkspace> adminWorkspace() async {
    final results = await Future.wait([
      _api.get('/admin/stores'),
      _api.get('/admin/marketplace/listings'),
      _api.get('/admin/verification-requests'),
    ]);
    List<Map<String, dynamic>> items(Map<String, dynamic> data) =>
        ((data['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
    return AdminWorkspace(
      stores: items(results[0]),
      listings: items(results[1]),
      verifications: items(results[2]),
    );
  }

  Future<List<Map<String, dynamic>>> adminPromotionPlans() async =>
      _mapItems(await _api.get('/admin/marketplace/promotion-plans'));

  Future<void> saveAdminPromotionPlan({
    String? code,
    String? currencyCode,
    required Map<String, dynamic> body,
  }) async {
    if (code == null || currencyCode == null) {
      await _api.post('/admin/marketplace/promotion-plans', body: body);
      return;
    }
    await _api.patch(
      '/admin/marketplace/promotion-plans/${Uri.encodeComponent(code)}/${Uri.encodeComponent(currencyCode)}',
      body: body,
    );
  }

  /// Full category controls used by the store and product catalogue tabs.
  Future<List<Map<String, dynamic>>> adminCatalogCategories(String type) async =>
      _mapItems(await _api.get('/admin/catalog-categories', query: {'type': type}));

  Future<void> saveAdminCatalogCategory({
    required String type,
    String? publicId,
    required Map<String, dynamic> body,
  }) async {
    final path = publicId == null
        ? '/admin/catalog-categories'
        : '/admin/catalog-categories/${Uri.encodeComponent(publicId)}';
    await (publicId == null
        ? _api.post(path, body: {'category_type': type, ...body})
        : _api.patch(path, body: body));
  }

  Future<String> uploadAdminPublicMedia(XFile image) async {
    final data = await _api.postForm(
      '/media',
      body: FormData.fromMap({
        'visibility': 'public',
        'file': await MultipartFile.fromFile(image.path, filename: image.name),
      }),
      idempotencyKey: _operationKey('admin-catalog-image'),
    );
    final media = Map<String, dynamic>.from(data['media'] as Map? ?? const {});
    final publicId = media['public_id'] as String?;
    if (publicId == null || publicId.isEmpty) {
      throw const FormatException('لم يعد الخادم معرفاً صالحاً لصورة التصنيف.');
    }
    return publicId;
  }

  Future<List<Map<String, dynamic>>> adminMarketplaceCategories() async {
    final data = await _api.get('/admin/marketplace/categories');
    return _mapItems(data);
  }

  Future<List<Map<String, dynamic>>> adminMarketplaceAttributes(
    String categoryId,
  ) async {
    final data = await _api.get(
      '/admin/marketplace/categories/${Uri.encodeComponent(categoryId)}/attributes',
    );
    return _mapItems(data);
  }

  Future<List<Map<String, dynamic>>> adminMarketplaceCountries() async =>
      _mapItems(await _api.get('/admin/marketplace/locations/countries'));

  Future<List<Map<String, dynamic>>> adminMarketplaceCities(
    String countryId,
  ) async => _mapItems(
    await _api.get(
      '/admin/marketplace/locations/cities',
      query: {'country_id': countryId},
    ),
  );

  Future<List<Map<String, dynamic>>> adminMarketplaceDistricts(
    String cityId,
  ) async => _mapItems(
    await _api.get(
      '/admin/marketplace/locations/districts',
      query: {'city_id': cityId},
    ),
  );

  Future<void> createAdminMarketplaceAttributeWithOptions({
    required Map<String, dynamic> body,
    required List<String> options,
  }) async {
    final created = await _api.post('/admin/marketplace/attributes', body: body);
    final attribute = Map<String, dynamic>.from(
      created['attribute'] as Map? ?? const {},
    );
    final attributeId = attribute['public_id'] as String?;
    if (attributeId == null || attributeId.isEmpty) {
      throw const FormatException('لم يعد الخادم معرف الخاصية الجديدة.');
    }
    await Future.wait(
      options.asMap().entries.map(
        (entry) => _api.post(
          '/admin/marketplace/attributes/${Uri.encodeComponent(attributeId)}/options',
          body: {'option_value': entry.value, 'sort_order': entry.key},
        ),
      ),
    );
  }

  Future<void> saveAdminMarketplaceEntity({
    required String type,
    String? publicId,
    required Map<String, dynamic> body,
  }) async {
    final collection = switch (type) {
      'category' => '/admin/marketplace/categories',
      'attribute' => '/admin/marketplace/attributes',
      'country' => '/admin/marketplace/locations/countries',
      'city' => '/admin/marketplace/locations/cities',
      'district' => '/admin/marketplace/locations/districts',
      _ => throw ArgumentError('نوع إعداد الحراج غير معروف.'),
    };
    if (publicId == null) {
      await _api.post(collection, body: body);
    } else {
      await _api.patch(
        '$collection/${Uri.encodeComponent(publicId)}',
        body: body,
      );
    }
  }

  Future<void> deleteAdminMarketplaceLocation({
    required String type,
    required String publicId,
  }) async {
    final collection = switch (type) {
      'country' => '/admin/marketplace/locations/countries',
      'city' => '/admin/marketplace/locations/cities',
      'district' => '/admin/marketplace/locations/districts',
      _ => throw ArgumentError('لا يدعم هذا العنصر الحذف.'),
    };
    await _api.delete('$collection/${Uri.encodeComponent(publicId)}');
  }

  Future<AdminDecisionQueues> adminDecisionQueues() async {
    final responses = await Future.wait([
      _api.get('/admin/payments/manual-log', query: const {'per_page': '100'}),
      _api.get('/admin/withdrawals'),
      _api.get('/admin/support/tickets'),
      _api.get('/admin/marketplace/reports'),
      _api.get('/admin/marketplace/disputes'),
      _api.get('/admin/marketplace/promotions/review-queue'),
    ]);
    List<Map<String, dynamic>> items(Map<String, dynamic> data) =>
        ((data['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
    return AdminDecisionQueues(
      payments: items(responses[0]),
      withdrawals: items(responses[1]),
      supportTickets: items(responses[2]),
      reports: items(responses[3]),
      disputes: items(responses[4]),
      promotions: items(responses[5]),
    );
  }

  Future<List<Map<String, dynamic>>> merchantPaymentQueue() =>
      _mapItemsAsync(_api.get('/merchant/payments/review-queue'));

  Future<void> reviewMerchantPayment({
    required String orderId,
    required String decision,
    String note = '',
  }) => _api.post(
    '/merchant/orders/${Uri.encodeComponent(orderId)}/payment-review',
    body: {'decision': decision, 'note': note.trim()},
    idempotencyKey: _operationKey('merchant-payment-review'),
  );

  Future<Uint8List> merchantPaymentReceipt(String orderId) =>
      _api.getBytes('/merchant/orders/${Uri.encodeComponent(orderId)}/payment-receipt');

  Future<List<Map<String, dynamic>>> adminManualPaymentLog() =>
      _mapItemsAsync(_api.get('/admin/payments/manual-log', query: {'per_page': '100'}));

  Future<void> reviewAdminPayment({
    required String orderId,
    required String decision,
    String note = '',
  }) => _api.post(
    '/admin/orders/${Uri.encodeComponent(orderId)}/payment-review',
    body: {'decision': decision, 'note': note.trim()},
    idempotencyKey: _operationKey('admin-payment-review'),
  );

  Future<void> cancelAdminOrder({
    required String orderId,
    required String reason,
  }) => _api.post(
    '/admin/orders/${Uri.encodeComponent(orderId)}/cancel',
    body: {'reason': reason.trim()},
    idempotencyKey: _operationKey('admin-order-cancel'),
  );

  Future<void> decideAdminWithdrawal({
    required String withdrawalId,
    required String decision,
    String note = '',
  }) => _api.post(
    '/admin/withdrawals/${Uri.encodeComponent(withdrawalId)}/decision',
    body: {'decision': decision, 'note': note.trim()},
    idempotencyKey: _operationKey('admin-withdrawal-decision'),
  );

  Future<void> updateAdminReport({
    required String reportId,
    required String status,
  }) => _api.patch(
    '/admin/marketplace/reports/${Uri.encodeComponent(reportId)}',
    body: {'report_status': status},
  );

  Future<void> decideAdminDispute({
    required String disputeId,
    required String decision,
    required String note,
  }) => _api.post(
    '/admin/marketplace/disputes/${Uri.encodeComponent(disputeId)}/decision',
    body: {'decision': decision, 'resolution_note': note.trim()},
  );

  Future<void> reviewAdminPromotion({
    required String promotionId,
    required String decision,
  }) => _api.post(
    '/admin/marketplace/promotions/${Uri.encodeComponent(promotionId)}/payment-review',
    body: {'decision': decision},
  );

  Future<void> replyAdminSupportTicket({
    required String ticketId,
    required String body,
  }) => _api.post(
    '/admin/support/tickets/${Uri.encodeComponent(ticketId)}/messages',
    body: {'body': body.trim()},
  );

  Future<void> updateAdminSupportTicket({
    required String ticketId,
    required String status,
  }) => _api.patch(
    '/admin/support/tickets/${Uri.encodeComponent(ticketId)}/status',
    body: {'ticket_status': status},
  );

  Future<Uint8List> adminPaymentReceipt(String orderId) => _api.getBytes(
    '/admin/orders/${Uri.encodeComponent(orderId)}/payment-receipt',
  );

  Future<Uint8List> adminPromotionReceipt(String promotionId) => _api.getBytes(
    '/admin/marketplace/promotions/${Uri.encodeComponent(promotionId)}/payment-receipt',
  );

  Future<Uint8List> adminVerificationMedia(
    String verificationId,
    String type,
  ) => _api.getBytes(
    '/admin/verification-requests/${Uri.encodeComponent(verificationId)}/media/${Uri.encodeComponent(type)}',
  );

  Future<List<Map<String, dynamic>>> adminUsers({
    String search = '',
    String role = '',
    String status = '',
  }) async {
    final query = <String, String>{'per_page': '100'};
    if (search.trim().isNotEmpty) query['search'] = search.trim();
    if (role.isNotEmpty) query['role'] = role;
    if (status.isNotEmpty) query['status'] = status;
    final data = await _api.get('/admin/users', query: query);
    return ((data['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createAdminUser(
    Map<String, dynamic> input,
  ) async {
    final data = await _api.post('/admin/users', body: input);
    return Map<String, dynamic>.from(data['user'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateAdminUser(
    String userId,
    Map<String, dynamic> input,
  ) async {
    final data = await _api.patch(
      '/admin/users/${Uri.encodeComponent(userId)}',
      body: input,
    );
    return Map<String, dynamic>.from(data['user'] as Map? ?? const {});
  }

  Future<void> deleteAdminUser(String userId) =>
      _api.delete('/admin/users/${Uri.encodeComponent(userId)}');

  Future<List<Map<String, dynamic>>> adminStores() =>
      _mapItemsAsync(_api.get('/admin/stores', query: {'per_page': '100'}));

  Future<Map<String, dynamic>> adminStoreDetail(String storeId) => _api.get('/admin/stores/${Uri.encodeComponent(storeId)}');

  Future<Map<String, dynamic>> adminProductDetail(String productId) async {
    final data = await _api.get('/admin/products/${Uri.encodeComponent(productId)}');
    return {
      ...Map<String, dynamic>.from(data['product'] as Map? ?? const {}),
      'media': (data['media'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false) ??
          const <Map<String, dynamic>>[],
    };
  }

  Future<List<Map<String, dynamic>>> adminProducts({
    String search = '',
    String status = '',
  }) => _mapItemsAsync(
    _api.get('/admin/products', query: {
      'per_page': '100',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (status.isNotEmpty) 'status': status,
    }),
  );

  Future<Map<String, dynamic>> adminOrderDetail(String orderId) async {
    final data = await _api.get('/admin/orders/${Uri.encodeComponent(orderId)}');
    return {
      ...Map<String, dynamic>.from(data['order'] as Map? ?? const {}),
      'items': (data['items'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false) ??
          const <Map<String, dynamic>>[],
      'history': (data['history'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false) ??
          const <Map<String, dynamic>>[],
      if (data['store_snapshot'] is Map)
        'store_snapshot': Map<String, dynamic>.from(data['store_snapshot'] as Map),
      if (data['delivery_address'] is Map)
        'delivery_address': Map<String, dynamic>.from(data['delivery_address'] as Map),
    };
  }

  Future<List<Map<String, dynamic>>> adminOrders({
    String search = '',
    String orderStatus = '',
    String paymentStatus = '',
  }) => _mapItemsAsync(
    _api.get('/admin/orders', query: {
      'per_page': '100',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (orderStatus.isNotEmpty) 'order_status': orderStatus,
      if (paymentStatus.isNotEmpty) 'payment_status': paymentStatus,
    }),
  );

  Future<List<Map<String, dynamic>>> adminCouriers({
    String search = '',
    String verificationStatus = '',
    String workStatus = '',
  }) => _mapItemsAsync(
    _api.get('/admin/couriers', query: {
      'per_page': '100',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (verificationStatus.isNotEmpty) 'verification_status': verificationStatus,
      if (workStatus.isNotEmpty) 'work_status': workStatus,
    }),
  );

  Future<Map<String, dynamic>> adminCourierDetail(String courierId) =>
      _api.get('/admin/couriers/${Uri.encodeComponent(courierId)}');

  Future<void> updateAdminCourierVerification({
    required String courierId,
    required String status,
  }) => _api.patch(
    '/admin/couriers/${Uri.encodeComponent(courierId)}/verification',
    body: {'verification_status': status},
  );

  Future<void> updateAdminCourierWorkStatus({
    required String courierId,
    required String status,
  }) => _api.patch(
    '/admin/couriers/${Uri.encodeComponent(courierId)}/work-status',
    body: {'work_status': status},
  );

  Future<List<Map<String, dynamic>>> adminMarketplaceTransactions({
    String search = '',
    String status = '',
  }) => _mapItemsAsync(
    _api.get('/admin/marketplace/transactions', query: {
      'per_page': '100',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (status.isNotEmpty) 'transaction_status': status,
    }),
  );

  Future<Map<String, dynamic>> adminMarketplaceTransactionDetail(
    String transactionId,
  ) => _api.get(
    '/admin/marketplace/transactions/${Uri.encodeComponent(transactionId)}',
  );

  Future<List<Map<String, dynamic>>> adminDeliveryTasks({
    String search = '',
    String status = '',
    String sourceType = '',
    String courierId = '',
  }) => _mapItemsAsync(
    _api.get('/admin/delivery-tasks', query: {
      'per_page': '100',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (status.isNotEmpty) 'task_status': status,
      if (sourceType.isNotEmpty) 'source_type': sourceType,
      if (courierId.isNotEmpty) 'courier_id': courierId,
    }),
  );

  Future<Map<String, dynamic>> adminDeliveryTaskDetail(String taskId) =>
      _api.get('/admin/delivery-tasks/${Uri.encodeComponent(taskId)}');

  Future<Uint8List> adminDeliveryTaskProof({
    required String taskId,
    required String proofType,
  }) => _api.getBytes(
    '/admin/delivery-tasks/${Uri.encodeComponent(taskId)}/proof/${Uri.encodeComponent(proofType)}',
  );

  Future<void> updateAdminProductStatus({
    required String productId,
    required String status,
  }) => _api.patch(
    '/admin/products/${Uri.encodeComponent(productId)}/status',
    body: {'product_status': status},
  );

  Future<void> adminDeleteProduct(String productId) =>
      _api.delete('/admin/products/${Uri.encodeComponent(productId)}');

  Future<void> adminDeleteListing(String listingId) => _api.delete(
    '/admin/marketplace/listings/${Uri.encodeComponent(listingId)}',
  );

  Future<Map<String, dynamic>> adminModerationSettings() async {
    final data = await _api.get('/admin/marketplace/settings');
    final raw = data['settings'];
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  Future<void> updateAdminModerationSettings({
    required bool autoApproveListings,
    required bool requireListingImage,
  }) => _api.patch(
    '/admin/marketplace/settings',
    body: {
      'auto_approve_listings': autoApproveListings,
      'require_listing_image': requireListingImage,
    },
  );

  Future<List<Map<String, dynamic>>> adminFeeRules() async {
    final data = await _api.get('/admin/fee-rules');
    final raw = data['items'];
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> updateAdminFeeRule(Map<String, dynamic> input) =>
      _api.patch('/admin/fee-rules', body: input);

  Future<Map<String, dynamic>> adminOperationalHealth() async {
    final data = await _api.get('/admin/operations/health');
    final health = data['health'];
    return health is Map ? Map<String, dynamic>.from(health) : const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> adminNotificationSettings() async {
    final data = await _api.get('/admin/notification-settings');
    final raw = data['settings'];
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  Future<void> updateAdminNotificationSettings({
    required bool inAppEnabled,
    required bool pushEnabled,
  }) => _api.patch(
    '/admin/notification-settings',
    body: {'in_app_enabled': inAppEnabled, 'push_enabled': pushEnabled},
  );

  Future<void> updateStoreReview(String storeId, String status) => _api.patch(
    '/admin/stores/${Uri.encodeComponent(storeId)}/status',
    body: {'store_status': status},
  );

  Future<void> updateAdminStoreVerification({
    required String storeId,
    required bool isVerified,
  }) => _api.patch(
    '/admin/stores/${Uri.encodeComponent(storeId)}/verification',
    body: {'is_verified': isVerified},
  );

  Future<void> adminDeleteStore(String storeId) =>
      _api.delete('/admin/stores/${Uri.encodeComponent(storeId)}');

  Future<void> setAdminStoreSuspended({
    required String storeId,
    required bool suspended,
  }) => _api.patch(
    '/admin/stores/${Uri.encodeComponent(storeId)}/status',
    body: {'store_status': suspended ? 'suspended' : 'active'},
  );

  Future<void> updateListingReview(String listingId, String status) =>
      _api.patch(
        '/admin/marketplace/listings/${Uri.encodeComponent(listingId)}/status',
        body: {'listing_status': status},
      );

  Future<List<Map<String, dynamic>>> myVerificationRequests() async =>
      _mapItems(await _api.get('/verification-requests/me'));

  Future<void> submitVerificationRequest({
    required String roleCode,
    required XFile identity,
    required XFile selfie,
  }) async {
    final mediaIds = await Future.wait([
      _uploadPrivateMedia(identity, 'verification-identity-upload'),
      _uploadPrivateMedia(selfie, 'verification-selfie-upload'),
    ]);
    await _api.post(
      '/verification-requests',
      body: {
        'role_code': roleCode,
        'identity_media_id': mediaIds[0],
        'selfie_media_id': mediaIds[1],
      },
      idempotencyKey: _operationKey('verification-submit'),
    );
  }

  Future<String> _uploadPrivateMedia(XFile image, String operation) async {
    final uploadData = await _api.postForm(
      '/media',
      body: FormData.fromMap({
        'visibility': 'private',
        'file': await MultipartFile.fromFile(image.path, filename: image.name),
      }),
      idempotencyKey: _operationKey(operation),
    );
    final media = Map<String, dynamic>.from(
      uploadData['media'] as Map? ?? const <String, dynamic>{},
    );
    final mediaId = media['public_id'] as String?;
    if (mediaId == null || mediaId.isEmpty) {
      throw const FormatException('لم يعد الخادم معرفاً صالحاً لملف التوثيق.');
    }
    return mediaId;
  }

  Future<void> decideVerification({
    required String verificationId,
    required String status,
    String reviewerNote = '',
  }) => _api.patch(
    '/admin/verification-requests/${Uri.encodeComponent(verificationId)}',
    body: {'verification_status': status, 'reviewer_note': reviewerNote.trim()},
  );

  Future<List<StoreCategoryOption>> storeCategories() async {
    final data = await _api.get('/store-categories');
    final raw = data['items'];
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map(
          (item) =>
              StoreCategoryOption.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((category) => category.publicId.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createMerchantStore({
    required Map<String, dynamic> values,
  }) async {
    final data = await _api.post('/merchant/store', body: values);
    final store = data['store'];
    return store is Map ? Map<String, dynamic>.from(store) : const <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> merchantStoreBanners() async => _mapItems(await _api.get('/merchant/store/banners'));
  Future<List<Map<String, dynamic>>> adminStoreHomeBanners() async => _mapItems(await _api.get('/admin/store-home-banners'));
  Future<void> saveStoreBanner({required bool admin, String? bannerId, required Map<String, dynamic> values, XFile? image}) async {
    final body = Map<String, dynamic>.from(values);
    if (image != null) body['media_public_id'] = await _uploadPublicMedia(image, admin ? 'admin-store-banner-image' : 'merchant-store-banner-image');
    final collection = admin ? '/admin/store-home-banners' : '/merchant/store/banners';
    if (bannerId == null || bannerId.isEmpty) { await _api.post(collection, body: body, idempotencyKey: _operationKey(admin ? 'admin-store-banner-create' : 'merchant-store-banner-create')); }
    else { await _api.patch('$collection/${Uri.encodeComponent(bannerId)}', body: body, idempotencyKey: _operationKey(admin ? 'admin-store-banner-update' : 'merchant-store-banner-update')); }
  }
  Future<void> deleteStoreBanner({required bool admin, required String bannerId}) => _api.delete('${admin ? '/admin/store-home-banners' : '/merchant/store/banners'}/${Uri.encodeComponent(bannerId)}', idempotencyKey: _operationKey(admin ? 'admin-store-banner-delete' : 'merchant-store-banner-delete'));

  Future<void> updateMerchantStore({
    required Map<String, dynamic> values,
    XFile? logo,
  }) async {
    final body = Map<String, dynamic>.from(values);
    if (logo != null) {
      final uploadData = await _api.postForm(
        '/media',
        body: FormData.fromMap({
          'visibility': 'public',
          'file': await MultipartFile.fromFile(logo.path, filename: logo.name),
        }),
        idempotencyKey: _operationKey('store-logo-upload'),
      );
      final mediaRaw = uploadData['media'];
      final media = mediaRaw is Map
          ? Map<String, dynamic>.from(mediaRaw)
          : const <String, dynamic>{};
      final mediaId = media['public_id'] as String?;
      if (mediaId == null || mediaId.isEmpty) {
        throw const FormatException(
          'لم يعد الخادم معرفاً صالحاً لشعار المتجر.',
        );
      }
      body['logo_media_id'] = mediaId;
    }
    await _api.patch('/merchant/store', body: body);
  }

  Future<CourierWorkspace> courierWorkspace() async {
    final profileData = await _api.get('/courier/profile');
    final profileRaw = profileData['profile'];
    final profile = profileRaw is Map
        ? Map<String, dynamic>.from(profileRaw)
        : const <String, dynamic>{};
    if (profile['verification_status'] != 'verified') {
      return CourierWorkspace(profile: profile, tasks: const []);
    }
    // This endpoint joins store-order and marketplace delivery tasks. Keeping
    // the source type allows later acceptance/transitions to use their own
    // permissioned contracts without losing either kind of work.
    final data = await _api.get('/courier/unified-tasks');
    final tasksRaw = data['items'];
    return CourierWorkspace(
      profile: profile,
      tasks: (tasksRaw is List ? tasksRaw : const [])
          .whereType<Map>()
          .map((item) {
            final raw = Map<String, dynamic>.from(item);
            Map<String, dynamic> snapshot(Object? value) {
              if (value is Map) return Map<String, dynamic>.from(value);
              if (value is String && value.isNotEmpty) {
                try {
                  final decoded = jsonDecode(value);
                  if (decoded is Map) return Map<String, dynamic>.from(decoded);
                } on FormatException {}
              }
              return const <String, dynamic>{};
            }
            final store = snapshot(raw['store_snapshot'] ?? raw['store']);
            final pickup = raw['source_type'] == 'marketplace_transaction'
                ? snapshot(raw['pickup_address_snapshot'])
                : store;
            return <String, dynamic>{
              ...raw,
              'public_id': raw['task_public_id'] ?? raw['public_id'],
              'order_number': raw['source_label'] ?? raw['order_number'],
              'store': store,
              'pickup_address': pickup,
              'delivery_address': snapshot(raw['delivery_address_snapshot'] ?? raw['delivery_address']),
            };
          })
          .toList(growable: false),
    );
  }

  Future<void> createProduct({
    required String name,
    required String description,
    required num price,
    required int stockQuantity,
    required String currencyCode,
    required bool publish,
    String fulfillmentMode = 'retail',
    int? preorderMinQuantity,
    int? preorderMaxQuantity,
    int? preorderLeadDays,
    bool isSpecialOffer = false,
    num? salePrice,
    DateTime? saleEndsAt,
    XFile? image,
  }) async {
    final data = await _api.post(
      '/merchant/products',
      body: {
        'name': name.trim(),
        'description': description.trim(),
        'price': price,
        'stock_quantity': stockQuantity,
        'currency_code': currencyCode,
        'publish': publish,
        'fulfillment_mode': fulfillmentMode,
        'preorder_min_quantity': preorderMinQuantity,
        'preorder_max_quantity': preorderMaxQuantity,
        'preorder_lead_days': preorderLeadDays,
        'is_special_offer': isSpecialOffer,
        'sale_price': salePrice,
        'sale_ends_at': saleEndsAt?.toUtc().toIso8601String(),
      },
      idempotencyKey: _operationKey('product-create'),
    );
    if (image == null) return;
    final productRaw = data['product'];
    final product = productRaw is Map
        ? Map<String, dynamic>.from(productRaw)
        : const <String, dynamic>{};
    final productId = product['public_id'] as String?;
    if (productId == null || productId.isEmpty) {
      throw const FormatException('لم يعد الخادم معرفاً صالحاً للمنتج الجديد.');
    }
    await _attachProductImage(productId, image);
  }

  Future<void> updateProduct({
    required String productId,
    required String name,
    required String description,
    required num price,
    required int stockQuantity,
    required String currencyCode,
    required String productStatus,
    String? sku,
    String fulfillmentMode = 'retail',
    int? preorderMinQuantity,
    int? preorderMaxQuantity,
    int? preorderLeadDays,
    bool isSpecialOffer = false,
    num? salePrice,
    DateTime? saleEndsAt,
    XFile? image,
  }) async {
    await _api.patch(
      '/merchant/products/${Uri.encodeComponent(productId)}',
      body: {
        'name': name.trim(),
        'description': description.trim(),
        'price': price,
        'stock_quantity': stockQuantity,
        'currency_code': currencyCode,
        'product_status': productStatus,
        'sku': sku?.trim() ?? '',
        'fulfillment_mode': fulfillmentMode,
        'preorder_min_quantity': preorderMinQuantity,
        'preorder_max_quantity': preorderMaxQuantity,
        'preorder_lead_days': preorderLeadDays,
        'is_special_offer': isSpecialOffer,
        'sale_price': salePrice,
        'sale_ends_at': saleEndsAt?.toUtc().toIso8601String(),
      },
      idempotencyKey: _operationKey('product-update'),
    );
    if (image != null) await _attachProductImage(productId, image);
  }

  Future<void> archiveProduct(String productId) => _api.delete(
    '/merchant/products/${Uri.encodeComponent(productId)}',
    idempotencyKey: _operationKey('product-archive'),
  );

  Future<void> _attachProductImage(String productId, XFile image) async {
    final mediaId = await _uploadPublicMedia(image, 'product-image-upload');
    await _api.post(
      '/merchant/products/${Uri.encodeComponent(productId)}/media',
      body: {'media_public_id': mediaId, 'is_primary': true},
      idempotencyKey: _operationKey('product-image-attach'),
    );
  }

  Future<String> _uploadPublicMedia(XFile image, String operation) async {
    final uploadData = await _api.postForm(
      '/media',
      body: FormData.fromMap({
        'visibility': 'public',
        'file': await MultipartFile.fromFile(image.path, filename: image.name),
      }),
      idempotencyKey: _operationKey(operation),
    );
    final mediaRaw = uploadData['media'];
    final media = mediaRaw is Map
        ? Map<String, dynamic>.from(mediaRaw)
        : const <String, dynamic>{};
    final mediaId = media['public_id'] as String?;
    if (mediaId == null || mediaId.isEmpty) {
      throw const FormatException(
        'لم يعد الخادم معرفاً صالحاً للصورة المختارة.',
      );
    }
    return mediaId;
  }

  Future<List<Map<String, dynamic>>> adminAuditLogs({String search = ''}) => _mapItemsAsync(
    _api.get('/admin/audit-logs', query: {'per_page': '200', if (search.trim().isNotEmpty) 'search': search.trim()}),
  );

  Future<List<Map<String, dynamic>>> adminNotificationLogs({String search = '', String category = '', String deliveryStatus = ''}) => _mapItemsAsync(
    _api.get('/admin/notification-logs', query: {
      'per_page': '200',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (category.isNotEmpty) 'category': category,
      if (deliveryStatus.isNotEmpty) 'delivery_status': deliveryStatus,
    }),
  );

  Future<List<Map<String, dynamic>>> adminNotificationCampaigns() async =>
      _mapItems(await _api.get('/admin/notification-campaigns'));

  Future<List<Map<String, dynamic>>> merchantNotificationCampaignProducts({String search = ''}) =>
      _mapItemsAsync(_api.get('/merchant/notification-campaign-products', query: {
        'per_page': '12',
        if (search.trim().isNotEmpty) 'search': search.trim(),
      }));

  Future<List<Map<String, dynamic>>> merchantNotificationCampaigns() async =>
      _mapItems(await _api.get('/merchant/notification-campaigns'));

  Future<Map<String, dynamic>> createMerchantNotificationCampaign(Map<String, dynamic> values) =>
      _api.post('/merchant/notification-campaigns', body: values, idempotencyKey: _operationKey('merchant-notification-campaign'));

  Future<List<Map<String, dynamic>>> adminMerchantNotificationCampaigns({String status = ''}) =>
      _mapItemsAsync(_api.get('/admin/merchant-notification-campaigns', query: {
        if (status.isNotEmpty) 'status': status,
      }));

  Future<Map<String, dynamic>> reviewMerchantNotificationCampaign(String campaignId, Map<String, dynamic> values) =>
      _api.post('/admin/merchant-notification-campaigns/${Uri.encodeComponent(campaignId)}/review', body: values);

  Future<List<Map<String, dynamic>>> adminNotificationCampaignTargets({
    required String type,
    required String search,
    String storeId = '',
  }) => _mapItemsAsync(_api.get('/admin/notification-campaign-targets', query: {
    'type': type,
    'search': search.trim(),
    'per_page': '12',
    if (storeId.trim().isNotEmpty) 'store_id': storeId.trim(),
  }));

  Future<Map<String, dynamic>> previewAdminNotificationCampaign(Map<String, dynamic> values) =>
      _api.post('/admin/notification-campaigns/preview', body: values);

  Future<Map<String, dynamic>> createAdminNotificationCampaign(Map<String, dynamic> values) =>
      _api.post('/admin/notification-campaigns', body: values, idempotencyKey: _operationKey('admin-notification-campaign'));

  Future<Map<String, dynamic>> adminFinancialSummary({String currencyCode = ''}) => _api.get(
    '/admin/finance/summary',
    query: {if (currencyCode.isNotEmpty) 'currency_code': currencyCode},
  );

  Future<List<Map<String, dynamic>>> adminFinancialWallets({
    String search = '', String currencyCode = '', String ownerType = '',
  }) => _mapItemsAsync(_api.get('/admin/finance/wallets', query: {
    'per_page': '100',
    if (search.trim().isNotEmpty) 'search': search.trim(),
    if (currencyCode.isNotEmpty) 'currency_code': currencyCode,
    if (ownerType.isNotEmpty) 'owner_type': ownerType,
  }));

  Future<Map<String, dynamic>> adminFinancialWalletDetail(String accountKey, String currencyCode) => _api.get(
    '/admin/finance/wallets/${Uri.encodeComponent(accountKey)}/${Uri.encodeComponent(currencyCode)}',
  );

  Future<List<Map<String, dynamic>>> adminFinancialEntries({
    String search = '', String currencyCode = '', String direction = '', String entryType = '',
  }) => _mapItemsAsync(_api.get('/admin/finance/entries', query: {
    'per_page': '150',
    if (search.trim().isNotEmpty) 'search': search.trim(),
    if (currencyCode.isNotEmpty) 'currency_code': currencyCode,
    if (direction.isNotEmpty) 'direction': direction,
    if (entryType.isNotEmpty) 'entry_type': entryType,
  }));

  Future<List<Map<String, dynamic>>> adminFinancialInvoices({String search = '', String currencyCode = ''}) => _mapItemsAsync(
    _api.get('/admin/finance/invoices', query: {
      'per_page': '100',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (currencyCode.isNotEmpty) 'currency_code': currencyCode,
    }),
  );

  Future<Map<String, dynamic>> wallet({
    required String role,
    required String currencyCode,
  }) async {
    final path = role == 'merchant' ? '/merchant/wallet' : '/courier/wallet';
    final data = await _api.get(path, query: {'currency_code': currencyCode});
    return Map<String, dynamic>.from(data['wallet'] as Map? ?? const {});
  }

  Future<void> requestWithdrawal({
    required String role,
    required String currencyCode,
    required String amount,
    required Map<String, dynamic> payoutDetails,
  }) async {
    final path = role == 'merchant' ? '/merchant/withdrawals' : '/courier/withdrawals';
    await _api.post(
      path,
      body: {
        'currency_code': currencyCode,
        'amount': amount,
        'payout_details': payoutDetails,
      },
      idempotencyKey: _operationKey('$role-withdrawal'),
    );
  }

  Future<void> setCourierAvailability(bool available) => _api.patch(
    '/courier/availability',
    body: {'available': available},
    idempotencyKey: _operationKey('availability'),
  );

  Future<void> acceptTask(String taskId, {String sourceType = 'store_order'}) => _api.post(
    sourceType == 'marketplace_transaction'
        ? '/courier/marketplace-tasks/${Uri.encodeComponent(taskId)}/accept'
        : '/courier/tasks/${Uri.encodeComponent(taskId)}/accept',
    idempotencyKey: _operationKey('task-accept'),
  );

  Future<void> transitionCourierTask({
    required String taskId,
    required String action,
    String sourceType = 'store_order',
    XFile? proof,
  }) async {
    String? proofMediaId;
    if (proof != null) {
      final uploadData = await _api.postForm(
        '/media',
        body: FormData.fromMap({
          'visibility': 'private',
          'file': await MultipartFile.fromFile(
            proof.path,
            filename: proof.name,
          ),
        }),
        idempotencyKey: _operationKey('delivery-proof-upload'),
      );
      final mediaRaw = uploadData['media'];
      final media = mediaRaw is Map
          ? Map<String, dynamic>.from(mediaRaw)
          : const <String, dynamic>{};
      proofMediaId = media['public_id'] as String?;
      if (proofMediaId == null || proofMediaId.isEmpty) {
        throw const FormatException(
          'لم يعد الخادم معرفاً صالحاً لصورة الإثبات.',
        );
      }
    }
    await _api.post(
      sourceType == 'marketplace_transaction'
          ? '/courier/marketplace-tasks/${Uri.encodeComponent(taskId)}/transition'
          : '/courier/tasks/${Uri.encodeComponent(taskId)}/transition',
      body: {'action': action, 'proof_media_id': ?proofMediaId},
      idempotencyKey: _operationKey('task-transition'),
    );
  }

  Future<List<Map<String, dynamic>>> _mapItemsAsync(Future<Map<String, dynamic>> data) async =>
      _mapItems(await data);

  List<Map<String, dynamic>> _mapItems(Map<String, dynamic> data) =>
      ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);

  String _operationKey(String operation) =>
      '$operation-${DateTime.now().microsecondsSinceEpoch}-${++_operationCounter}';
}
