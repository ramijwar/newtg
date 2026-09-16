import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/network/api_exception.dart';
import 'admin_navigation.dart';

/// Cross-store control surface for records that were previously only visible
/// through individual merchant pages or the payment queue.
final class AdminCommercePage extends StatefulWidget {
  const AdminCommercePage({super.key});

  @override
  State<AdminCommercePage> createState() => _AdminCommercePageState();
}

final class _AdminCommercePageState extends State<AdminCommercePage> {
  late Future<List<Map<String, dynamic>>> _stores;
  late Future<List<Map<String, dynamic>>> _products;
  late Future<List<Map<String, dynamic>>> _orders;
  late Future<List<Map<String, dynamic>>> _payments;
  bool _ready = false;
  String? _working;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready) {
      _ready = true;
      _reload();
    }
  }

  void _reload() => setState(() {
        final controller = AppScope.of(context);
        _stores = controller.loadAdminStores();
        _products = controller.loadAdminProducts();
        _orders = controller.loadAdminOrders();
        _payments = controller.loadAdminManualPaymentLog();
      });

  Future<void> _run(
    String key,
    Future<void> Function() operation,
    String success,
  ) async {
    setState(() => _working = key);
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      _reload();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('متابعة')),
          ],
        ),
      ) ??
      false;

  Future<void> _editStore(Map<String, dynamic> store) async {
    final id = store['public_id'] as String? ?? '';
    if (id.isEmpty) return;
    final originalVerified = store['verification_status'] == 'verified';
    final originalSuspended = store['store_status'] == 'suspended';
    var verified = originalVerified;
    var suspended = originalSuspended;
    final result = await showDialog<Map<String, bool>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('تعديل ${store['name'] ?? 'المتجر'}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('التوثيق مستقل عن التنشيط. الإيقاف الإداري قفل لا يستطيع التاجر تجاوزه.'),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: verified,
                onChanged: (value) => setLocalState(() => verified = value),
                title: const Text('متجر موثّق'),
                subtitle: Text(verified ? 'علامة التوثيق مفعلة.' : 'علامة التوثيق معطلة.'),
              ),
              const Divider(),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: suspended,
                onChanged: (value) => setLocalState(() => suspended = value),
                title: const Text('إيقاف إداري'),
                subtitle: Text(suspended ? 'لا يستطيع صاحب المتجر إعادة تشغيله.' : 'المتجر غير مقفل إدارياً.'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, {'verified': verified, 'suspended': suspended}), child: const Text('حفظ')),
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

  Future<void> _deleteStore(Map<String, dynamic> store) async {
    final id = store['public_id'] as String? ?? '';
    if (id.isEmpty) return;
    if (await _confirm('حذف المتجر', 'سيختفي المتجر ومنتجاته عن العملاء، مع الاحتفاظ بسجلات الطلبات والتدقيق.')) {
      await _run('store-$id', () => AppScope.of(context).adminDeleteStore(id), 'تم حذف المتجر من العرض.');
    }
  }

  Future<String?> _reason(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'السبب الذي سيحفظ في سجل الطلب'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.length >= 2) Navigator.pop(context, reason);
            },
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  String _storeStatus(String status) => switch (status) {
    'active' => 'نشط',
    'draft' => 'مسودة',
    'suspended' => 'معلّق',
    'rejected' => 'مرفوض',
    'pending_review' => 'بانتظار المراجعة',
    _ => status.isEmpty ? 'غير محدد' : status,
  };

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('المتاجر والمنتجات والطلبات'),
            actions: [
              IconButton(
                tooltip: 'تحديث كل البيانات',
                onPressed: _working == null ? _reload : null,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            bottom: adminTabbedBottom(
              context,
              'commerce',
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.storefront_outlined), text: 'المتاجر'),
                  Tab(icon: Icon(Icons.inventory_2_outlined), text: 'المنتجات'),
                  Tab(icon: Icon(Icons.receipt_long_outlined), text: 'الطلبات'),
                  Tab(icon: Icon(Icons.payments_outlined), text: 'سجل الدفع'),
                ],
              ),
            ),
          ),
          body: TabBarView(children: [_storesTab(), _productsTab(), _ordersTab(), _paymentsTab()]),
        ),
      );

  Widget _storesTab() => _AdminList(
        future: _stores,
        empty: 'لا توجد متاجر للعرض.',
        searchHint: 'ابحث باسم المتجر أو التاجر أو التصنيف',
        fields: const ['name', 'merchant_name', 'category_name', 'store_status'],
        itemBuilder: (item) {
          final id = item['public_id'] as String? ?? '';
          return _AdminEntityCard(
            icon: Icons.storefront_outlined,
            title: item['name'] as String? ?? 'متجر',
            summary: '${item['merchant_name'] ?? 'تاجر'} · ${item['category_name'] ?? 'بدون تصنيف'}\n${_storeStatus(item['store_status'] as String? ?? '')} · ${item['verification_status'] == 'verified' ? 'موثّق' : 'غير موثّق'}',
            item: item,
            detailTitle: 'تفاصيل المتجر',
            loadDetails: id.isEmpty ? null : () async {
              final data = await AppScope.of(context).loadAdminStoreDetail(id);
              return {...Map<String, dynamic>.from(data['store'] as Map? ?? const {}), 'store_products': data['products'] ?? const [], 'store_orders': data['orders'] ?? const [], 'store_reviews': data['reviews'] ?? const [], 'latest_verification': data['latest_verification']};
            },
            busy: _working == 'store-$id',
            menu: id.isEmpty
                ? const []
                : [
                    _Action('تعديل', Icons.edit_outlined, () => _editStore(item)),
                    _Action('حذف', Icons.delete_outline, () => _deleteStore(item)),
                  ],
          );
        },
      );

  Widget _productsTab() => _AdminList(
        future: _products,
        empty: 'لا توجد منتجات للعرض.',
        searchHint: 'ابحث باسم المنتج أو المتجر أو SKU',
        fields: const ['name', 'store_name', 'merchant_name', 'sku', 'product_status'],
        filterField: 'product_status',
        filterLabel: 'حالة المنتج',
        filterOptions: const {'draft': 'مسودة', 'active': 'نشط', 'hidden': 'مخفي', 'archived': 'مؤرشف'},
        itemBuilder: (item) {
          final id = item['public_id'] as String? ?? '';
          final stock = item['stock_quantity'] ?? 0;
          return _AdminEntityCard(
            icon: Icons.inventory_2_outlined,
            title: item['name'] as String? ?? 'منتج',
            summary: '${item['store_name'] ?? 'متجر'} · ${item['price'] ?? 0} ${item['currency_code'] ?? ''}\nالمخزون: $stock · الحالة: ${item['product_status'] ?? '—'}',
            item: item,
            detailTitle: 'تفاصيل المنتج',
            loadDetails: id.isEmpty ? null : () => AppScope.of(context).loadAdminProductDetail(id),
            busy: _working == 'product-$id',
            menu: id.isEmpty
                ? const []
                : [
                    _Action('إظهار المنتج', Icons.visibility_outlined, () => _run('product-$id', () => AppScope.of(context).updateAdminProductStatus(productId: id, status: 'active'), 'تم نشر المنتج.')),
                    _Action('إخفاء المنتج', Icons.visibility_off_outlined, () => _run('product-$id', () => AppScope.of(context).updateAdminProductStatus(productId: id, status: 'hidden'), 'تم إخفاء المنتج.')),
                    _Action('أرشفة المنتج', Icons.archive_outlined, () => _run('product-$id', () => AppScope.of(context).updateAdminProductStatus(productId: id, status: 'archived'), 'تمت أرشفة المنتج.')),
                    _Action('حذف منطقي', Icons.delete_outline, () async {
                      if (await _confirm('حذف المنتج من العرض', 'سيُحذف المنتج من العرض فقط ويحافظ الخادم على السجلات المالية السابقة.')) {
                        _run('product-$id', () => AppScope.of(context).adminDeleteProduct(id), 'تم حذف المنتج من العرض.');
                      }
                    }),
                  ],
          );
        },
      );

  Widget _paymentsTab() => _AdminList(
        future: _payments,
        empty: 'لا توجد إشعارات دفع يدوي في السجل.',
        searchHint: 'ابحث بالطلب أو المتجر أو العميل أو رقم الفاتورة',
        fields: const ['order_number', 'store_name', 'customer_name', 'customer_phone', 'invoice_number', 'payment_status'],
        filterField: 'payment_status',
        filterLabel: 'حالة إشعار الدفع',
        filterOptions: const {'submitted': 'قيد مراجعة التاجر', 'merchant_approved': 'اعتمد التاجر', 'rejected': 'مرفوض', 'admin_approved': 'سجل تاريخي'},
        itemBuilder: (item) => _AdminEntityCard(
          icon: item['order_payment_status'] == 'paid' ? Icons.verified_rounded : Icons.payments_outlined,
          title: item['order_number'] as String? ?? 'إشعار دفع',
          summary: '${item['store_name'] ?? 'متجر'} ← ${item['customer_name'] ?? 'عميل'}\n${item['order_payment_status'] == 'paid' ? 'تم الدفع' : item['payment_status'] ?? '—'} · ${item['amount'] ?? 0} ${item['currency_code'] ?? ''}${item['invoice_number'] != null ? ' · فاتورة ${item['invoice_number']}' : ''}',
          item: item,
          detailTitle: 'سجل إشعار الدفع',
          loadDetails: () async => item,
          busy: false,
          menu: const [],
        ),
      );

  Widget _ordersTab() => _AdminList(
        future: _orders,
        empty: 'لا توجد طلبات للعرض.',
        searchHint: 'ابحث برقم الطلب أو العميل أو المتجر',
        fields: const ['order_number', 'store_name', 'customer_name', 'customer_phone', 'order_status', 'payment_status'],
        filterField: 'order_status',
        filterLabel: 'حالة الطلب',
        filterOptions: const {'awaiting_payment': 'بانتظار الدفع', 'payment_review': 'مراجعة الدفع', 'payment_rejected': 'دفع مرفوض', 'payment_verified': 'دفع معتمد', 'merchant_accepted': 'مقبول', 'preparing': 'تحضير', 'ready_for_delivery': 'جاهز للتوصيل', 'assigned_to_courier': 'مسند لعامل', 'picked_up': 'تم الاستلام', 'out_for_delivery': 'في الطريق', 'delivered': 'تم التسليم', 'completed': 'مكتمل', 'cancelled': 'ملغي', 'disputed': 'نزاع'},
        itemBuilder: (item) {
          final id = item['public_id'] as String? ?? '';
          final status = item['order_status'] as String? ?? '';
          final cancellable = !['completed', 'cancelled', 'delivered'].contains(status);
          return _AdminEntityCard(
            icon: Icons.receipt_long_outlined,
            title: item['order_number'] as String? ?? 'طلب',
            summary: '${item['store_name'] ?? 'متجر'} ← ${item['customer_name'] ?? 'عميل'}\n${item['total_amount'] ?? 0} ${item['currency_code'] ?? ''} · $status · دفع: ${item['payment_status'] ?? '—'}',
            item: item,
            detailTitle: 'تفاصيل الطلب',
            loadDetails: id.isEmpty ? null : () => AppScope.of(context).loadAdminOrderDetail(id),
            busy: _working == 'order-$id',
            menu: id.isEmpty || !cancellable
                ? const []
                : [
                    _Action('إلغاء إداري موثق', Icons.cancel_outlined, () async {
                      final reason = await _reason('إلغاء ${item['order_number'] ?? 'الطلب'}');
                      if (reason != null) {
                        _run('order-$id', () => AppScope.of(context).cancelAdminOrder(orderId: id, reason: reason), 'تم إلغاء الطلب وتوثيق السبب.');
                      }
                    }),
                  ],
          );
        },
      );
}

