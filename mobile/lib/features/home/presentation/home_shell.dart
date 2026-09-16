import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/presentation/auth_page.dart';
import 'about_page.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/presentation/catalog_detail_pages.dart';
import '../../catalog/presentation/featured_products_panel.dart';
import '../../catalog/presentation/marketplace_activity_page.dart';
import '../../catalog/presentation/marketplace_browse_page.dart';
import '../../catalog/presentation/store_browse_page.dart';
import '../../commerce/presentation/cart_page.dart';
import '../../commerce/presentation/orders_page.dart';
import '../../commerce/presentation/addresses_page.dart';
import '../../notifications/presentation/notifications_page.dart';
import '../../workspace/presentation/admin_dashboard_page.dart';
import '../../workspace/presentation/courier_tasks_page.dart';
import '../../workspace/presentation/merchant_workspace_page.dart';
import '../../workspace/presentation/merchant_products_page.dart';
import '../../workspace/presentation/account_verification_page.dart';
import '../../workspace/presentation/support_tickets_page.dart';
import '../../workspace/presentation/wallet_page.dart';

final class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

final class _HomeShellState extends State<HomeShell> {
  int _tabIndex = 0;
  String _storeMode = '';

  void _selectStoreMode(String mode, {bool openStoresTab = true}) {
    setState(() {
      _storeMode = mode == 'retail' || mode == 'preorder' ? mode : '';
      if (openStoresTab) _tabIndex = 1;
    });
    unawaited(AppScope.of(context).loadStoreDirectory(mode: _storeMode));
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    if (controller.isBootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = [
      _DiscoverTab(onOpenMarketplace: () => setState(() => _tabIndex = 2)),
      _StoresTab(mode: _storeMode, onModeChanged: _selectStoreMode),
      const _MarketplaceTab(),
      const _AccountTab(),
    ];

    return Scaffold(
      drawer: _StoreDirectoryDrawer(
        mode: _storeMode,
        onModeChanged: _selectStoreMode,
      ),
      onDrawerChanged: (isOpen) {
        if (isOpen) unawaited(controller.loadStoreDirectory(mode: _storeMode));
      },
      appBar: AppBar(
        title: const _Brand(),
        actions: [
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: controller.session == null
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const AuthPage()),
                  )
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationsPage(),
                    ),
                  ),
            icon: Badge(
              isLabelVisible: controller.unreadNotificationCount > 0,
              label: Text(controller.unreadNotificationCount > 99 ? '99+' : '${controller.unreadNotificationCount}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          IconButton(
            tooltip: 'محادثات الحراج',
            onPressed: controller.session == null
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const AuthPage()),
                  )
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MarketplaceActivityPage(initialIndex: 2),
                    ),
                  ),
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: 'المفضلة',
            onPressed: controller.session == null
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const AuthPage()),
                  )
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MarketplaceActivityPage(initialIndex: 1),
                    ),
                  ),
            icon: const Icon(Icons.favorite_border_rounded),
          ),
          if (controller.isCustomer)
            IconButton(
              tooltip: 'سلة المشتريات',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => const CartPage())),
              icon: Badge(
                isLabelVisible: controller.cartItemCount > 0,
                label: Text('${controller.cartItemCount}'),
                child: const Icon(Icons.shopping_bag_outlined),
              ),
            ),
          IconButton(
            tooltip: 'تحديث المحتوى',
            onPressed: controller.isRefreshing ? null : controller.refreshHome,
            icon: controller.isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: pages[_tabIndex]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) => setState(() => _tabIndex = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: 'المتاجر',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'الحراج',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'حسابي',
          ),
        ],
      ),
    );
  }
}

final class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 29,
        height: 29,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Icon(
          Icons.storefront_rounded,
          size: 18,
          color: Colors.white,
        ),
      ),
      const SizedBox(width: 8),
      const Text('تجارتي', style: TextStyle(fontWeight: FontWeight.w900)),
    ],
  );
}

