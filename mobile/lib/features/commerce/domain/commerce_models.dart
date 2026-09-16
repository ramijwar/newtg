final class CustomerAddress {
  const CustomerAddress({
    required this.publicId,
    required this.label,
    required this.recipientName,
    required this.phone,
    required this.countryCode,
    required this.city,
    required this.district,
    required this.addressLine1,
    required this.addressLine2,
    required this.latitude,
    required this.longitude,
    required this.isDefault,
  });

  final String publicId;
  final String label;
  final String recipientName;
  final String phone;
  final String countryCode;
  final String city;
  final String? district;
  final String addressLine1;
  final String? addressLine2;
  final double? latitude;
  final double? longitude;
  final bool isDefault;

  factory CustomerAddress.fromJson(Map<String, dynamic> json) =>
      CustomerAddress(
        publicId: json['public_id'] as String? ?? '',
        label: json['label'] as String? ?? 'عنوان التوصيل',
        recipientName: json['recipient_name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        countryCode: json['country_code'] as String? ?? '',
        city: json['city'] as String? ?? '',
        district: json['district'] as String?,
        addressLine1: json['address_line1'] as String? ?? '',
        addressLine2: json['address_line2'] as String?,
        latitude: _doubleOrNull(json['latitude']),
        longitude: _doubleOrNull(json['longitude']),
        isDefault: json['is_default'] == true,
      );

  Map<String, dynamic> toInput() => {
    'label': label.trim(),
    'recipient_name': recipientName.trim(),
    'phone': phone.trim(),
    'country_code': countryCode.trim().toUpperCase(),
    'city': city.trim(),
    'district': district?.trim(),
    'address_line1': addressLine1.trim(),
    'address_line2': addressLine2?.trim(),
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    'is_default': isDefault,
  };
}

final class ManualPaymentInstructions {
  const ManualPaymentInstructions({
    required this.enabled,
    this.depositTitle,
    this.depositAddress,
    this.instructions,
  });

  final bool enabled;
  final String? depositTitle;
  final String? depositAddress;
  final String? instructions;

  factory ManualPaymentInstructions.fromJson(Map<String, dynamic> json) =>
      ManualPaymentInstructions(
        enabled: json['enabled'] == true || json['enabled'] == 1,
        depositTitle: json['deposit_title'] as String?,
        depositAddress: json['deposit_address'] as String?,
        instructions: json['instructions'] as String?,
      );
}

final class PaymentNotice {
  const PaymentNotice({
    required this.status,
    required this.hasReceipt,
    this.reference,
    this.note,
    this.merchantNote,
    this.reviewedAt,
  });

  final String status;
  final bool hasReceipt;
  final String? reference;
  final String? note;
  final String? merchantNote;
  final String? reviewedAt;

  factory PaymentNotice.fromJson(Map<String, dynamic> json) => PaymentNotice(
    status: json['payment_status'] as String? ?? 'submitted',
    hasReceipt: json['has_receipt'] == true || json['has_receipt'] == 1,
    reference: json['transfer_reference'] as String?,
    note: json['payer_note'] as String?,
    merchantNote: json['merchant_note'] as String?,
    reviewedAt: json['merchant_reviewed_at'] as String?,
  );
}

final class DeliveryQuote {
  const DeliveryQuote({
    required this.distanceKm,
    required this.durationSeconds,
    required this.baseFee,
    required this.perKmFee,
    required this.deliveryFee,
    required this.currencyCode,
  });

  final num distanceKm;
  final int durationSeconds;
  final num baseFee;
  final num perKmFee;
  final num deliveryFee;
  final String currencyCode;

  factory DeliveryQuote.fromJson(Map<String, dynamic> json) => DeliveryQuote(
    distanceKm: _num(json['distance_km']),
    durationSeconds: _int(json['duration_seconds']),
    baseFee: _num(json['base_fee_amount']),
    perKmFee: _num(json['per_km_fee_amount']),
    deliveryFee: _num(json['delivery_fee_amount']),
    currencyCode: json['currency_code'] as String? ?? 'USD',
  );
}

final class CartItem {
  const CartItem({
    required this.productPublicId,
    required this.name,
    required this.quantity,
    required this.effectivePrice,
    required this.currencyCode,
    required this.availableStock,
    required this.mediaPublicId,
  });

  final String productPublicId;
  final String name;
  final int quantity;
  final num effectivePrice;
  final String currencyCode;
  final int availableStock;
  final String? mediaPublicId;

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    productPublicId: json['product_public_id'] as String? ?? '',
    name: json['name'] as String? ?? 'منتج',
    quantity: _int(json['quantity']),
    effectivePrice: _num(json['effective_price'] ?? json['price']),
    currencyCode: json['currency_code'] as String? ?? 'USD',
    availableStock: _int(json['available_stock']),
    mediaPublicId: json['primary_media_public_id'] as String?,
  );
}

final class ShoppingCart {
  const ShoppingCart({
    required this.publicId,
    required this.storeId,
    required this.storeName,
    required this.currencyCode,
    required this.items,
    required this.subtotal,
    this.acceptsDelivery = true,
    this.acceptsPickup = true,
    this.manualPayment,
  });