final class _AdminList extends StatefulWidget {
  const _AdminList({
    required this.future,
    required this.empty,
    required this.searchHint,
    required this.fields,
    required this.itemBuilder,
    this.filterField,
    this.filterLabel,
    this.filterOptions = const {},
  });
  final Future<List<Map<String, dynamic>>> future;
  final String empty;
  final String searchHint;
  final List<String> fields;
  final Widget Function(Map<String, dynamic>) itemBuilder;
  final String? filterField;
  final String? filterLabel;
  final Map<String, String> filterOptions;

  @override
  State<_AdminList> createState() => _AdminListState();
}

final class _AdminListState extends State<_AdminList> {
  String _query = '';
  String _selectedFilter = '';

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: widget.future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تعذر تحميل البيانات.';
            return Center(child: Text(message, textAlign: TextAlign.center));
          }
          final all = snapshot.data ?? const <Map<String, dynamic>>[];
          final query = _query.trim().toLowerCase();
          final filtered = widget.filterField == null || _selectedFilter.isEmpty ? all : all.where((item) => '${item[widget.filterField] ?? ''}' == _selectedFilter).toList(growable: false);
          final items = query.isEmpty ? filtered : filtered.where((item) => widget.fields.any((field) => '${item[field] ?? ''}'.toLowerCase().contains(query))).toList(growable: false);
          return Column(
            children: [
              if (widget.filterOptions.isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DropdownButtonFormField<String>(
                  value: _selectedFilter,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: widget.filterLabel ?? 'تصفية'),
                  items: [const DropdownMenuItem(value: '', child: Text('كل الحالات')), ...widget.filterOptions.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))],
                  onChanged: (value) => setState(() => _selectedFilter = value ?? ''),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: widget.searchHint),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(18, 0, 18, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('${items.length} سجل ظاهر', style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(child: Text(query.isEmpty ? widget.empty : 'لا توجد نتائج مطابقة.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, index) => widget.itemBuilder(items[index]),
                      ),
              ),
            ],
          );
        },
      );
}