final class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab({required this.onOpenMarketplace});
  final VoidCallback onOpenMarketplace;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final feed = controller.feed;
    return RefreshIndicator(
      onRefresh: controller.refreshHome,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _Hero(onExplore: onOpenMarketplace),
          if (feed.isStale) _OfflineNotice(lastSyncedAt: feed.lastSyncedAt),
          if (controller.homeError != null)
            _ErrorNotice(message: controller.homeError!),
          const SizedBox(height: 28),
          _SectionHeader(
            title: 'إعلانات قريبة منك',
            subtitle: 'أحدث ما نُشر في الحراج',
          ),
          const SizedBox(height: 12),
          if (feed.listings.isEmpty)
            const _EmptyCard(
              icon: Icons.grid_view_rounded,
              title: 'لا توجد إعلانات منشورة بعد',
              body: 'ستظهر الإعلانات المعتمدة هنا فور نشرها.',
            )
          else
            SizedBox(
              height: 248,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: feed.listings.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, index) => _ListingCard(
                  listing: feed.listings[index],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ListingDetailsPage(
                        listingId: feed.listings[index].publicId,
                        title: feed.listings[index].title,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 30),
          const _SectionHeader(
            title: 'متاجر محلية',
            subtitle: 'متاجر موثوقة جاهزة لاستقبال طلباتك',
          ),
          const SizedBox(height: 12),
          if (feed.stores.isEmpty)
            const _EmptyCard(
              icon: Icons.storefront_rounded,
              title: 'لا توجد متاجر منشورة بعد',
              body: 'عند تفعيل أول متجر سيظهر هنا تلقائياً.',
            )
          else
            ...feed.stores
                .take(5)
                .map(
                  (store) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StoreCard(
                      store: store,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StoreDetailsPage(
                            storeId: store.publicId,
                            storeName: store.name,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

final class _Hero extends StatelessWidget {
  const _Hero({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF0E6756), Color(0xFF19816C)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26125F4F),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                color: Color(0xFFBFE8D9),
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                'كل ما تحتاجه، أقرب إليك',
                style: TextStyle(
                  color: Color(0xFFDBF4EA),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'تسوّق محلياً،\nبطريقة أذكى.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1.18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'اكتشف متاجر وإعلانات موثوقة في تجربة عربية واضحة وسلسة.',
            style: TextStyle(color: Color(0xFFE2F4ED), height: 1.55),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: theme.colorScheme.primary,
              minimumSize: const Size(0, 46),
            ),
            onPressed: onExplore,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('اكتشف الحراج'),
          ),
        ],
      ),
    );
  }
}

final class _StoresTab extends StatefulWidget {
  const _StoresTab({required this.mode, required this.onModeChanged});

  final String mode;
  final ValueChanged<String> onModeChanged;

  @override
  State<_StoresTab> createState() => _StoresTabState();
}

final class _StoresTabState extends State<_StoresTab> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      unawaited(AppScope.of(context).loadStoreDirectory(mode: widget.mode));
    }
  }

  @override
  void didUpdateWidget(covariant _StoresTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      unawaited(AppScope.of(context).loadStoreDirectory(mode: widget.mode));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final isCurrentMode = controller.storeDirectoryMode == widget.mode;
    final stores = isCurrentMode ? controller.storeDirectory : const <StoreSummary>[];
    return RefreshIndicator(
      onRefresh: () => controller.loadStoreDirectory(mode: widget.mode, force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(
            title: 'المتاجر',
            subtitle: 'كل المتاجر المحلية النشطة مرتبة حسب الزيارات',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StoreBrowsePage()),
            ),
            icon: const Icon(Icons.manage_search_rounded),
            label: const Text('البحث وتصفية المتاجر'),
          ),
          const SizedBox(height: 16),
          _StoreModeFilters(
            mode: widget.mode,
            onChanged: widget.onModeChanged,
          ),
          const SizedBox(height: 16),
          if (controller.isStoreDirectoryLoading && !isCurrentMode)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.storeDirectoryError != null && isCurrentMode)
            _DirectoryError(
              message: controller.storeDirectoryError!,
              onRetry: () => controller.loadStoreDirectory(
                mode: widget.mode,
                force: true,
              ),
            )
          else if (stores.isEmpty)
            const _EmptyCard(
              icon: Icons.storefront_rounded,
              title: 'لا توجد متاجر متاحة الآن',
              body: 'اسحب للأسفل لتحديث المحتوى من الخادم.',
            )
          else ...[
            Text(
              'كل المتاجر (${stores.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 9),
            ...stores.map(
              (store) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _StoreCard(
                  store: store,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StoreDetailsPage(
                        storeId: store.publicId,
                        storeName: store.name,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const FeaturedProductsPanel(
              kind: 'best_selling',
              title: 'الأكثر مبيعاً',
              emptyText: 'ستظهر المنتجات الأكثر مبيعاً بعد اكتمال الطلبات.',
            ),
            const SizedBox(height: 22),
            const FeaturedProductsPanel(
              kind: 'top_rated',
              title: 'الأعلى تقييماً',
              emptyText: 'ستظهر المنتجات الأعلى تقييماً بعد تسجيل تقييمات العملاء.',
            ),
          ],
        ],
      ),
    );
  }
}

