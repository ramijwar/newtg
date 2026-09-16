import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/network/api_exception.dart';
import '../data/workspace_repository.dart';
import 'admin_catalog_page.dart';
import 'admin_commerce_page.dart';
import 'admin_activity_page.dart';
import 'admin_delivery_page.dart';
import 'admin_finance_page.dart';
import 'admin_control_strip.dart';
import 'admin_marketplace_settings_page.dart';
import 'admin_operations_page.dart';
import 'admin_queues_page.dart';
import 'admin_users_page.dart';
import 'store_banner_management_page.dart';

final class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

final class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late Future<AdminWorkspace> _future;
  bool _loaded = false;
  String? _workingId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _future = AppScope.of(context).loadAdminWorkspace();
    }
  }

  void _reload() =>
      setState(() => _future = AppScope.of(context).loadAdminWorkspace());

  Future<void> _editStore(Map<String, dynamic> item) async {
    final id = item['public_id'] as String? ?? '';
    if (id.isEmpty) return;
    final originalVerified = item['verification_status'] == 'verified';
    final originalSuspended = item['store_status'] == 'suspended';
    var isVerified = originalVerified;
    var isSuspended = originalSuspended;
    final result = await showDialog<Map<String, bool>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('تعديل ${item['name'] ?? 'المتجر'}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('التوثيق لا يغيّر تنشيط المتجر. أما الإيقاف الإداري فهو قفل لا يستطيع صاحب المتجر تجاوزه.'),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: isVerified,
                onChanged: (value) => setLocalState(() => isVerified = value),
                title: const Text('متجر موثّق'),
                subtitle: Text(isVerified ? 'تظهر علامة التوثيق للمتجر.' : 'لا تظهر علامة توثيق للمتجر.'),
              ),
              const Divider(),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: isSuspended,
                onChanged: (value) => setLocalState(() => isSuspended = value),
                title: const Text('إيقاف إداري'),
                subtitle: Text(isSuspended ? 'المتجر موقوف ولا يستطيع صاحبه تشغيله.' : 'المتجر غير مقفل إدارياً.'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, {'verified': isVerified, 'suspended': isSuspended}), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _run(
      'store-$id',
      () async {
        if (result['verified'] != originalVerified) {
          await AppScope.of(context).updateAdminStoreVerification(storeId: id, isVerified: result['verified']!);
        }
        if (result['suspended'] != originalSuspended) {
          await AppScope.of(context).setAdminStoreSuspended(storeId: id, suspended: result['suspended']!);
        }
      },
      'تم حفظ تعديلات المتجر.',
    );
  }

  Future<void> _deleteStore(Map<String, dynamic> item) async {
    final id = item['public_id'] as String? ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المتجر من العرض'),
        content: const Text('سيختفي المتجر ومنتجاته عن العملاء مع الاحتفاظ بسجلات الطلبات والتدقيق في النظام.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run('store-$id', () => AppScope.of(context).adminDeleteStore(id), 'تم حذف المتجر من العرض.');
  }

  Future<void> _deleteListing(Map<String, dynamic> item) async {
    final id = item['public_id'] as String? ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الإعلان من العرض'),
        content: const Text('سيكون الحذف منطقياً: لا تظهر الصفحة للناس، مع الاحتفاظ بالسجل الإداري والمالي.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف من العرض')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      'listing-$id',
      () => AppScope.of(context).adminDeleteListing(id),
      'تم حذف الإعلان من العرض.',
    );
  }

  Future<void> _run(
    String id,
    Future<void> Function() operation,
    String message,
  ) async {
    setState(() => _workingId = id);
    try {
      await operation();
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  Future<void> _viewVerificationDocuments(String verificationId) async {
    try {
      final files = await Future.wait([
        AppScope.of(context)
            .loadAdminVerificationMedia(verificationId, 'identity'),
        AppScope.of(context)
            .loadAdminVerificationMedia(verificationId, 'selfie'),
      ]);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('وثائق التوثيق الخاصة'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'وثيقة الهوية',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Image.memory(files[0]),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'الصورة الشخصية',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Image.memory(files[1]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _decideVerification(String id, String status) async {
    var note = '';
    if (status == 'rejected') {
      final controller = TextEditingController();
      final decision = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('سبب الرفض'),
          content: TextField(
            controller: controller,
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'اختياري، لكنه مفيد لصاحب الطلب',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      );
      note = controller.text;
      controller.dispose();
      if (decision != true || !mounted) return;
    }
    await _run(
      id,
      () => AppScope.of(context).decideVerification(
        verificationId: id,
        status: status,
        reviewerNote: note,
      ),
      status == 'verified' ? 'تم اعتماد طلب التوثيق.' : 'تم رفض طلب التوثيق.',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('لوحة الإدارة'),
      actions: [
        IconButton(
          tooltip: 'بنرات دليل المتاجر',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StoreBannerManagementPage(admin: true))),
          icon: const Icon(Icons.campaign_outlined),
        ),
        IconButton(
          tooltip: 'تحديث لوحة الإدارة',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(62),
        child: AdminControlStrip(
          active: 'dashboard',
          onDashboard: () {},
          onUsers: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AdminUsersPage()),
          ),
          onQueues: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AdminQueuesPage()),
          ),
          onCommerce: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AdminCommercePage()),
          ),
          onCatalog: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AdminCatalogPage()),
          ),
          onMarketplace: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminMarketplaceSettingsPage(),
            ),
          ),
          onDelivery: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AdminDeliveryPage()),
          ),
          onFinance: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AdminFinancePage()),
          ),
          onActivity: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AdminActivityPage()),
          ),
          onOperations: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminOperationsPage(),
            ),
          ),
        ),
      ),
    ),
    body: FutureBuilder<AdminWorkspace>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException
              ? (snapshot.error as ApiException).message
              : 'تعذر تحميل لوحة الإدارة.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }
        final data = snapshot.data!;
        final pendingListings = data.listings
            .where((item) => item['listing_status'] == 'pending_review')
            .toList();
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
            children: [
              _SummaryCard(
                stores: data.stores.length,
                listings: pendingListings.length,
                verifications: data.verifications.length,
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'طلبات توثيق الحسابات',
                empty: 'لا توجد طلبات توثيق معلقة.',
                children: data.verifications
                    .map(
                      (item) => _VerificationCard(
                        item: item,
                        busy: _workingId == item['public_id'],
                        onViewDocuments: () => _viewVerificationDocuments(
                          item['public_id'] as String,
                        ),
                        onDecision: (status) => _decideVerification(
                          item['public_id'] as String,
                          status,
                        ),
                      ),
                    )
                    .toList(),
              ),
              _Section(
                title: 'إدارة المتاجر',
                empty: 'لا توجد متاجر مطابقة للعرض.',
                children: data.stores
                    .map(
                      (item) => _StoreManagementCard(
                        item: item,
                        busy: _workingId == 'store-${item['public_id']}',
                        onDetails: () => _showRecordDetails(
                          context,
                          title: 'تفاصيل المتجر',
                          item: item,
                          labels: const {
                            'name': 'اسم المتجر',
                            'merchant_name': 'التاجر',
                            'category_name': 'التصنيف',
                            'store_status': 'حالة النشر',
                            'verification_status': 'حالة التوثيق',
                            'description': 'الوصف',
                            'public_id': 'المعرف',
                            'created_at': 'تاريخ الإنشاء',
                          },
                        ),
                        onEdit: () => _editStore(item),
                        onDelete: () => _deleteStore(item),
                      ),
                    )
                    .toList(),
              ),
              _Section(
                title: 'إدارة إعلانات الحراج',
                empty: 'لا توجد إعلانات حراج مطابقة للعرض.',
                children: data.listings
                    .map(
                      (item) {
                        final status = item['listing_status'] as String? ?? '';
                        final needsReview = status == 'pending_review';
                        return _ModerationCard(
                        title: item['title'] as String? ?? 'إعلان',
                        subtitle:
                            '${item['seller_name'] ?? ''} • ${item['price_amount'] ?? 0} ${item['currency_code'] ?? 'USD'} • ${_listingStatus(status)}',
                        mediaPublicId: item['primary_media_public_id'] as String?,
                        busy: _workingId == 'listing-${item['public_id']}',
                        onDetails: () => _showRecordDetails(
                          context,
                          title: 'تفاصيل إعلان الحراج',
                          item: item,
                          labels: const {
                            'title': 'عنوان الإعلان',
                            'seller_name': 'البائع',
                            'category_name': 'القسم',
                            'price_amount': 'السعر',
                            'currency_code': 'العملة',
                            'listing_status': 'الحالة',
                            'country_name': 'الدولة',
                            'city_name': 'المدينة',
                            'district_name': 'المنطقة',
                            'description': 'الوصف',
                            'public_id': 'المعرف',
                            'created_at': 'تاريخ الإنشاء',
                          },
                        ),
                        onApprove: !needsReview ? null : () => _run(
                          'listing-${item['public_id']}',
                          () => AppScope.of(context).updateListingReview(
                            item['public_id'] as String,
                            'active',
                          ),
                          'تم اعتماد الإعلان.',
                        ),
                        onReject: !needsReview ? null : () => _run(
                          'listing-${item['public_id']}',
                          () => AppScope.of(context).updateListingReview(
                            item['public_id'] as String,
                            'rejected',
                          ),
                          'تم رفض الإعلان.',
                        ),
                        onDelete: () => _deleteListing(item),
                        onPause: status == 'active'
                            ? () => _run(
                                'listing-${item['public_id']}',
                                () => AppScope.of(context).updateListingReview(
                                  item['public_id'] as String,
                                  'paused',
                                ),
                                'تم إيقاف الإعلان.',
                              )
                            : null,
                      );
                      },
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
    ),
  );

  String _storeStatus(String status) => switch (status) {
    'active' => 'نشط',
    'pending_review' => 'بانتظار المراجعة',
    'draft' => 'مسودة',
    'rejected' => 'مرفوض',
    'suspended' => 'معلّق',
    _ => status,
  };

  String _listingStatus(String status) => switch (status) {
    'active' => 'منشور تلقائياً',
    'pending_review' => 'بانتظار المراجعة',
    'rejected' => 'مرفوض',
    'paused' => 'متوقف',
    'sold' => 'تم البيع',
    'reserved' => 'محجوز',
    'draft' => 'مسودة',
    _ => status,
  };
}

