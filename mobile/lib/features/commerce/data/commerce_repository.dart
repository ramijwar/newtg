import 'dart:math';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../domain/commerce_models.dart';

/// Customer actions always reach the API; financial checkout is deliberately
/// never queued locally. The backend validates stock, totals and idempotency.
final class CommerceRepository {
  CommerceRepository(this._api);
  final ApiClient _api;

  Future<List<ShoppingCart>> loadCarts() async {
    final data = await _api.get('/customer/carts');
    final items = data['items'];
    return (items is List ? items : const [])
        .whereType<Map>()
        .map((item) => ShoppingCart.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> addProduct(String productId) async {
    await _api.post(
      '/customer/carts/items',
      body: {'product_id': productId, 'quantity': 1},
      idempotencyKey: _idempotencyKey(),
    );
  }

  Future<void> changeQuantity({
    required String cartId,
    required String productId,
    required int quantity,
  }) async {
    await _api.patch(
      '/customer/carts/${Uri.encodeComponent(cartId)}/items/${Uri.encodeComponent(productId)}',
      body: {'quantity': quantity},
      idempotencyKey: _idempotencyKey(),
    );
  }

  Future<void> removeItem({
    required String cartId,
    required String productId,
  }) => _api.delete(
    '/customer/carts/${Uri.encodeComponent(cartId)}/items/${Uri.encodeComponent(productId)}',
    idempotencyKey: _idempotencyKey(),
  );

  Future<List<CustomerAddress>> loadAddresses() async {
    final data = await _api.get('/customer/addresses');
    final items = data['items'];
    return (items is List ? items : const [])
        .whereType<Map>()
        .map(
          (item) => CustomerAddress.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final data = await _api.get(
      '/customer/addresses/reverse-geocode',
      query: {'latitude': latitude, 'longitude': longitude},
    );
    final raw = data['address'];
    return raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
  }

  Future<CustomerAddress> saveAddress(CustomerAddress address) async {
    final isNew = address.publicId.isEmpty;
    final data = isNew
        ? await _api.post(
            '/customer/addresses',
            body: address.toInput(),
            idempotencyKey: _idempotencyKey(),
          )
        : await _api.patch(
            '/customer/addresses/${Uri.encodeComponent(address.publicId)}',
            body: address.toInput(),
            idempotencyKey: _idempotencyKey(),
          );
    final raw = data['address'];
    return CustomerAddress.fromJson(
      raw is Map ? Map<String, dynamic>.from(raw) : const {},
    );
  }

  Future<DeliveryQuote> deliveryQuote({
    required String cartId,
    required String deliveryAddressId,
  }) async {
    final data = await _api.post(
      '/customer/carts/${Uri.encodeComponent(cartId)}/delivery-quote',
      body: {'delivery_address_id': deliveryAddressId},
    );
    final raw = data['quote'];
    return DeliveryQuote.fromJson(raw is Map ? Map<String, dynamic>.from(raw) : const {});
  }

  Future<Map<String, dynamic>> checkout({
    required String cartId,
    required String fulfillmentType,
    String? deliveryAddressId,
    required String paymentMethod,
    String? customerNote,
  }) => _api.post(
    '/customer/carts/${Uri.encodeComponent(cartId)}/checkout',
    body: {
      'fulfillment_type': fulfillmentType,
      'payment_method': paymentMethod,
      if (deliveryAddressId != null && deliveryAddressId.isNotEmpty)
        'delivery_address_id': deliveryAddressId,
      if (customerNote != null && customerNote.trim().isNotEmpty)
        'customer_note': customerNote.trim(),
    },
    idempotencyKey: _idempotencyKey(),
  );

  Future<List<CustomerOrder>> loadOrders() async {
    final data = await _api.get(
      '/customer/orders',
      query: const {'per_page': 30},
    );
    final items = data['items'];
    return (items is List ? items : const [])
        .whereType<Map>()
        .map((item) => CustomerOrder.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> cancelOrder({
    required String orderId,
    required String reason,
  }) async {
    await _api.post(
      '/customer/orders/${Uri.encodeComponent(orderId)}/cancel',
      body: {'reason': reason.trim()},
      idempotencyKey: _idempotencyKey(),
    );
  }

  Future<void> confirmOrderDelivery(String orderId) => _api.post(
    '/customer/orders/${Uri.encodeComponent(orderId)}/confirm-delivery',
    body: const {},
    idempotencyKey: _idempotencyKey(),
  );

  Future<void> submitManualPayment({
    required String orderId,
    String transferReference = '',
    String paymentNote = '',
    XFile? receipt,
  }) async {
    String? mediaId;
    if (receipt != null) {
      final upload = FormData.fromMap({
        'visibility': 'private',
        'file': await MultipartFile.fromFile(receipt.path, filename: receipt.name),
      });
      final uploadData = await _api.postForm('/media', body: upload, idempotencyKey: _idempotencyKey());
      final media = uploadData['media'] is Map
          ? Map<String, dynamic>.from(uploadData['media'] as Map)
          : const <String, dynamic>{};
      mediaId = media['public_id'] as String?;
      if (mediaId == null || mediaId.isEmpty) {
        throw const FormatException('لم يعد الخادم معرفاً صالحاً لصورة الإيصال.');
      }
    }
    if (paymentNote.trim().length < 2 && transferReference.trim().length < 2 && mediaId == null) {
      throw const FormatException('اكتب إشعار الدفع أو أرفق صورة الإيصال.');
    }
    await _api.post(
      '/customer/orders/${Uri.encodeComponent(orderId)}/payment',
      body: {
        if (transferReference.trim().isNotEmpty) 'transfer_reference': transferReference.trim(),
        if (paymentNote.trim().isNotEmpty) 'payment_note': paymentNote.trim(),
        if (mediaId != null) 'receipt_media_id': mediaId,
      },
      idempotencyKey: _idempotencyKey(),
    );
  }

  String _idempotencyKey() {
    final random = Random.secure();
    final suffix = List<String>.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return 'android-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }
}
