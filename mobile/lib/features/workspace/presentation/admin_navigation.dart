import 'package:flutter/material.dart';

import 'admin_activity_page.dart';
import 'admin_catalog_page.dart';
import 'admin_commerce_page.dart';
import 'admin_delivery_page.dart';
import 'admin_finance_page.dart';
import 'admin_control_strip.dart';
import 'admin_dashboard_page.dart';
import 'admin_marketplace_settings_page.dart';
import 'admin_operations_page.dart';
import 'admin_queues_page.dart';
import 'admin_users_page.dart';

/// One navigation policy for all administration screens. The destination
/// replaces the current admin page so the visible control strip behaves like
/// the web workspace tabs, not a deep stack of hidden app-bar icons.
enum AdminDestination { dashboard, users, queues, commerce, catalog, marketplace, delivery, finance, activity, operations }

void openAdminDestination(BuildContext context, AdminDestination destination) {
  final Widget page = switch (destination) {
    AdminDestination.dashboard => const AdminDashboardPage(),
    AdminDestination.users => const AdminUsersPage(),
    AdminDestination.queues => const AdminQueuesPage(),
    AdminDestination.commerce => const AdminCommercePage(),
    AdminDestination.catalog => const AdminCatalogPage(),
    AdminDestination.marketplace => const AdminMarketplaceSettingsPage(),
    AdminDestination.delivery => const AdminDeliveryPage(),
    AdminDestination.finance => const AdminFinancePage(),
    AdminDestination.activity => const AdminActivityPage(),
    AdminDestination.operations => const AdminOperationsPage(),
  };
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(builder: (_) => page),
  );
}

AdminControlStrip _adminStrip(BuildContext context, String active) => AdminControlStrip(
  active: active,
  onDashboard: () => openAdminDestination(context, AdminDestination.dashboard),
  onUsers: () => openAdminDestination(context, AdminDestination.users),
  onQueues: () => openAdminDestination(context, AdminDestination.queues),
  onCommerce: () => openAdminDestination(context, AdminDestination.commerce),
  onCatalog: () => openAdminDestination(context, AdminDestination.catalog),
  onMarketplace: () => openAdminDestination(context, AdminDestination.marketplace),
  onDelivery: () => openAdminDestination(context, AdminDestination.delivery),
  onFinance: () => openAdminDestination(context, AdminDestination.finance),
  onActivity: () => openAdminDestination(context, AdminDestination.activity),
  onOperations: () => openAdminDestination(context, AdminDestination.operations),
);

PreferredSizeWidget adminControlBottom(BuildContext context, String active) =>
    PreferredSize(
      preferredSize: const Size.fromHeight(62),
      child: _adminStrip(context, active),
    );

PreferredSizeWidget adminTabbedBottom(
  BuildContext context,
  String active,
  TabBar tabs,
) => PreferredSize(
  preferredSize: const Size.fromHeight(110),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(height: 62, child: _adminStrip(context, active)),
      SizedBox(height: 48, child: tabs),
    ],
  ),
);
