import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../catalog/presentation/catalog_detail_pages.dart';
import '../../catalog/presentation/marketplace_activity_page.dart';
import '../../commerce/presentation/orders_page.dart';
import '../../workspace/presentation/courier_tasks_page.dart';
import '../../workspace/presentation/merchant_workspace_page.dart';
import '../../workspace/presentation/support_tickets_page.dart';
import '../../workspace/presentation/wallet_page.dart';

/// Opens the safest useful destination for every notification entity created by
/// the backend. No notification payload is trusted as authentication data; the
/// target screen always reloads its own API-protected data.
Future<bool> openNotificationTarget(
  BuildContext context, {
  String? entityType,
  String? entityPublicId,
  String? category,
}) async {
  final id = entityPublicId?.trim();
  final roles = AppScope.of(context).session?.roles ?? const <String>[];
  Widget? page;

  // A campaign's explicit public destination takes precedence over its category.
  // The destination pages reload and enforce their own visibility rules.
  if (entityType == 'store' && id != null && id.isNotEmpty) {
    page = StoreDetailsPage(storeId: id, storeName: 'المتجر');
  } else if (entityType == 'product' && id != null && id.isNotEmpty) {
    page = ProductDetailsPage(productId: id, title: 'تفاصيل المنتج');
  }
  if (page == null && category == 'wallet') {
    page = roles.contains('courier')
        ? const WalletPage(role: 'courier')
        : roles.contains('merchant')
            ? const WalletPage(role: 'merchant')
            : null;
  }
  page ??= switch (entityType) {
    'marketplace_conversation' when id != null && id.isNotEmpty =>
      MarketplaceConversationPage(conversationId: id, title: 'محادثة الحراج'),
    'marketplace_listing' when id != null && id.isNotEmpty =>
      ListingDetailsPage(listingId: id, title: 'تفاصيل إعلان الحراج'),
    'marketplace_transaction' => const MarketplaceActivityPage(initialIndex: 3),
    'delivery_task' => const CourierTasksPage(),
    'order' || 'order_payment' => roles.contains('merchant')
        ? const MerchantWorkspacePage()
        : const OrdersPage(),
    'support_ticket' => const SupportTicketsPage(),
    _ => null,
  };
  if (page == null || !context.mounted) return false;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page!));
  return true;
}