final class _StoreDirectoryDrawer extends StatelessWidget {
  const _StoreDirectoryDrawer({
    required this.mode,
    required this.onModeChanged,
  });

  final String mode;
  final ValueChanged<String> onModeChanged;

  void _chooseMode(BuildContext context, String value) {
    Navigator.of(context).pop();
    onModeChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final stores = controller.storeDirectoryMode == mode
        ? controller.storeDirectory
        : const <StoreSummary>[];
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'دليل المتاجر',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Text('كل المتاجر وعلامات الاكتشاف'),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StoreModeFilters(
                mode: mode,
                compact: true,
                onChanged: (value) => _chooseMode(context, value),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 13, 18, 8),
              child: Text(
                'الأكثر زيارة يحمل علامة مميزة، والمتجر الأكثر مبيعاً يحمل علامة ترند.',
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: controller.isStoreDirectoryLoading && stores.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : controller.storeDirectoryError != null && stores.isEmpty
                      ? _DirectoryError(
                          message: controller.storeDirectoryError!,
                          onRetry: () => controller.loadStoreDirectory(
                            mode: mode,
                            force: true,
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: stores.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) => _StoreCard(
                            store: stores[index],
                            compact: true,
                            onTap: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => StoreDetailsPage(
                                    storeId: stores[index].publicId,
                                    storeName: stores[index].name,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _StoreModeFilters extends StatelessWidget {
  const _StoreModeFilters({
    required this.mode,
    required this.onChanged,
    this.compact = false,
  });

  final String mode;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          _filter(context, '', 'الكل'),
          _filter(context, 'retail', 'تجزئة'),
          _filter(context, 'preorder', 'بيع مسبق'),
        ],
      );

  Widget _filter(BuildContext context, String value, String label) => ChoiceChip(
        label: Text(label),
        selected: mode == value,
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        onSelected: (_) => onChanged(value),
      );
}

final class _DirectoryError extends StatelessWidget {
  const _DirectoryError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
}

final class _MarketplaceTab extends StatefulWidget {
  const _MarketplaceTab();

  @override
  State<_MarketplaceTab> createState() => _MarketplaceTabState();
}

final class _MarketplaceTabState extends State<_MarketplaceTab> {
  Future<CatalogPage<MarketplaceListing>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<CatalogPage<MarketplaceListing>> _load() => AppScope.of(context).browseMarketplacePage();

  Future<void> _reload() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  void _openBrowse() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MarketplaceBrowsePage()),
      );

  void _openActivity() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MarketplaceActivityPage()),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<CatalogPage<MarketplaceListing>>(
        future: _future,
        builder: (context, snapshot) {
          final listings = snapshot.data?.items ?? const <MarketplaceListing>[];
          return RefreshIndicator(
            onRefresh: _reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(child: _MarketplaceTabHero(onBrowse: _openBrowse, onActivity: _openActivity)),
                if (snapshot.connectionState != ConnectionState.done)
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 28),
                    sliver: _MarketplaceTabLoading(),
                  )
                else if (snapshot.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MarketplaceTabStateCard(
                      icon: Icons.cloud_off_rounded,
                      title: 'تعذر تحديث الحراج',
                      body: snapshot.error is ApiException
                          ? (snapshot.error as ApiException).message
                          : 'تحقق من اتصالك ثم حاول التحديث مرة أخرى.',
                      actionLabel: 'إعادة المحاولة',
                      onAction: () { _reload(); },
                    ),
                  )
                else if (listings.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MarketplaceTabStateCard(
                      icon: Icons.storefront_outlined,
                      title: 'الحراج ينتظر أول إعلان',
                      body: 'لا توجد إعلانات نشطة حاليًا. تصفح أقسام الحراج أو أدر إعلاناتك من مساحتك.',
                      actionLabel: 'فتح مساحة الحراج',
                      onAction: _openActivity,
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 9),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('أحدث الإعلانات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text('تُحدّث باستمرار من الحراج المحلي', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ])),
                        TextButton.icon(onPressed: _openBrowse, icon: const Icon(Icons.arrow_back_rounded, size: 18), label: const Text('عرض الكل')),
                      ]),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 5, 16, 30),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 260,
                        mainAxisExtent: 294,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: listings.length,
                      itemBuilder: (context, index) => _MarketplaceTabReveal(
                        key: ValueKey(listings[index].publicId),
                        index: index,
                        child: _ListingCard(
                          listing: listings[index],
                          wide: false,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ListingDetailsPage(
                                listingId: listings[index].publicId,
                                title: listings[index].title,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
}

final class _MarketplaceTabHero extends StatelessWidget {
  const _MarketplaceTabHero({required this.onBrowse, required this.onActivity});
  final VoidCallback onBrowse;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          gradient: const LinearGradient(
            colors: [Color(0xFF114F40), Color(0xFF287C60), Color(0xFF83BF75)],
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
          ),
          boxShadow: const [BoxShadow(color: Color(0x33205748), blurRadius: 22, offset: Offset(0, 10))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(color: Colors.white.withOpacity(.17), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.storefront_rounded, color: Colors.white),
            ),
            const SizedBox(width: 11),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('الحراج', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
              SizedBox(height: 2),
              Text('فرص محلية جديدة كل يوم', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            ])),
            IconButton(
              tooltip: 'مساحة الحراج',
              onPressed: onActivity,
              icon: const Icon(Icons.dashboard_customize_outlined, color: Colors.white),
            ),
          ]),
          const SizedBox(height: 16),
          const Text('ابحث، تواصل، واعثر على ما يناسبك بالقرب منك.', style: TextStyle(color: Colors.white, height: 1.45, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 15),
          Row(children: [
            Expanded(child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF155644), minimumSize: const Size(0, 44)),
              onPressed: onBrowse,
              icon: const Icon(Icons.travel_explore_rounded),
              label: const Text('استكشف الحراج'),
            )),
            const SizedBox(width: 9),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0x99FFFFFF)), minimumSize: const Size(54, 44)),
              onPressed: onActivity,
              child: const Icon(Icons.person_outline_rounded),
            ),
          ]),
        ]),
      );
}

