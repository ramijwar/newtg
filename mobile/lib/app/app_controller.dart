import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../core/network/api_exception.dart';
import '../core/storage/local_database.dart';
import '../core/storage/offline_operation_sync.dart';
import '../core/storage/secure_session.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/catalog/data/catalog_repository.dart';
import '../features/catalog/domain/catalog_models.dart';
import '../features/commerce/data/commerce_repository.dart';
import '../features/commerce/domain/commerce_models.dart';
import '../features/notifications/data/firebase_push_service.dart';
import '../features/notifications/data/notification_repository.dart';
import '../features/workspace/data/workspace_repository.dart';

final class AppController extends ChangeNotifier {
  AppController({
    required this._authRepository,
    required this._catalogRepository,
    required this._commerceRepository,
    required this._notificationRepository,
    required this._pushService,
    required this._workspaceRepository,
    required this._offlineSync,
    required this._sessionStore,
  }) {
    _pushService.onForegroundNotification = () {
      unawaited(refreshNotificationBadge());
    };
    _pushService.onNotificationOpened = (target) {
      if (target.notificationId != null) {
        unawaited(markNotificationRead(target.notificationId!));
      }
      unawaited(refreshNotificationBadge());
      _notificationTargets.add(target);
    };
    _pushService.onPermissionStateChanged = (state) {
      pushPermissionState = state;
      notifyListeners();
    };
    _pushService.onRegistrationStateChanged = (state) {
      pushDeviceRegistrationState = state;
      if (state == PushDeviceRegistrationState.registered) {
        unawaited(refreshNotificationBadge());
      }
      notifyListeners();
    };
  }

  final AuthRepository _authRepository;
  final CatalogRepository _catalogRepository;
  final CommerceRepository _commerceRepository;
  final NotificationRepository _notificationRepository;
  final FirebasePushService _pushService;
  final WorkspaceRepository _workspaceRepository;
  final OfflineOperationSync _offlineSync;
  final SecureSessionStore _sessionStore;
  final StreamController<NotificationTarget> _notificationTargets =
      StreamController<NotificationTarget>.broadcast();
  Timer? _notificationPollingTimer;
  bool _isRefreshingNotificationBadge = false;

  /// Navigation instructions originating from a tapped FCM notification.
  Stream<NotificationTarget> get notificationTargets => _notificationTargets.stream;

  bool isBootstrapping = true;
  bool isRefreshing = false;
  bool isCartLoading = false;
  bool isCartMutating = false;
  UserSession? session;
  HomeFeed feed = const HomeFeed(stores: [], listings: []);
  List<ShoppingCart> carts = const [];
  List<StoreSummary> storeDirectory = const [];
  String storeDirectoryMode = '';
  bool isStoreDirectoryLoading = false;
  String? storeDirectoryError;
  int _storeDirectoryRevision = 0;
  String? homeError;
  int notificationRevision = 0;
  int unreadNotificationCount = 0;
  PushPermissionState pushPermissionState = PushPermissionState.needsRequest;
  PushDeviceRegistrationState pushDeviceRegistrationState = PushDeviceRegistrationState.notRegistered;

  bool get isCustomer => session?.roles.contains('customer') == true;
  int get cartItemCount =>
      carts.fold(0, (total, cart) => total + cart.itemCount);

  Future<void> bootstrap() async {
    session = await _sessionStore.read();
    isBootstrapping = false;
    notifyListeners();
    // Ask Android at every app launch until it is granted, even before login.
    // Token association is retried automatically after authentication succeeds.
    unawaited(_pushService.activate());
    if (session != null) {
      unawaited(_offlineSync.flush());
      unawaited(refreshNotificationBadge());
      _startNotificationPolling();
    }
    await Future.wait([refreshHome(silent: true), refreshCarts(silent: true)]);
  }

  /// Exposes the permission state for settings/status screens. Startup requests
  /// the Android permission automatically when it has not yet been granted.
  Future<PushPermissionState> refreshPushPermissionState() async {
    final state = await _pushService.refreshPermissionState();
    pushPermissionState = state;
    pushDeviceRegistrationState = _pushService.registrationState;
    notifyListeners();
    return state;
  }

  Future<PushPermissionState> requestPushPermission() async {
    final state = await _pushService.requestPermission();
    pushPermissionState = state;
    pushDeviceRegistrationState = _pushService.registrationState;
    notifyListeners();
    return state;
  }