final class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.stores,
    required this.listings,
    required this.verifications,
  });
  final int stores;
  final int listings;
  final int verifications;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(.42),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _stat(context, '$verifications', 'توثيق'),
          _stat(context, '$stores', 'متاجر'),
          _stat(context, '$listings', 'إعلانات'),
        ],
      ),
    ),
  );

  Widget _stat(BuildContext context, String number, String label) => Expanded(
    child: Column(
      children: [
        Text(
          number,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(label),
      ],
    ),
  );
}

final class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.empty,
    required this.children,
  });
  final String title;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 9),
        if (children.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(empty),
            ),
          )
        else
          ...children,
      ],
    ),
  );
}

final class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.item,
    required this.busy,
    required this.onViewDocuments,
    required this.onDecision,
  });
  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onViewDocuments;
  final ValueChanged<String> onDecision;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['full_name'] as String? ?? 'طلب توثيق',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(item['role_code'] == 'courier' ? 'عامل توصيل' : 'تاجر'),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onViewDocuments,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('الوثائق'),
              ),
              TextButton(
                onPressed: busy ? null : () => onDecision('rejected'),
                child: const Text('رفض'),
              ),
              FilledButton(
                onPressed: busy ? null : () => onDecision('verified'),
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('اعتماد'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

void _showRecordDetails(
  BuildContext context, {
  required String title,
  required Map<String, dynamic> item,
  required Map<String, String> labels,
}) {
  final rows = labels.entries
      .where((entry) => item[entry.key] != null && '${item[entry.key]}'.trim().isNotEmpty)
      .map((entry) => (label: entry.value, value: '${item[entry.key]}'))
      .toList(growable: false);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .62,
        maxChildSize: .9,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ...rows.map((row) => Card(
              child: ListTile(
                title: Text(row.label),
                subtitle: SelectableText(row.value),
              ),
            )),
            if (rows.isEmpty) const Text('لا توجد تفاصيل إضافية متاحة لهذا السجل.'),
          ],
        ),
      ),
    ),
  );
}