final class _MarketplaceTabLoading extends StatelessWidget {
  const _MarketplaceTabLoading();

  @override
  Widget build(BuildContext context) => SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          mainAxisExtent: 294,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _MarketplaceTabSkeleton(delay: index * 75),
          childCount: 6,
        ),
      );
}

final class _MarketplaceTabSkeleton extends StatelessWidget {
  const _MarketplaceTabSkeleton({required this.delay});
  final int delay;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: .32, end: .86),
        duration: Duration(milliseconds: 850 + delay),
        curve: Curves.easeInOut,
        builder: (_, opacity, __) => Card(
          child: Opacity(
            opacity: opacity,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Container(decoration: BoxDecoration(color: const Color(0xFFE4ECE7), borderRadius: BorderRadius.circular(16)))),
                const SizedBox(height: 11),
                Container(height: 10, width: 76, color: const Color(0xFFE4ECE7)),
                const SizedBox(height: 8),
                Container(height: 13, width: double.infinity, color: const Color(0xFFE4ECE7)),
                const SizedBox(height: 8),
                Container(height: 10, width: 118, color: const Color(0xFFE4ECE7)),
              ]),
            ),
          ),
        ),
      );
}

final class _MarketplaceTabStateCard extends StatelessWidget {
  const _MarketplaceTabStateCard({required this.icon, required this.title, required this.body, required this.actionLabel, required this.onAction});
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 52),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Card(child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(23)),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 34),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.55)),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.arrow_back_rounded), label: Text(actionLabel)),
            ]),
          )),
        )),
      );
}