final class _Action {
  const _Action(this.label, this.icon, this.run);
  final String label;
  final IconData icon;
  final Future<void> Function() run;
}

final class _AdminEntityCard extends StatelessWidget {
  const _AdminEntityCard({
    required this.icon,
    required this.title,
    required this.summary,
    required this.item,
    required this.detailTitle,
    this.loadDetails,
    required this.busy,
    required this.menu,
  });
  final IconData icon;
  final String title;
  final String summary;
  final Map<String, dynamic> item;
  final String detailTitle;
  final Future<Map<String, dynamic>> Function()? loadDetails;
  final bool busy;
  final List<_Action> menu;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(summary, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: () async {
                        final loader = loadDetails;
                        if (loader == null) {
                          _showDetails(context, title: detailTitle, item: item);
                        } else {
                          await _loadRemoteDetails(context, title: detailTitle, loader: loader);
                        }
                      },
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label: const Text('عرض التفاصيل'),
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(padding: EdgeInsets.all(10), child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              else if (menu.isNotEmpty)
                PopupMenuButton<_Action>(
                  tooltip: 'إجراءات الإدارة',
                  onSelected: (action) => action.run(),
                  itemBuilder: (_) => menu.map((action) => PopupMenuItem(value: action, child: ListTile(leading: Icon(action.icon), title: Text(action.label)))).toList(growable: false),
                ),
            ],
          ),
        ),
      );
}