  Future<void> refreshHome({bool silent = false}) async {
    if (!silent) {
      isRefreshing = true;
      notifyListeners();
    }
    homeError = null;
    try {
      feed = await _catalogRepository.loadHome();
    } on ApiException catch (error) {
      homeError = error.message;
    } catch (_) {
      homeError = 'تعذر تجهيز المحتوى الآن.';
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> loadStoreDirectory({
    String mode = '',
    bool force = false,
  }) async {
    final normalizedMode = mode == 'retail' || mode == 'preorder' ? mode : '';
    if (!force && !isStoreDirectoryLoading &&
        storeDirectoryMode == normalizedMode && storeDirectory.isNotEmpty) {
      return;
    }
    final revision = ++_storeDirectoryRevision;
    storeDirectoryMode = normalizedMode;
    isStoreDirectoryLoading = true;
    storeDirectoryError = null;
    notifyListeners();
    try {
      final stores = await _catalogRepository.loadStoreDirectory(mode: normalizedMode);
      if (revision != _storeDirectoryRevision) return;
      storeDirectory = stores;
    } on ApiException catch (error) {
      if (revision != _storeDirectoryRevision) return;
      storeDirectoryError = error.message;
    } catch (_) {
      if (revision != _storeDirectoryRevision) return;
      storeDirectoryError = 'تعذر تحميل دليل المتاجر الآن.';
    } finally {
      if (revision == _storeDirectoryRevision) {
        isStoreDirectoryLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshCarts({bool silent = false}) async {
    if (!isCustomer) {
      carts = const [];
      if (!silent) notifyListeners();
      return;
    }
    if (!silent) {
      isCartLoading = true;
      notifyListeners();
    }
    try {
      carts = await _commerceRepository.loadCarts();
    } on ApiException {
      // The cart is account data, not offline cache. Preserve last server state.
    } finally {
      isCartLoading = false;
      notifyListeners();
    }
  }

  Future<void> addProductToCart(String productId) async {
    _requireCustomer();
    await _cartMutation(() => _commerceRepository.addProduct(productId));
  }

  Future<void> changeCartQuantity({
    required String cartId,
    required String productId,
    required int quantity,
  }) async {
    _requireCustomer();
    if (quantity < 0) return;
    await _cartMutation(
      () => _commerceRepository.changeQuantity(
        cartId: cartId,
        productId: productId,
        quantity: quantity,
      ),
    );
  }

  Future<List<CustomerAddress>> loadAddresses() {
    _requireCustomer();
    return _commerceRepository.loadAddresses();
  }

  Future<CustomerAddress> saveAddress(CustomerAddress address) {
    _requireCustomer();
    return _commerceRepository.saveAddress(address);
  }

  Future<Map<String, dynamic>> reverseGeocodeAddress({
    required double latitude,
    required double longitude,
  }) {
    _requireCustomer();
    return _commerceRepository.reverseGeocode(
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<DeliveryQuote> deliveryQuote({
    required String cartId,
    required String deliveryAddressId,
  }) {
    _requireCustomer();
    return _commerceRepository.deliveryQuote(
      cartId: cartId,
      deliveryAddressId: deliveryAddressId,
    );
  }

  Future<Map<String, dynamic>> checkout({
    required String cartId,
    required String fulfillmentType,
    String? deliveryAddressId,
    required String paymentMethod,
    String? customerNote,
  }) async {
    _requireCustomer();
    isCartMutating = true;
    notifyListeners();
    try {
      final order = await _commerceRepository.checkout(
        cartId: cartId,
        fulfillmentType: fulfillmentType,
        deliveryAddressId: deliveryAddressId,
        paymentMethod: paymentMethod,
        customerNote: customerNote,
      );
      await refreshCarts(silent: true);
      return order;
    } finally {
      isCartMutating = false;
      notifyListeners();
    }
  }

  Future<List<CustomerOrder>> loadOrders() {
    _requireCustomer();
    return _commerceRepository.loadOrders();
  }

  Future<void> cancelOrder({required String orderId, required String reason}) {
    _requireCustomer();
    return _commerceRepository.cancelOrder(orderId: orderId, reason: reason);
  }

  Future<void> confirmOrderDelivery(String orderId) {
    _requireCustomer();
    return _commerceRepository.confirmOrderDelivery(orderId);
  }

  Future<void> submitManualPayment({
    required String orderId,
    String transferReference = '',
    String paymentNote = '',
    XFile? receipt,
  }) {
    _requireCustomer();
    return _commerceRepository.submitManualPayment(
      orderId: orderId,
      transferReference: transferReference,
      paymentNote: paymentNote,
      receipt: receipt,
    );
  }

  Future<List<Map<String, dynamic>>> loadMerchantPaymentQueue() =>
      _workspaceRepository.merchantPaymentQueue();

  Future<void> reviewMerchantPayment({
    required String orderId,
    required String decision,
    String note = '',
  }) => _workspaceRepository.reviewMerchantPayment(
    orderId: orderId,
    decision: decision,
    note: note,
  );

  Future<Uint8List> loadMerchantPaymentReceipt(String orderId) =>
      _workspaceRepository.merchantPaymentReceipt(orderId);

  Future<List<Map<String, dynamic>>> loadAdminManualPaymentLog() =>
      _workspaceRepository.adminManualPaymentLog();

  Future<CatalogPage<StoreSummary>> browseStoresPage({String search = '', String categoryId = '', String mode = '', String sort = 'popular', int page = 1}) =>
      _catalogRepository.browseStoresPage(search: search, categoryId: categoryId, mode: mode, sort: sort, page: page);

  Future<List<StoreSummary>> browseStores({
    String search = '',
    String categoryId = '',
    String mode = '',
    String sort = 'popular',
  }) => _catalogRepository.browseStores(
    search: search,
    categoryId: categoryId,
    mode: mode,
    sort: sort,
  );

  Future<List<Map<String, dynamic>>> loadPublicStoreCategories() =>
      _catalogRepository.loadPublicStoreCategories();

  Future<List<StoreProduct>> loadFeaturedProducts(String kind) =>
      _catalogRepository.loadFeaturedProducts(kind);

  Future<List<Map<String, dynamic>>> loadStoreReviews(String storeId) =>
      _catalogRepository.loadStoreReviews(storeId);

  Future<List<Map<String, dynamic>>> loadStoreReviewEligibility(String storeId) =>
      _catalogRepository.loadStoreReviewEligibility(storeId);

  Future<void> setStoreFollowing({
    required String storeId,
    required bool following,
  }) => _catalogRepository.setStoreFollowing(storeId: storeId, following: following);

  Future<void> createStoreReview({
    required String storeId,
    required String orderId,
    required int rating,
    String comment = '',
  }) => _catalogRepository.createStoreReview(
    storeId: storeId,
    orderId: orderId,
    rating: rating,
    comment: comment,
  );

  Future<CatalogPage<MarketplaceListing>> browseMarketplacePage({String search = '', String city = '', String categoryId = '', String sort = 'newest', int page = 1}) =>
      _catalogRepository.browseMarketplacePage(search: search, city: city, categoryId: categoryId, sort: sort, page: page);

  Future<List<MarketplaceListing>> browseMarketplace({
    String search = '',
    String city = '',
    String categoryId = '',
    String sort = 'newest',
  }) => _catalogRepository.browseMarketplace(
    search: search,
    city: city,
    categoryId: categoryId,
    sort: sort,
  );

  Future<List<Map<String, dynamic>>> loadMyMarketplaceListings() =>
      _catalogRepository.loadMyMarketplaceListings();

  Future<List<Map<String, dynamic>>> loadMarketplaceFavorites() =>
      _catalogRepository.loadMarketplaceFavorites();

  Future<bool> setMarketplaceFavorite({
    required String listingId,
    required bool enabled,
  }) => _catalogRepository.setMarketplaceFavorite(
    listingId: listingId,
    enabled: enabled,
  );

  Future<List<Map<String, dynamic>>> loadMarketplaceConversations() =>
      _catalogRepository.loadMarketplaceConversations();

  Future<Map<String, dynamic>> startMarketplaceConversation(String listingId) =>
      _catalogRepository.startMarketplaceConversation(listingId);

  Future<List<Map<String, dynamic>>> loadConversationMessages(
    String conversationId,
  ) async {
    final messages = await _catalogRepository.loadConversationMessages(conversationId);
    // The server acknowledges marketplace notification events when the thread
    // is opened. Refresh the global bell immediately rather than waiting for
    // the next polling interval.
    await refreshNotificationBadge();
    return messages;
  }

  Future<void> sendConversationMessage({
    required String conversationId,
    required String body,
  }) => _catalogRepository.sendConversationMessage(
    conversationId: conversationId,
    body: body,
  );

  Future<void> sendMarketplaceOffer({
    required String conversationId,
    required String amount,
  }) => _catalogRepository.sendMarketplaceOffer(
    conversationId: conversationId,
    amount: amount,
  );

  Future<void> decideMarketplaceOffer({
    required String offerId,
    required String decision,
  }) => _catalogRepository.decideMarketplaceOffer(
    offerId: offerId,
    decision: decision,
  );

  Future<List<Map<String, dynamic>>> loadMarketplaceTransactions() =>
      _catalogRepository.loadMarketplaceTransactions();

  Future<void> updateMarketplaceTransaction({
    required String transactionId,
    required String action,
  }) => _catalogRepository.updateMarketplaceTransaction(
    transactionId: transactionId,
    action: action,
  );

  Future<List<Map<String, dynamic>>> loadMarketplacePromotionPlans() =>
      _catalogRepository.loadMarketplacePromotionPlans();

  Future<Map<String, dynamic>> requestMarketplacePromotion({
    required String listingId,
    required String planCode,
  }) => _catalogRepository.requestMarketplacePromotion(
    listingId: listingId,
    planCode: planCode,
  );

  Future<void> submitMarketplacePromotionPayment({
    required String promotionId,
    required String transferReference,
    required XFile receipt,
  }) => _catalogRepository.submitMarketplacePromotionPayment(
    promotionId: promotionId,
    transferReference: transferReference,
    receipt: receipt,
  );

  Future<void> setMarketplaceUserBlock({
    required String userId,
    required bool blocked,
  }) => _catalogRepository.setMarketplaceUserBlock(
    userId: userId,
    blocked: blocked,
  );

  Future<void> reportMarketplaceListing({
    required String listingId,
    required String reasonCode,
    String details = '',
  }) => _catalogRepository.reportMarketplaceListing(
    listingId: listingId,
    reasonCode: reasonCode,
    details: details,
  );

  Future<void> confirmMarketplaceDelivery(String taskId) =>
      _catalogRepository.confirmMarketplaceDelivery(taskId);

  Future<void> requestMarketplaceDelivery({
    required String transactionId,
    required Map<String, dynamic> pickupAddress,
    required Map<String, dynamic> deliveryAddress,
  }) => _catalogRepository.requestMarketplaceDelivery(
    transactionId: transactionId,
    pickupAddress: pickupAddress,
    deliveryAddress: deliveryAddress,
  );

  Future<void> openMarketplaceDispute({
    required String transactionId,
    required String reasonCode,
    required String details,
  }) => _catalogRepository.openMarketplaceDispute(
    transactionId: transactionId,
    reasonCode: reasonCode,
    details: details,
  );

  Future<List<Map<String, dynamic>>> loadMySupportTickets() =>
      _catalogRepository.loadMySupportTickets();

  Future<void> createSupportTicket({
    required String subject,
    required String body,
  }) => _catalogRepository.createSupportTicket(subject: subject, body: body);

  Future<Map<String, dynamic>> loadSupportTicket(String ticketId) =>
      _catalogRepository.loadSupportTicket(ticketId);

  Future<void> replySupportTicket({
    required String ticketId,
    required String body,
  }) => _catalogRepository.replySupportTicket(ticketId: ticketId, body: body);

  Future<List<Map<String, dynamic>>> loadMarketplaceCategories() =>
      _catalogRepository.loadMarketplaceCategories();

  Future<List<Map<String, dynamic>>> loadMarketplaceCountries() =>
      _catalogRepository.loadMarketplaceCountries();

  Future<List<Map<String, dynamic>>> loadMarketplaceLocationOptions() =>
      _catalogRepository.loadMarketplaceLocationOptions();

  Future<List<Map<String, dynamic>>> loadMarketplaceCities(String countryId) =>
      _catalogRepository.loadMarketplaceCities(countryId);

  Future<List<Map<String, dynamic>>> loadMarketplaceAttributes(String categoryId) =>
      _catalogRepository.loadMarketplaceAttributes(categoryId);

  Future<void> updateMarketplaceListing({
    required String listingId,
    required String title,
    required String description,
    String? priceAmount,
    bool submitForReview = false,
  }) => _catalogRepository.updateMarketplaceListing(
    listingId: listingId,
    title: title,
    description: description,
    priceAmount: priceAmount,
    submitForReview: submitForReview,
  );

  Future<void> replaceMarketplaceListingImage({
    required String listingId,
    required XFile image,
  }) => _catalogRepository.replaceMarketplaceListingImage(
    listingId: listingId,
    image: image,
  );

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
  }) => _catalogRepository.createMarketplaceListing(
    title: title,
    description: description,
    categoryId: categoryId,
    listingType: listingType,
    currencyCode: currencyCode,
    countryId: countryId,
    cityId: cityId,
    districtId: districtId,
    priceAmount: priceAmount,
    attributes: attributes,
    image: image,
  );

  Future<StoreDetails> loadStoreDetails(String publicId) =>
      _catalogRepository.loadStore(publicId);

  Future<ListingDetails> loadListingDetails(String publicId) =>
      _catalogRepository.loadListing(publicId);

  Future<ProductDetails> loadProductDetails(String publicId) =>
      _catalogRepository.loadProduct(publicId);

  Future<List<ContentComment>> loadContentComments({
    required String kind,
    required String publicId,
  }) => _catalogRepository.loadComments(kind: kind, publicId: publicId);

  Future<void> addContentComment({
    required String kind,
    required String publicId,
    required String body,
  }) =>
      _catalogRepository.addComment(kind: kind, publicId: publicId, body: body);

  Future<void> deleteContentComment(String publicId) =>
      _catalogRepository.deleteComment(publicId);

  Future<void> login({required String phone, required String password}) async {
    session = await _authRepository.login(phone: phone, password: password);
    notifyListeners();
    unawaited(_pushService.activate());
    unawaited(refreshNotificationBadge());
    _startNotificationPolling();
    await refreshCarts(silent: true);
  }

  Future<void> register({
    required String fullName,
    required String username,
    required String phone,
    required String password,
    String role = 'customer',
  }) async {
    session = await _authRepository.register(
      fullName: fullName,
      username: username,
      phone: phone,
      password: password,
      role: role,
    );
    notifyListeners();
    unawaited(_pushService.activate());
    unawaited(refreshNotificationBadge());
    _startNotificationPolling();
    await refreshCarts(silent: true);
  }

  Future<Map<String, dynamic>> checkAvailability({
    required String field,
    required String value,
  }) => _authRepository.availability(field: field, value: value);

  Future<void> updateProfileAvatar(XFile image) async {
    session = await _authRepository.updateAvatar(image);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> loadMyVerificationRequests() =>
      _workspaceRepository.myVerificationRequests();

  Future<void> submitVerificationRequest({
    required String roleCode,
    required XFile identity,
    required XFile selfie,
  }) => _workspaceRepository.submitVerificationRequest(
    roleCode: roleCode,
    identity: identity,
    selfie: selfie,
  );

  Future<NotificationFeed> loadNotifications() {
    if (session == null) {
      throw const ApiException(
        message: 'سجّل الدخول لعرض الإشعارات.',
        code: 'authentication_required',
      );
    }
    return _notificationRepository.load();
  }

  /// Gets the authoritative unread count used by the global bell badge.
  /// It works even without Firebase, including after app resume.
  Future<void> refreshNotificationBadge() async {
    if (session == null || _isRefreshingNotificationBadge) return;
    _isRefreshingNotificationBadge = true;
    try {
      final feed = await _notificationRepository.load();
      if (unreadNotificationCount != feed.unreadCount) {
        unreadNotificationCount = feed.unreadCount;
        notificationRevision++;
        notifyListeners();
      }
    } catch (_) {
      // Preserve the last known count. Badge refresh is intentionally silent.
    } finally {
      _isRefreshingNotificationBadge = false;
    }
  }

  void _startNotificationPolling() {
    _notificationPollingTimer?.cancel();
    _notificationPollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(refreshNotificationBadge());
    });
  }

  void _stopNotificationPolling() {
    _notificationPollingTimer?.cancel();
    _notificationPollingTimer = null;
  }

  Future<List<NotificationPreference>> loadNotificationPreferences() =>
      _notificationRepository.preferences();

  Future<void> saveNotificationPreferences(
    List<NotificationPreference> preferences,
  ) => _notificationRepository.updatePreferences(preferences);

  Future<void> markNotificationRead(String publicId) async {
    await _notificationRepository.markRead(publicId);
    await refreshNotificationBadge();
  }

  Future<void> markAllNotificationsRead() async {
    await _notificationRepository.markAllRead();
    if (unreadNotificationCount != 0) {
      unreadNotificationCount = 0;
      notificationRevision++;
      notifyListeners();
    }
  }

  Future<MerchantWorkspace> loadMerchantWorkspace() =>
      _workspaceRepository.merchantWorkspace();

  Future<CourierWorkspace> loadCourierWorkspace() =>
      _workspaceRepository.courierWorkspace();

  Future<List<StoreCategoryOption>> loadStoreCategories() =>
      _workspaceRepository.storeCategories();

  Future<AdminWorkspace> loadAdminWorkspace() =>
      _workspaceRepository.adminWorkspace();

  Future<Map<String, dynamic>> loadAdminModerationSettings() =>
      _workspaceRepository.adminModerationSettings();

  Future<void> updateAdminModerationSettings({
    required bool autoApproveListings,
    required bool requireListingImage,
  }) => _workspaceRepository.updateAdminModerationSettings(
    autoApproveListings: autoApproveListings,
    requireListingImage: requireListingImage,
  );

  Future<List<Map<String, dynamic>>> loadAdminFeeRules() =>
      _workspaceRepository.adminFeeRules();

  Future<void> updateAdminFeeRule(Map<String, dynamic> input) =>
      _workspaceRepository.updateAdminFeeRule(input);

  Future<Map<String, dynamic>> loadAdminNotificationSettings() =>
      _workspaceRepository.adminNotificationSettings();

  Future<void> updateAdminNotificationSettings({
    required bool inAppEnabled,
    required bool pushEnabled,
  }) => _workspaceRepository.updateAdminNotificationSettings(
    inAppEnabled: inAppEnabled,
    pushEnabled: pushEnabled,
  );

  Future<List<Map<String, dynamic>>> loadAdminPromotionPlans() =>
      _workspaceRepository.adminPromotionPlans();

  Future<void> saveAdminPromotionPlan({
    String? code,
    String? currencyCode,
    required Map<String, dynamic> body,
  }) => _workspaceRepository.saveAdminPromotionPlan(
    code: code,
    currencyCode: currencyCode,
    body: body,
  );

  Future<List<Map<String, dynamic>>> loadAdminCatalogCategories(String type) =>
      _workspaceRepository.adminCatalogCategories(type);

  Future<void> saveAdminCatalogCategory({
    required String type,
    String? publicId,
    required Map<String, dynamic> body,
  }) => _workspaceRepository.saveAdminCatalogCategory(
    type: type,
    publicId: publicId,
    body: body,
  );

  Future<String> uploadAdminPublicMedia(XFile image) =>
      _workspaceRepository.uploadAdminPublicMedia(image);

  Future<List<Map<String, dynamic>>> loadAdminMarketplaceCategories() =>
      _workspaceRepository.adminMarketplaceCategories();

  Future<List<Map<String, dynamic>>> loadAdminMarketplaceAttributes(
    String categoryId,
  ) => _workspaceRepository.adminMarketplaceAttributes(categoryId);

  Future<List<Map<String, dynamic>>> loadAdminMarketplaceCountries() =>
      _workspaceRepository.adminMarketplaceCountries();

  Future<List<Map<String, dynamic>>> loadAdminMarketplaceCities(
    String countryId,
  ) => _workspaceRepository.adminMarketplaceCities(countryId);

  Future<List<Map<String, dynamic>>> loadAdminMarketplaceDistricts(
    String cityId,
  ) => _workspaceRepository.adminMarketplaceDistricts(cityId);

  Future<void> createAdminMarketplaceAttributeWithOptions({
    required Map<String, dynamic> body,
    required List<String> options,
  }) => _workspaceRepository.createAdminMarketplaceAttributeWithOptions(
    body: body,
    options: options,
  );

  Future<void> saveAdminMarketplaceEntity({
    required String type,
    String? publicId,
    required Map<String, dynamic> body,
  }) => _workspaceRepository.saveAdminMarketplaceEntity(
    type: type,
    publicId: publicId,
    body: body,
  );

  Future<void> deleteAdminMarketplaceLocation({
    required String type,
    required String publicId,
  }) => _workspaceRepository.deleteAdminMarketplaceLocation(
    type: type,
    publicId: publicId,
  );

  Future<AdminDecisionQueues> loadAdminDecisionQueues() =>
      _workspaceRepository.adminDecisionQueues();

  Future<void> reviewAdminPayment({
    required String orderId,
    required String decision,
    String note = '',
  }) => _workspaceRepository.reviewAdminPayment(
    orderId: orderId,
    decision: decision,
    note: note,
  );

  Future<void> cancelAdminOrder({
    required String orderId,
    required String reason,
  }) => _workspaceRepository.cancelAdminOrder(orderId: orderId, reason: reason);

  Future<void> decideAdminWithdrawal({
    required String withdrawalId,
    required String decision,
    String note = '',
  }) => _workspaceRepository.decideAdminWithdrawal(
    withdrawalId: withdrawalId,
    decision: decision,
    note: note,
  );

  Future<void> updateAdminReport({
    required String reportId,
    required String status,
  }) => _workspaceRepository.updateAdminReport(
    reportId: reportId,
    status: status,
  );

  Future<void> decideAdminDispute({
    required String disputeId,
    required String decision,
    required String note,
  }) => _workspaceRepository.decideAdminDispute(
    disputeId: disputeId,
    decision: decision,
    note: note,
  );

  Future<void> reviewAdminPromotion({
    required String promotionId,
    required String decision,
  }) => _workspaceRepository.reviewAdminPromotion(
    promotionId: promotionId,
    decision: decision,
  );

  Future<void> replyAdminSupportTicket({
    required String ticketId,
    required String body,
  }) => _workspaceRepository.replyAdminSupportTicket(
    ticketId: ticketId,
    body: body,
  );

  Future<void> updateAdminSupportTicket({
    required String ticketId,
    required String status,
  }) => _workspaceRepository.updateAdminSupportTicket(
    ticketId: ticketId,
    status: status,
  );

  Future<Uint8List> loadAdminPaymentReceipt(String orderId) =>
      _workspaceRepository.adminPaymentReceipt(orderId);

  Future<Uint8List> loadAdminPromotionReceipt(String promotionId) =>
      _workspaceRepository.adminPromotionReceipt(promotionId);

  Future<Uint8List> loadAdminVerificationMedia(
    String verificationId,
    String type,
  ) => _workspaceRepository.adminVerificationMedia(verificationId, type);

  Future<List<Map<String, dynamic>>> loadAdminUsers({
    String search = '',
    String role = '',
    String status = '',
  }) => _workspaceRepository.adminUsers(
    search: search,
    role: role,
    status: status,
  );

  Future<Map<String, dynamic>> createAdminUser(Map<String, dynamic> input) =>
      _workspaceRepository.createAdminUser(input);

  Future<Map<String, dynamic>> updateAdminUser(
    String userId,
    Map<String, dynamic> input,
  ) => _workspaceRepository.updateAdminUser(userId, input);

  Future<void> deleteAdminUser(String userId) =>
      _workspaceRepository.deleteAdminUser(userId);

  Future<List<Map<String, dynamic>>> loadAdminStores() =>
      _workspaceRepository.adminStores();

  Future<Map<String, dynamic>> loadAdminStoreDetail(String storeId) => _workspaceRepository.adminStoreDetail(storeId);

  Future<Map<String, dynamic>> loadAdminProductDetail(String productId) =>
      _workspaceRepository.adminProductDetail(productId);

  Future<List<Map<String, dynamic>>> loadAdminProducts({
    String search = '',
    String status = '',
  }) => _workspaceRepository.adminProducts(search: search, status: status);

  Future<Map<String, dynamic>> loadAdminOrderDetail(String orderId) =>
      _workspaceRepository.adminOrderDetail(orderId);

  Future<List<Map<String, dynamic>>> loadAdminOrders({
    String search = '',
    String orderStatus = '',
    String paymentStatus = '',
  }) => _workspaceRepository.adminOrders(
    search: search,
    orderStatus: orderStatus,
    paymentStatus: paymentStatus,
  );

  Future<List<Map<String, dynamic>>> loadAdminCouriers({
    String search = '',
    String verificationStatus = '',
    String workStatus = '',
  }) => _workspaceRepository.adminCouriers(
    search: search,
    verificationStatus: verificationStatus,
    workStatus: workStatus,
  );

  Future<Map<String, dynamic>> loadAdminCourierDetail(String courierId) =>
      _workspaceRepository.adminCourierDetail(courierId);

  Future<void> updateAdminCourierVerification({
    required String courierId,
    required String status,
  }) => _workspaceRepository.updateAdminCourierVerification(
    courierId: courierId,
    status: status,
  );

  Future<void> updateAdminCourierWorkStatus({
    required String courierId,
    required String status,
  }) => _workspaceRepository.updateAdminCourierWorkStatus(
    courierId: courierId,
    status: status,
  );

  Future<List<Map<String, dynamic>>> loadAdminMarketplaceTransactions({
    String search = '',
    String status = '',
  }) => _workspaceRepository.adminMarketplaceTransactions(
    search: search,
    status: status,
  );

  Future<Map<String, dynamic>> loadAdminMarketplaceTransactionDetail(
    String transactionId,
  ) => _workspaceRepository.adminMarketplaceTransactionDetail(transactionId);

  Future<List<Map<String, dynamic>>> loadAdminDeliveryTasks({
    String search = '',
    String status = '',
    String sourceType = '',
    String courierId = '',
  }) => _workspaceRepository.adminDeliveryTasks(
    search: search,
    status: status,
    sourceType: sourceType,
    courierId: courierId,
  );

  Future<Map<String, dynamic>> loadAdminDeliveryTaskDetail(String taskId) =>
      _workspaceRepository.adminDeliveryTaskDetail(taskId);

  Future<Uint8List> loadAdminDeliveryTaskProof({
    required String taskId,
    required String proofType,
  }) => _workspaceRepository.adminDeliveryTaskProof(
    taskId: taskId,
    proofType: proofType,
  );

  Future<void> updateAdminProductStatus({
    required String productId,
    required String status,
  }) => _workspaceRepository.updateAdminProductStatus(
    productId: productId,
    status: status,
  );

  Future<void> adminDeleteProduct(String productId) =>
      _workspaceRepository.adminDeleteProduct(productId);

  Future<void> adminDeleteListing(String listingId) =>
      _workspaceRepository.adminDeleteListing(listingId);

  Future<void> updateStoreReview(String storeId, String status) =>
      _workspaceRepository.updateStoreReview(storeId, status);

  Future<void> updateAdminStoreVerification({
    required String storeId,
    required bool isVerified,
  }) => _workspaceRepository.updateAdminStoreVerification(
    storeId: storeId,
    isVerified: isVerified,
  );

  Future<void> adminDeleteStore(String storeId) =>
      _workspaceRepository.adminDeleteStore(storeId);

  Future<void> setAdminStoreSuspended({
    required String storeId,
    required bool suspended,
  }) => _workspaceRepository.setAdminStoreSuspended(
    storeId: storeId,
    suspended: suspended,
  );

  Future<void> updateListingReview(String listingId, String status) =>
      _workspaceRepository.updateListingReview(listingId, status);

  Future<void> decideVerification({
    required String verificationId,
    required String status,
    String reviewerNote = '',
  }) => _workspaceRepository.decideVerification(
    verificationId: verificationId,
    status: status,
    reviewerNote: reviewerNote,
  );

  Future<Map<String, dynamic>> createMerchantStore({
    required Map<String, dynamic> values,
  }) => _workspaceRepository.createMerchantStore(values: values);

  Future<void> updateMerchantStore({
    required Map<String, dynamic> values,
    XFile? logo,
  }) => _workspaceRepository.updateMerchantStore(values: values, logo: logo);

  Future<List<Map<String, dynamic>>> loadStoreBanners({required bool admin}) => admin ? _workspaceRepository.adminStoreHomeBanners() : _workspaceRepository.merchantStoreBanners();
  Future<void> saveStoreBanner({required bool admin, String? bannerId, required Map<String, dynamic> values, XFile? image}) => _workspaceRepository.saveStoreBanner(admin: admin, bannerId: bannerId, values: values, image: image);
  Future<void> deleteStoreBanner({required bool admin, required String bannerId}) => _workspaceRepository.deleteStoreBanner(admin: admin, bannerId: bannerId);


  Future<void> createMerchantProduct({
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
  }) => _workspaceRepository.createProduct(
    name: name,
    description: description,
    price: price,
    stockQuantity: stockQuantity,
    currencyCode: currencyCode,
    publish: publish,
    fulfillmentMode: fulfillmentMode,
    preorderMinQuantity: preorderMinQuantity,
    preorderMaxQuantity: preorderMaxQuantity,
    preorderLeadDays: preorderLeadDays,
    isSpecialOffer: isSpecialOffer,
    salePrice: salePrice,
    saleEndsAt: saleEndsAt,
    image: image,
  );

  Future<void> updateMerchantProduct({
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
  }) => _workspaceRepository.updateProduct(
    productId: productId,
    name: name,
    description: description,
    price: price,
    stockQuantity: stockQuantity,
    currencyCode: currencyCode,
    productStatus: productStatus,
    sku: sku,
    fulfillmentMode: fulfillmentMode,
    preorderMinQuantity: preorderMinQuantity,
    preorderMaxQuantity: preorderMaxQuantity,
    preorderLeadDays: preorderLeadDays,
    isSpecialOffer: isSpecialOffer,
    salePrice: salePrice,
    saleEndsAt: saleEndsAt,
    image: image,
  );

  Future<void> archiveMerchantProduct(String productId) =>
      _workspaceRepository.archiveProduct(productId);

  Future<List<Map<String, dynamic>>> loadAdminAuditLogs({String search = ''}) => _workspaceRepository.adminAuditLogs(search: search);
  Future<List<Map<String, dynamic>>> loadAdminNotificationLogs({String search = '', String category = '', String deliveryStatus = ''}) =>
      _workspaceRepository.adminNotificationLogs(search: search, category: category, deliveryStatus: deliveryStatus);

  Future<Map<String, dynamic>> loadAdminOperationalHealth() =>
      _workspaceRepository.adminOperationalHealth();

  Future<List<Map<String, dynamic>>> loadAdminNotificationCampaigns() =>
      _workspaceRepository.adminNotificationCampaigns();
  Future<List<Map<String, dynamic>>> searchMerchantNotificationCampaignProducts({String search = ''}) =>
      _workspaceRepository.merchantNotificationCampaignProducts(search: search);
  Future<List<Map<String, dynamic>>> loadMerchantNotificationCampaigns() =>
      _workspaceRepository.merchantNotificationCampaigns();
  Future<Map<String, dynamic>> createMerchantNotificationCampaign(Map<String, dynamic> values) =>
      _workspaceRepository.createMerchantNotificationCampaign(values);
  Future<List<Map<String, dynamic>>> loadAdminMerchantNotificationCampaigns({String status = ''}) =>
      _workspaceRepository.adminMerchantNotificationCampaigns(status: status);
  Future<Map<String, dynamic>> reviewMerchantNotificationCampaign(String campaignId, Map<String, dynamic> values) =>
      _workspaceRepository.reviewMerchantNotificationCampaign(campaignId, values);
  Future<List<Map<String, dynamic>>> searchAdminNotificationCampaignTargets({
    required String type,
    required String search,
    String storeId = '',
  }) => _workspaceRepository.adminNotificationCampaignTargets(type: type, search: search, storeId: storeId);
  Future<Map<String, dynamic>> previewAdminNotificationCampaign(Map<String, dynamic> values) =>
      _workspaceRepository.previewAdminNotificationCampaign(values);
  Future<Map<String, dynamic>> createAdminNotificationCampaign(Map<String, dynamic> values) =>
      _workspaceRepository.createAdminNotificationCampaign(values);
  Future<List<Map<String, dynamic>>> searchAdminUsers({String search = '', String role = ''}) =>
      _workspaceRepository.adminUsers(search: search, role: role, status: 'active');

  Future<Map<String, dynamic>> loadAdminFinancialSummary({String currencyCode = ''}) =>
      _workspaceRepository.adminFinancialSummary(currencyCode: currencyCode);
  Future<List<Map<String, dynamic>>> loadAdminFinancialWallets({String search = '', String currencyCode = '', String ownerType = ''}) =>
      _workspaceRepository.adminFinancialWallets(search: search, currencyCode: currencyCode, ownerType: ownerType);
  Future<Map<String, dynamic>> loadAdminFinancialWalletDetail(String accountKey, String currencyCode) =>
      _workspaceRepository.adminFinancialWalletDetail(accountKey, currencyCode);
  Future<List<Map<String, dynamic>>> loadAdminFinancialEntries({String search = '', String currencyCode = '', String direction = '', String entryType = ''}) =>
      _workspaceRepository.adminFinancialEntries(search: search, currencyCode: currencyCode, direction: direction, entryType: entryType);
  Future<List<Map<String, dynamic>>> loadAdminFinancialInvoices({String search = '', String currencyCode = ''}) =>
      _workspaceRepository.adminFinancialInvoices(search: search, currencyCode: currencyCode);

  Future<Map<String, dynamic>> loadWallet({
    required String role,
    required String currencyCode,
  }) => _workspaceRepository.wallet(role: role, currencyCode: currencyCode);

  Future<void> requestWalletWithdrawal({
    required String role,
    required String currencyCode,
    required String amount,
    required Map<String, dynamic> payoutDetails,
  }) => _workspaceRepository.requestWithdrawal(
    role: role,
    currencyCode: currencyCode,
    amount: amount,
    payoutDetails: payoutDetails,
  );

  Future<void> setCourierAvailability(bool available) =>
      _workspaceRepository.setCourierAvailability(available);

  Future<void> acceptCourierTask(String taskId, {String sourceType = 'store_order'}) =>
      _workspaceRepository.acceptTask(taskId, sourceType: sourceType);

  Future<void> transitionCourierTask({
    required String taskId,
    required String action,
    String sourceType = 'store_order',
    XFile? proof,
  }) => _workspaceRepository.transitionCourierTask(
    taskId: taskId,
    action: action,
    sourceType: sourceType,
    proof: proof,
  );

  Future<void> logout() async {
    _stopNotificationPolling();
    await _pushService.deactivate();
    try {
      await _authRepository.logout();
    } finally {
      // Account-bound public cache and deferred non-financial work must never
      // cross a logout/login boundary, even if the remote logout call fails.
      await LocalDatabase.instance.clearLocalData();
    }
    session = null;
    carts = const [];
    unreadNotificationCount = 0;
    notificationRevision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopNotificationPolling();
    _notificationTargets.close();
    super.dispose();
  }

  Future<void> _cartMutation(Future<void> Function() mutation) async {
    isCartMutating = true;
    notifyListeners();
    try {
      await mutation();
      await refreshCarts(silent: true);
    } finally {
      isCartMutating = false;
      notifyListeners();
    }
  }

  void _requireCustomer() {
    if (!isCustomer) {
      throw const ApiException(
        message: 'هذه العملية متاحة لحساب العميل فقط.',
        code: 'customer_role_required',
      );
    }
  }
}