final class _MarketplaceTabReveal extends StatelessWidget {
  const _MarketplaceTabReveal({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 250 + index.clamp(0, 8).toInt() * 50),
        curve: Curves.easeOutCubic,
        builder: (_, value, child) => Transform.translate(offset: Offset(0, 16 * (1 - value)), child: Opacity(opacity: value, child: child)),
        child: child,
      );
}

final class _AccountTab extends StatefulWidget {
  const _AccountTab();

  @override
  State<_AccountTab> createState() => _AccountTabState();
}

final class _AccountTabState extends State<_AccountTab> {
  bool _uploadingAvatar = false;

  Future<void> _changeAvatar() async {
    final image = await ImageUploadPolicy.pick(ImageSource.gallery);
    if (!mounted || image == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      await AppScope.of(context).updateProfileAvatar(image);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث صورة الملف الشخصي.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر رفع الصورة الشخصية الآن.')),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  String _roleLabel(String role) => switch (role) {
        'customer' => 'عميل',
        'merchant' => 'تاجر',
        'courier' => 'عامل توصيل',
        'admin' => 'مدير',
        _ => role,
      };

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final session = controller.session;
    if (session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 30,
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 34,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'أهلاً بك في تجارتي',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'سجّل الدخول لمتابعة الطلبات والإعلانات والإشعارات.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const AuthPage()),
                    ),
                    child: const Text('تسجيل الدخول'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                    ),
                    child: const Text('عن تجارتي'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final roles = session.roles;
    final avatarId = session.user['avatar_media_public_id'] as String?;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipOval(
                        child: SizedBox.square(
                          dimension: 60,
                          child: avatarId?.isNotEmpty == true
                              ? CachedMediaImage(
                                  mediaPublicId: avatarId!,
                                  fit: BoxFit.cover,
                                  errorIcon: Icons.person_outline_rounded,
                                )
                              : CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Text(
                                    _initial(session.fullName).toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Material(
                          color: Theme.of(context).colorScheme.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _uploadingAvatar ? null : _changeAvatar,
                            child: SizedBox.square(
                              dimension: 28,
                              child: Center(
                                child: _uploadingAvatar
                                    ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.add_a_photo_outlined,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'حسابي · ${roles.isEmpty ? 'مستخدم' : roles.map(_roleLabel).join('، ')}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.fullName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      if (session.identityLabel != null)
                        Text(
                          session.identityLabel!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _AccountAction(
          icon: Icons.support_agent_rounded,
          title: 'الدعم',
          compact: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SupportTicketsPage()),
          ),
        ),
        ...roles
            .where((role) => role == 'merchant' || role == 'courier')
            .map((role) => _VerificationAccountAction(roleCode: role)),
        if (roles.contains('customer'))
          _AccountAction(
            icon: Icons.shopping_bag_outlined,
            title: 'سلة المشتريات',
            subtitle: controller.cartItemCount == 0
                ? 'لا توجد منتجات في السلة'
                : '${controller.cartItemCount} منتجات جاهزة للمراجعة',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const CartPage())),
          ),
        if (roles.contains('customer'))
          _AccountAction(
            icon: Icons.receipt_long_outlined,
            title: 'طلباتي',
            subtitle: 'تابع الطلبات وحالة الدفع والتوصيل',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const OrdersPage())),
          ),
        if (roles.contains('customer'))
          _AccountAction(
            icon: Icons.location_on_outlined,
            title: 'عنوان التوصيل',
            subtitle: 'عنوان واحد يستخدم للطلبات والتوصيل',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AddressesPage()),
            ),
          ),
        _AccountAction(
          icon: Icons.grid_view_rounded,
          title: 'مساحة الحراج',
          subtitle: 'إعلاناتي ومفضلتي ومحادثاتي وصفقاتي',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MarketplaceActivityPage()),
          ),
        ),
        ...roles
            .where((role) => role == 'merchant' || role == 'courier')
            .map(
              (role) => _AccountAction(
                icon: Icons.account_balance_wallet_outlined,
                title: 'محفظة ${_roleLabel(role)}',
                subtitle: 'الرصيد المتاح وطلبات السحب',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => WalletPage(role: role)),
                ),
              ),
            ),
        if (roles.contains('merchant'))
          _AccountAction(
            icon: Icons.settings_outlined,
            title: 'إعدادات المتجر',
            subtitle: 'بيانات المتجر وحالة التفعيل والحملات',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MerchantWorkspacePage()),
            ),
          ),
        if (roles.contains('merchant'))
          _AccountAction(
            icon: Icons.inventory_2_outlined,
            title: 'المنتجات',
            subtitle: 'إضافة المنتجات وتعديلها وإدارتها',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MerchantProductsPage()),
            ),
          ),
        if (roles.contains('courier'))
          _AccountAction(
            icon: Icons.local_shipping_outlined,
            title: 'مهام التوصيل',
            subtitle: 'حالة التوفر والمهام المسندة',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CourierTasksPage()),
            ),
          ),
        if (roles.contains('admin'))
          _AccountAction(
            icon: Icons.admin_panel_settings_outlined,
            title: 'لوحة الإدارة',
            subtitle: 'مراجعات الحسابات والمتاجر وإعلانات الحراج',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminDashboardPage(),
              ),
            ),
          ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () async {
            await controller.logout();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم تسجيل الخروج من هذا الجهاز.')),
              );
            }
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('تسجيل الخروج'),
        ),
      ],
    );
  }
}