  final String publicId;
  final String storeId;
  final String storeName;
  final String currencyCode;
  final List<CartItem> items;
  final num subtotal;
  final bool acceptsDelivery;
  final bool acceptsPickup;
  final ManualPaymentInstructions? manualPayment;

  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  factory ShoppingCart.fromJson(Map<String, dynamic> json) {
    final store = json['store'] is Map
        ? Map<String, dynamic>.from(json['store'] as Map)
        : const <String, dynamic>{};
    final rawItems = json['items'];
    final manual = store['manual_payment'] is Map
        ? Map<String, dynamic>.from(store['manual_payment'] as Map)
        : const <String, dynamic>{};
    return ShoppingCart(
      publicId: json['public_id'] as String? ?? '',
      storeId: store['public_id'] as String? ?? '',
      storeName: store['name'] as String? ?? 'متجر تجارتي',
      currencyCode: store['currency_code'] as String? ?? 'USD',
      acceptsDelivery: store['accepts_delivery'] != false,
      acceptsPickup: store['accepts_pickup'] != false,
      manualPayment: manual.isEmpty ? null : ManualPaymentInstructions.fromJson(manual),
      items: (rawItems is List ? rawItems : const [])
          .whereType<Map>()
          .map((item) => CartItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      subtotal: _num(json['subtotal_amount']),
    );
  }
}

final class CustomerOrder {
  const CustomerOrder({
    required this.publicId,
    required this.orderNumber,
    required this.orderStatus,
    required this.paymentMethod,
    required this.currencyCode,
    required this.total,
    required this.deliveryFee,
    required this.deliveryDistanceKm,
    required this.storeName,
    required this.placedAt,
    required this.items,
    required this.history,
    this.paymentStatus = 'unpaid',
    this.invoiceNumber,
    this.manualPayment,
    this.payment,
  });

  final String publicId;
  final String orderNumber;
  final String orderStatus;
  final String paymentMethod;
  final String currencyCode;
  final num total;
  final num deliveryFee;
  final num? deliveryDistanceKm;
  final String storeName;
  final String? placedAt;
  final List<OrderItem> items;
  final List<OrderHistoryEvent> history;
  final String paymentStatus;
  final String? invoiceNumber;
  final ManualPaymentInstructions? manualPayment;
  final PaymentNotice? payment;

  factory CustomerOrder.fromJson(Map<String, dynamic> json) {
    final store = json['store'] is Map
        ? Map<String, dynamic>.from(json['store'] as Map)
        : const <String, dynamic>{};
    final rawItems = json['items'];
    final rawHistory = json['history'];
    final manual = store['manual_payment'] is Map
        ? Map<String, dynamic>.from(store['manual_payment'] as Map)
        : const <String, dynamic>{};
    final payment = json['payment'] is Map
        ? Map<String, dynamic>.from(json['payment'] as Map)
        : const <String, dynamic>{};
    final invoice = json['invoice'] is Map
        ? Map<String, dynamic>.from(json['invoice'] as Map)
        : const <String, dynamic>{};
    return CustomerOrder(
      publicId: json['public_id'] as String? ?? '',
      orderNumber: json['order_number'] as String? ?? 'طلب تجارتي',
      orderStatus: json['order_status'] as String? ?? 'pending',
      paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      invoiceNumber: invoice['invoice_number'] as String?,
      manualPayment: manual.isEmpty ? null : ManualPaymentInstructions.fromJson(manual),
      payment: payment.isEmpty ? null : PaymentNotice.fromJson(payment),
      paymentMethod: json['payment_method'] as String? ?? '',
      currencyCode: json['currency_code'] as String? ?? 'USD',
      total: _num(json['total_amount']),
      deliveryFee: _num(json['delivery_fee_amount']),
      deliveryDistanceKm: _doubleOrNull(json['delivery_distance_km']),
      storeName: store['name'] as String? ?? 'متجر تجارتي',
      placedAt: json['placed_at'] as String?,
      items: (rawItems is List ? rawItems : const [])
          .whereType<Map>()
          .map((item) => OrderItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      history: (rawHistory is List ? rawHistory : const [])
          .whereType<Map>()
          .map(
            (item) =>
                OrderHistoryEvent.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
    );
  }
}

final class OrderItem {
  const OrderItem({
    required this.name,
    required this.quantity,
    required this.lineTotal,
  });

  final String name;
  final int quantity;
  final num lineTotal;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    name: json['name'] as String? ?? 'منتج',
    quantity: _int(json['quantity']),
    lineTotal: _num(json['line_total_amount']),
  );
}

final class OrderHistoryEvent {
  const OrderHistoryEvent({
    required this.toStatus,
    required this.note,
    required this.createdAt,
  });

  final String toStatus;
  final String? note;
  final String? createdAt;

  factory OrderHistoryEvent.fromJson(Map<String, dynamic> json) =>
      OrderHistoryEvent(
        toStatus: json['to_status'] as String? ?? '',
        note: json['note'] as String?,
        createdAt: json['created_at'] as String?,
      );
}

num _num(Object? value) => value is num ? value : num.tryParse('$value') ?? 0;
int _int(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;
double? _doubleOrNull(Object? value) => value is num ? value.toDouble() : double.tryParse('$value');
