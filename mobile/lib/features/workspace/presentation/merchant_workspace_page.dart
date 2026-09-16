import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/network/api_exception.dart';
import '../../catalog/domain/catalog_models.dart';
import '../data/workspace_repository.dart';
import 'merchant_products_page.dart';
import 'store_settings_page.dart';
import 'merchant_store_create_page.dart';
import 'merchant_notification_campaign_page.dart';
import 'merchant_payment_review_page.dart';

final class MerchantWorkspacePage extends StatefulWidget {
  const MerchantWorkspacePage({super.key});

  @override
  State<MerchantWorkspacePage> createState() => _MerchantWorkspacePageState();
}

final class _MerchantWorkspacePageState extends State<MerchantWorkspacePage> {
  late Future<MerchantWorkspace> _future;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _future = AppScope.of(context).loadMerchantWorkspace();
    }
  }

  void _reload() => setState(() => _future = AppScope.of(context).loadMerchantWorkspace());

  Future<void> _createStore() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const MerchantStoreCreatePage()),
    );
    if (created == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إعدادات المتجر')),
    body: FutureBuilder<MerchantWorkspace>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _ErrorState(error: snapshot.error, retry: _reload);
        final workspace = snapshot.data!;
        final store = workspace.store;
        if (store == null) {
          final closed = workspace.storeAccessState == 'closed_by_admin';
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 38),
                Icon(closed ? Icons.storefront_outlined : Icons.add_business_outlined, size: 62, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 18),
                Text(closed ? 'تم إغلاق المتجر' : 'ابدأ بإنشاء متجرك', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Text(closed ? 'أُغلق متجر هذا الحساب من الإدارة، ولا يمكن إنشاء متجر بديل تلقائياً. افتح تذكرة دعم إذا احتجت مراجعة القرار.' : 'لا يوجد متجر مرتبط بهذا الحساب بعد. أنشئ المتجر أولاً، ثم أكمل بياناته وموقعه وساعات العمل قبل تفعيله.', textAlign: TextAlign.center, style: const TextStyle(height: 1.6)),
                if (!closed) ...[
                  const SizedBox(height: 22),
                  FilledButton.icon(onPressed: _createStore, icon: const Icon(Icons.add_business_outlined), label: const Text('إنشاء متجري')),
                ],
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
            children: [
              _StoreStatusCard(
                store: store,
                onOpenSettings: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(builder: (_) => StoreSettingsPage(store: store)),
                  );
                  if (result == true && mounted) _reload();
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(builder: (_) => const MerchantProductsPage()),
                  );
                  if (changed == true && mounted) _reload();
                },
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('المنتجات'),
              ),
              const SizedBox(height: 12),
              if ((store['manual_payment'] as Map?)?['enabled'] == true)
                FilledButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MerchantPaymentReviewPage()));
                    if (mounted) _reload();
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: Text('إشعارات دفع بانتظار المراجعة (${workspace.pendingPayments.length})'),
                )
              else
                const Card(child: ListTile(leading: Icon(Icons.account_balance_outlined), title: Text('التحويل اليدوي غير مفعّل'), subtitle: Text('فعّله وأدخل عنوان الإيداع من إعدادات المتجر.'))),
              const SizedBox(height: 12),
              if (store['store_status'] == 'active')
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MerchantNotificationCampaignPage())),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('حملة للمشتركين والعملاء'),
                )
              else
                const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('فعّل المتجر أولاً لطلب حملة للمشتركين والعملاء.'))),
            ],
          ),
        );
      },
    ),
  );
}

final class _StoreStatusCard extends StatelessWidget {
  const _StoreStatusCard({required this.store, this.onOpenSettings});
  final Map<String, dynamic>? store;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (store == null) return const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لم يتم العثور على متجر هذا الحساب.')));
    final status = store!['store_status'] as String? ?? 'draft';
    final active = status == 'active';
    return Card(
      color: active ? Theme.of(context).colorScheme.primaryContainer.withOpacity(.42) : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          CircleAvatar(radius: 24, child: Icon(active ? Icons.storefront_rounded : Icons.storefront_outlined)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(store!['name'] as String? ?? 'متجري', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 3),
            Text(active ? 'متجرك نشط ويظهر للعملاء.' : 'متجرك في حالة مسودة؛ أكمل الإعدادات ثم فعّله.'),
          ])),
          IconButton(
            tooltip: 'إعدادات المتجر',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ]),
      ),
    );
  }
}


final class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.retry});
  final Object? error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException ? (error as ApiException).message : 'تعذر تحميل مساحة التاجر.';
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: retry, icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة'))])));
  }
}
