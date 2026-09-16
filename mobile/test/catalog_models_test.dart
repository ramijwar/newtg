import 'package:flutter_test/flutter_test.dart';
import 'package:tijarti_mobile/features/catalog/domain/catalog_models.dart';
import 'package:tijarti_mobile/features/commerce/domain/commerce_models.dart';

void main() {
  test('MarketplaceListing preserves server fields used by the UI and SQLite cache', () {
    final listing = MarketplaceListing.fromJson(const {
      'public_id': 'listing-1',
      'title': 'هاتف بحالة ممتازة',
      'price_amount': 120.5,
      'currency_code': 'USD',
      'city': 'Amsterdam',
      'category_name': 'إلكترونيات',
      'primary_media_public_id': 'media-1',
    });

    expect(listing.publicId, 'listing-1');
    expect(listing.title, 'هاتف بحالة ممتازة');
    expect(listing.priceAmount, 120.5);
    expect(listing.toJson()['primary_media_public_id'], 'media-1');
    expect(listing.toJson()['seller_name'], isNull);
  });

  test('StoreSummary defaults safely when optional API fields are absent', () {
    final store = StoreSummary.fromJson(const {
      'public_id': 'store-1',
      'name': 'متجر تجريبي',
    });
    expect(store.acceptsDelivery, isTrue);
    expect(store.acceptsPickup, isTrue);
    expect(store.categoryName, isNull);
  });

  test('StoreProduct parses the price selected by the server', () {
    final product = StoreProduct.fromJson(const {
      'public_id': 'product-1',
      'name': 'منتج تجريبي',
      'price': 25,
      'effective_price': 20,
      'currency_code': 'USD',
      'stock_quantity': 3,
    });

    expect(product.effectivePrice, 20);
    expect(product.stockQuantity, 3);
    expect(product.toJson()['public_id'], 'product-1');
  });

  test('cart parses decimal amounts returned by the PHP API', () {
    final cart = ShoppingCart.fromJson(const {
      'public_id': 'cart-1',
      'store': {
        'public_id': 'store-1',
        'name': 'متجر تجريبي',
        'currency_code': 'USD',
      },
      'subtotal_amount': '39.90',
      'items': [
        {
          'product_public_id': 'product-1',
          'name': 'منتج',
          'quantity': 2,
          'effective_price': '19.95',
          'currency_code': 'USD',
          'available_stock': 4,
        },
      ],
    });

    expect(cart.subtotal, 39.90);
    expect(cart.itemCount, 2);
    expect(cart.items.single.effectivePrice, 19.95);
  });
}