final class _StoreManagementCard extends StatelessWidget {
  const _StoreManagementCard({
    required this.item,
    required this.busy,
    required this.onDetails,
    required this.onEdit,
    required this.onDelete,
  });
  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final logoId = item['logo_media_public_id'] as String?;
    final verified = item['verification_status'] == 'verified';
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
        leading: ClipOval(
          child: SizedBox(
            width: 48,
            height: 48,
            child: logoId == null || logoId.isEmpty
                ? ColoredBox(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.storefront_outlined, color: Theme.of(context).colorScheme.primary),
                  )
                : CachedMediaImage(mediaPublicId: logoId, errorIcon: Icons.storefront_outlined),
          ),
        ),
        title: Text(item['name'] as String? ?? 'متجر', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${item['merchant_name'] ?? 'تاجر'} • ${item['category_name'] ?? 'بدون تصنيف'}\n'
            "${item['store_status'] == 'active' ? 'نشط' : item['store_status'] ?? '—'} • ${verified ? 'موثّق' : 'غير موثّق'}",
          ),
        ),
        isThreeLine: true,
        onTap: busy ? null : onDetails,
        trailing: busy
            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : PopupMenuButton<String>(
                tooltip: 'إدارة المتجر',
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('تعديل'))),
                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('حذف'))),
                ],
              ),
      ),
    );
  }
}

final class _ModerationCard extends StatelessWidget {
  const _ModerationCard({
    required this.title,
    required this.subtitle,
    required this.busy,
    this.onApprove,
    this.onReject,
    this.onDetails,
    this.onPause,
    this.onDelete,
    this.mediaPublicId,
  });
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onDetails;
  final VoidCallback? onPause;
  final VoidCallback? onDelete;
  final String? mediaPublicId;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mediaPublicId != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: CachedMediaImage(mediaPublicId: mediaPublicId!),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(subtitle),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              if (onDetails != null)
                TextButton(
                  onPressed: busy ? null : onDetails,
                  child: const Text('تفاصيل'),
                ),
              if (onReject != null)
                TextButton(
                  onPressed: busy ? null : onReject,
                  child: const Text('رفض'),
                ),
              if (onPause != null)
                TextButton(
                  onPressed: busy ? null : onPause,
                  child: const Text('تعليق'),
                ),
              if (onDelete != null)
                TextButton(
                  onPressed: busy ? null : onDelete,
                  child: const Text('حذف من العرض'),
                ),
              if (onApprove != null)
                FilledButton(
                  onPressed: busy ? null : onApprove,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('اعتماد'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