final class _VerificationAccountAction extends StatefulWidget {
  const _VerificationAccountAction({required this.roleCode});
  final String roleCode;
  @override
  State<_VerificationAccountAction> createState() => _VerificationAccountActionState();
}

final class _VerificationAccountActionState extends State<_VerificationAccountAction> {
  late Future<List<Map<String, dynamic>>> _future;
  @override void didChangeDependencies() { super.didChangeDependencies(); _future = AppScope.of(context).loadMyVerificationRequests(); }
  String _label(List<Map<String, dynamic>> items) {
    final current = items.where((item) => item['role_code'] == widget.roleCode).map((item) => item['verification_status'] as String? ?? 'not_submitted').cast<String?>().firstWhere((value) => value != null, orElse: () => 'not_submitted') ?? 'not_submitted';
    return switch (current) { 'pending' => 'مراجعة', 'verified' => 'موثق', _ => 'توثيق' };
  }
  IconData _icon(String label) => switch (label) { 'موثق' => Icons.verified_rounded, 'مراجعة' => Icons.hourglass_top_rounded, _ => Icons.verified_user_outlined };
  Future<void> _open() async { await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AccountVerificationPage(roleCode: widget.roleCode))); if (mounted) setState(() => _future = AppScope.of(context).loadMyVerificationRequests()); }
  @override Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(future: _future, builder: (context, snapshot) { final label = _label(snapshot.data ?? const []); return _AccountAction(icon: _icon(label), title: label, compact: true, onTap: _open); });
}

final class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.title,
    this.subtitle,
    this.compact = false,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 4 : 8),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: subtitle == null || subtitle!.trim().isEmpty ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: onTap,
    ),
  );
}

final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

