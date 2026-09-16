import 'package:flutter/material.dart';

/// Web-style horizontal administration navigation. It deliberately sits below
/// the title instead of hiding important workspaces behind tiny app-bar icons.
final class AdminControlStrip extends StatelessWidget {
  const AdminControlStrip({
    super.key,
    required this.active,
    required this.onDashboard,
    required this.onUsers,
    required this.onQueues,
    required this.onCommerce,
    required this.onCatalog,
    required this.onMarketplace,
    required this.onDelivery,
    required this.onFinance,
    required this.onActivity,
    required this.onOperations,
  });

  final String active;
  final VoidCallback onDashboard;
  final VoidCallback onUsers;
  final VoidCallback onQueues;
  final VoidCallback onCommerce;
  final VoidCallback onCatalog;
  final VoidCallback onMarketplace;
  final VoidCallback onDelivery;
  final VoidCallback onFinance;
  final VoidCallback onActivity;
  final VoidCallback onOperations;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: SizedBox(
          height: 62,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 10),
            children: [
              _item(
                context,
                code: 'dashboard',
                label: 'الرئيسية',
                icon: Icons.dashboard_outlined,
                onTap: onDashboard,
              ),
              _item(
                context,
                code: 'users',
                label: 'المستخدمون',
                icon: Icons.manage_accounts_outlined,
                onTap: onUsers,
              ),
              _item(
                context,
                code: 'queues',
                label: 'الطوابير',
                icon: Icons.rule_folder_outlined,
                onTap: onQueues,
              ),
              _item(
                context,
                code: 'commerce',
                label: 'التجارة والطلبات',
                icon: Icons.inventory_2_outlined,
                onTap: onCommerce,
              ),
              _item(
                context,
                code: 'catalog',
                label: 'كتالوج المتاجر',
                icon: Icons.category_outlined,
                onTap: onCatalog,
              ),
              _item(
                context,
                code: 'marketplace',
                label: 'الحراج والمواقع',
                icon: Icons.storefront_outlined,
                onTap: onMarketplace,
              ),
              _item(
                context,
                code: 'delivery',
                label: 'التوصيل والمهام',
                icon: Icons.delivery_dining_outlined,
                onTap: onDelivery,
              ),
              _item(
                context,
                code: 'finance',
                label: 'السجل المالي',
                icon: Icons.account_balance_wallet_outlined,
                onTap: onFinance,
              ),
              _item(
                context,
                code: 'activity',
                label: 'السجل والإشعارات',
                icon: Icons.history_rounded,
                onTap: onActivity,
              ),
              _item(
                context,
                code: 'operations',
                label: 'السياسات والرسوم',
                icon: Icons.tune_rounded,
                onTap: onOperations,
              ),
            ],
          ),
        ),
      );

  Widget _item(
    BuildContext context, {
    required String code,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final selected = active == code;
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : const Color(0xFFF4F7F3),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 14, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: selected ? color : const Color(0xFF52645C)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? color : const Color(0xFF38493F),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