Future<void> _loadRemoteDetails(
  BuildContext context, {
  required String title,
  required Future<Map<String, dynamic>> Function() loader,
}) async {
  try {
    final item = await loader();
    if (context.mounted) _showDetails(context, title: title, item: item);
  } on ApiException catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تحميل التفاصيل الكاملة.')));
  }
}

void _showDetails(BuildContext context, {required String title, required Map<String, dynamic> item}) {
  const labels = {
    'public_id': 'المعرف', 'name': 'الاسم', 'description': 'الوصف', 'sku': 'رمز المنتج', 'price': 'السعر', 'cost_price': 'سعر التكلفة', 'sale_price': 'سعر التخفيض',
    'sale_starts_at': 'بداية التخفيض', 'sale_ends_at': 'نهاية التخفيض', 'currency_code': 'العملة', 'stock_quantity': 'المخزون', 'low_stock_threshold': 'حد التنبيه', 'product_status': 'حالة المنتج',
    'store_name': 'المتجر', 'store_public_id': 'معرف المتجر', 'store_status': 'حالة المتجر', 'merchant_name': 'التاجر', 'merchant_public_id': 'معرف التاجر',
    'category_name': 'التصنيف', 'category_public_id': 'معرف التصنيف', 'view_count': 'المشاهدات', 'order_number': 'رقم الطلب', 'order_status': 'حالة الطلب',
    'payment_status': 'حالة الدفع', 'payment_method': 'طريقة الدفع', 'fulfillment_type': 'نوع الاستلام', 'customer_name': 'العميل',
    'customer_public_id': 'معرف العميل', 'customer_phone': 'هاتف العميل', 'customer_note': 'ملاحظة العميل', 'subtotal_amount': 'الإجمالي الفرعي', 'delivery_fee_amount': 'رسوم التوصيل',
    'platform_fee_amount': 'رسوم المنصة', 'total_amount': 'الإجمالي', 'item_count': 'عدد العناصر', 'placed_at': 'وقت الطلب',
    'invoice_number': 'رقم الفاتورة', 'enabled': 'التحويل اليدوي مفعّل', 'deposit_title': 'عنوان الإيداع', 'deposit_address': 'تفاصيل الإيداع', 'instructions': 'تعليمات العميل', 'payment_public_id': 'معرف إشعار الدفع', 'order_public_id': 'معرف الطلب', 'payer_note': 'إشعار العميل الكتابي', 'transfer_reference': 'مرجع التحويل', 'amount': 'مبلغ الإشعار', 'has_receipt': 'يتضمن صورة إيصال', 'submitted_at': 'وقت الإرسال', 'merchant_reviewer_name': 'التاجر المراجع', 'merchant_reviewed_at': 'وقت قرار التاجر', 'merchant_note': 'ملاحظة التاجر', 'order_payment_status': 'حالة دفع الطلب',
    'created_at': 'تاريخ الإنشاء', 'updated_at': 'آخر تحديث', 'cancelled_at': 'وقت الإلغاء',
  };
  final media = (item['media'] as List? ?? const []).whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList(growable: false);
  final lines = (item['items'] as List? ?? const []).whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList(growable: false);
  final history = (item['history'] as List? ?? const []).whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList(growable: false);
  final storeProducts = (item['store_products'] as List? ?? const []).whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList(growable: false);
  final storeOrders = (item['store_orders'] as List? ?? const []).whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList(growable: false);
  final storeReviews = (item['store_reviews'] as List? ?? const []).whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList(growable: false);
  final verification = item['latest_verification'] is Map ? Map<String, dynamic>.from(item['latest_verification'] as Map) : null;
  final basicRows = item.entries.where((entry) => entry.value != null && entry.value is! List && entry.value is! Map && '${entry.value}'.trim().isNotEmpty).map((entry) => (label: labels[entry.key] ?? entry.key, value: '${entry.value}')).toList(growable: false);
  Widget mapBlock(String heading, Map<String, dynamic>? values) {
    if (values == null || values.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16), Text(heading, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 6),
      ...values.entries.where((entry) => entry.value != null && '${entry.value}'.trim().isNotEmpty).map((entry) => Card(child: ListTile(title: Text(labels[entry.key] ?? entry.key), subtitle: SelectableText('${entry.value}')))),
    ]);
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        maxChildSize: .94,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
          children: [
            Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ...basicRows.map((row) => Card(child: ListTile(title: Text(row.label), subtitle: SelectableText(row.value)))),
            if (media.isNotEmpty) ...[
              const SizedBox(height: 16), Text('صور المنتج', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: media.where((entry) => entry['public_id'] is String).map((entry) => ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 112, height: 112, child: CachedMediaImage(mediaPublicId: entry['public_id'] as String)))).toList(growable: false)),
            ],
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 16), Text('عناصر الطلب', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 6),
              ...lines.map((line) => Card(child: ListTile(title: Text(line['product_name_snapshot'] as String? ?? 'منتج'), subtitle: Text('${line['quantity'] ?? 0} × ${line['unit_price_amount'] ?? 0} · ${line['sku_snapshot'] ?? 'دون SKU'}'), trailing: Text('${line['line_total_amount'] ?? 0}')))),
            ],
            mapBlock('إعدادات التحويل اليدوي الحالية', item['manual_payment'] is Map ? Map<String, dynamic>.from(item['manual_payment'] as Map) : null),
            mapBlock('لقطة المتجر وقت الطلب', item['store_snapshot'] is Map ? Map<String, dynamic>.from(item['store_snapshot'] as Map) : null),
            mapBlock('تعليمات الإيداع وقت الطلب', item['manual_payment_snapshot'] is Map ? Map<String, dynamic>.from(item['manual_payment_snapshot'] as Map) : item['deposit_snapshot'] is Map ? Map<String, dynamic>.from(item['deposit_snapshot'] as Map) : null),
            mapBlock('تفاصيل إشعار الدفع', item['payment'] is Map ? Map<String, dynamic>.from(item['payment'] as Map) : null),
            mapBlock('عنوان التسليم وقت الطلب', item['delivery_address'] is Map ? Map<String, dynamic>.from(item['delivery_address'] as Map) : null),
            mapBlock('آخر توثيق للتاجر', verification),
            if (storeProducts.isNotEmpty) ...[const SizedBox(height: 16), Text('منتجات المتجر (${storeProducts.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)), ...storeProducts.map((row) => Card(child: ListTile(title: Text(row['name'] as String? ?? 'منتج'), subtitle: Text('${row['price'] ?? 0} ${row['currency_code'] ?? ''} · مخزون ${row['stock_quantity'] ?? 0} · ${row['product_status'] ?? '—'}'))))],
            if (storeOrders.isNotEmpty) ...[const SizedBox(height: 16), Text('الطلبات الأخيرة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)), ...storeOrders.map((row) => Card(child: ListTile(title: Text(row['order_number'] as String? ?? 'طلب'), subtitle: Text(
              '${row['customer_name'] ?? 'عميل'} · ${row['total_amount'] ?? 0} ${row['currency_code'] ?? ''}\n'
              "${row['order_status'] ?? '—'} · دفع: ${row['payment_status'] ?? '—'}",
            ))))],
            if (storeReviews.isNotEmpty) ...[const SizedBox(height: 16), Text('التقييمات الأخيرة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)), ...storeReviews.map((row) => Card(child: ListTile(title: Text('${row['customer_name'] ?? 'عميل'} · ${row['rating'] ?? 0}/5'), subtitle: Text(row['comment'] as String? ?? 'دون تعليق'))))],
            if (history.isNotEmpty) ...[
              const SizedBox(height: 16), Text('سجل حالة إشعار الدفع', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 6),
              ...history.map((entry) => Card(child: ListTile(title: Text('${entry['from_status'] ?? 'بداية'} ← ${entry['to_status'] ?? '—'}'), subtitle: Text('${entry['actor_name'] ?? 'النظام'} · ${entry['created_at'] ?? ''}\n${entry['note'] ?? ''}')))),
            ],
            if ((item['payment_history'] as List? ?? const []).isNotEmpty) ...[
              const SizedBox(height: 16), Text('سجل مراجعة الدفع', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              ...((item['payment_history'] as List? ?? const []).whereType<Map>().map((entry) => Card(child: ListTile(title: Text('${entry['from_status'] ?? 'بداية'} ← ${entry['to_status'] ?? '—'}'), subtitle: Text('${entry['actor_name'] ?? 'النظام'} · ${entry['created_at'] ?? ''}\n${entry['note'] ?? ''}'))))),
            ],
          ],
        ),
      ),
    ),
  );
}