final class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, this.onTap, this.compact = false});
  final StoreSummary store;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      leading: SizedBox.square(
        dimension: 44,
        child: ClipOval(
          child: store.logoMediaPublicId?.isNotEmpty == true
              ? CachedMediaImage(
                  mediaPublicId: store.logoMediaPublicId!,
                  fit: BoxFit.cover,
                )
              : CircleAvatar(
                  backgroundColor: const Color(0xFFD9F0E8),
                  child: Text(
                    _initial(store.name),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              store.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          if (store.isVerified) ...[
            const SizedBox(width: 5),
            const Icon(Icons.verified_rounded, color: Color(0xFF2585E6), size: 19),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            store.description?.isNotEmpty == true
                ? store.description!
                : (store.categoryName ?? 'متجر محلي'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (store.discoveryTagline?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              store.discoveryTagline!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (!compact && (store.isWeeklyMostVisited || store.isBestSeller)) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                if (store.isWeeklyMostVisited)
                  const _StoreDiscoveryBadge(
                    label: 'الأكثر زيارة',
                    icon: Icons.local_fire_department_rounded,
                    color: Color(0xFFC44718),
                  ),
                if (store.isBestSeller)
                  const _StoreDiscoveryBadge(
                    label: 'ترند',
                    icon: Icons.trending_up_rounded,
                    color: Color(0xFF7A4D2F),
                  ),
              ],
            ),
          ],
        ],
      ),
      trailing: Icon(
        store.acceptsDelivery
            ? Icons.local_shipping_outlined
            : Icons.store_mall_directory_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      onTap: onTap,
    ),
  );
}


final class _StoreDiscoveryBadge extends StatelessWidget {
  const _StoreDiscoveryBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

final class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing, this.wide = true, this.onTap});
  final MarketplaceListing listing;
  final bool wide;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final location = [listing.district, listing.city]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .join('، ');
    return SizedBox(
      width: wide ? 188 : null,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(21),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 5,
              child: SizedBox(
                width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  listing.mediaPublicId == null
                      ? Container(
                          color: const Color(0xFFE1ECE5),
                          child: const Icon(Icons.image_outlined, size: 38, color: Color(0xFF578B72)),
                        )
                      : CachedMediaImage(mediaPublicId: listing.mediaPublicId!, fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Color(0x880C3429)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: 9,
                    start: 9,
                    child: _MarketplaceImageBadge(text: listing.categoryName ?? 'الحراج', icon: Icons.category_outlined),
                  ),
                  if (listing.isNegotiable)
                    const PositionedDirectional(
                      bottom: 8,
                      start: 8,
                      child: _MarketplaceImageBadge(text: 'قابل للتفاوض', icon: Icons.handshake_outlined),
                    ),
                ]),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, height: 1.2),
                  ),
                  const Spacer(),
                  Text(
                    _price(listing),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  const SizedBox(height: 5),
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 14, color: muted),
                    const SizedBox(width: 3),
                    Expanded(child: Text(location.isEmpty ? 'الموقع غير محدد' : location, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 10))),
                    const SizedBox(width: 5),
                    Icon(Icons.visibility_outlined, size: 14, color: muted),
                    const SizedBox(width: 2),
                    Text('${listing.viewCount}', style: TextStyle(color: muted, fontSize: 10)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _price(MarketplaceListing item) {
    if (item.priceAmount == null) return 'السعر عند التواصل';
    return '${item.priceAmount!.toStringAsFixed(2)} ${item.currencyCode}';
  }
}

final class _MarketplaceImageBadge extends StatelessWidget {
  const _MarketplaceImageBadge({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 115),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xD9FFFFFF), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: const Color(0xFF18513F)),
          const SizedBox(width: 4),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF18513F), fontSize: 9, fontWeight: FontWeight.w900))),
        ]),
      );
}

String _initial(String value) =>
    value.trim().isEmpty ? 'ت' : value.trim().substring(0, 1);

final class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({this.lastSyncedAt});
  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) {
    final stamp = lastSyncedAt == null
        ? ''
        : ' آخر تحديث: ${MaterialLocalizations.of(context).formatShortDate(lastSyncedAt!)}، ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(lastSyncedAt!))}.';
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2CC),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'تظهر آخر بيانات محفوظة محلياً. سيتم التحديث عند عودة الاتصال.$stamp',
            ),
          ),
        ],
      ),
    );
  }
}

final class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFDEBE8),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

final class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}
