import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import 'admin_navigation.dart';

/// Supervision for courier identities and both store-order and marketplace
/// delivery tasks. Private proofs are fetched as authenticated bytes only.
final class AdminDeliveryPage extends StatefulWidget {
  const AdminDeliveryPage({super.key});

  @override
  State<AdminDeliveryPage> createState() => _AdminDeliveryPageState();
}

final class _AdminDeliveryPageState extends State<AdminDeliveryPage> {
  late Future<List<Map<String, dynamic>>> _couriers;
  late Future<List<Map<String, dynamic>>> _tasks;
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
        _couriers = controller.loadAdminCouriers();
        _tasks = controller.loadAdminDeliveryTasks();
      });

  Future<void> _run(String key, Future<void> Function() operation, String message) async {
    setState(() => _working = key);
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      _reload();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _showCourier(String id) async {
    try {
      final data = await AppScope.of(context).loadAdminCourierDetail(id);
      if (!mounted) return;
      final courier = Map<String, dynamic>.from(data['courier'] as Map? ?? const {});
      final tasks = (data['tasks'] as List? ?? const []).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(growable: false);
      final verification = data['latest_verification'] is Map ? Map<String, dynamic>.from(data['latest_verification'] as Map) : null;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _DetailSheet(
          title: 'تفاصيل عامل التوصيل',
          sections: [
            _detailSection('بيانات الحساب', courier, const {
              'full_name': 'الاسم', 'username': 'اسم المستخدم', 'phone': 'الهاتف', 'account_status': 'حالة الحساب',
              'verification_status': 'حالة التوثيق', 'work_status': 'حالة العمل', 'task_count': 'إجمالي المهام',
              'active_task_count': 'المهام النشطة', 'last_task_at': 'آخر مهمة', 'created_at': 'تاريخ الانضمام', 'last_login_at': 'آخر دخول',
            }),
            if (verification != null) _detailSection('آخر طلب توثيق', verification, const {
              'public_id': 'المعرف', 'verification_status': 'الحالة', 'reviewer_note': 'ملاحظة المراجع', 'created_at': 'تاريخ الإرسال', 'reviewed_at': 'تاريخ المراجعة',
            }),
            if (tasks.isNotEmpty) _taskListSection('المهام المرتبطة', tasks),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _showTask(String id) async {
    try {
      final data = await AppScope.of(context).loadAdminDeliveryTaskDetail(id);
      if (!mounted) return;
      final task = Map<String, dynamic>.from(data['task'] as Map? ?? const {});
      final history = (data['history'] as List? ?? const []).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(growable: false);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _DetailSheet(
          title: 'تفاصيل مهمة التوصيل',
          sections: [
            _detailSection('المهمة والصفقة', task, const {
              'public_id': 'معرف المهمة', 'source_type': 'مصدر المهمة', 'source_label': 'المرجع', 'order_public_id': 'معرف الطلب', 'order_number': 'رقم الطلب',
              'transaction_public_id': 'معرف صفقة الحراج', 'transaction_status': 'حالة الصفقة', 'task_status': 'حالة المهمة',
              'courier_name': 'عامل التوصيل', 'courier_phone': 'هاتف العامل', 'customer_name': 'العميل/المشتري', 'seller_name': 'البائع/التاجر',
              'store_name': 'المتجر', 'delivery_fee_amount': 'رسم التوصيل', 'courier_earning_amount': 'استحقاق العامل', 'currency_code': 'العملة',
              'delivery_distance_km': 'المسافة كم', 'delivery_base_fee_amount': 'الرسم الأساسي', 'delivery_per_km_fee_amount': 'رسم كل كم',
              'accepted_at': 'وقت القبول', 'picked_up_at': 'وقت الاستلام', 'delivered_at': 'وقت التسليم', 'completed_at': 'وقت الإكمال', 'created_at': 'تاريخ الإنشاء', 'updated_at': 'آخر تحديث',
            }),
            _detailSection('عنوان الاستلام', task['pickup_address'] is Map ? Map<String, dynamic>.from(task['pickup_address'] as Map) : const {}, const {}),
            _detailSection('عنوان التسليم', task['delivery_address'] is Map ? Map<String, dynamic>.from(task['delivery_address'] as Map) : const {}, const {}),
            if (task['pickup_proof_media_public_id'] != null || task['delivery_proof_media_public_id'] != null)
              _proofSection(task),
            if (history.isNotEmpty) _historySection(history),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _showProof(String taskId, String proofType) async {
    try {
      final Uint8List bytes = await AppScope.of(context).loadAdminDeliveryTaskProof(taskId: taskId, proofType: proofType);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(proofType == 'pickup' ? 'إثبات استلام الطلب' : 'إثبات تسليم الطلب'),
          content: InteractiveViewer(child: Image.memory(bytes)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('عمال التوصيل والمهام'),
            actions: [IconButton(onPressed: _working == null ? _reload : null, tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded))],
            bottom: adminTabbedBottom(
              context,
              'delivery',
              const TabBar(tabs: [Tab(icon: Icon(Icons.delivery_dining_outlined), text: 'عمال التوصيل'), Tab(icon: Icon(Icons.route_outlined), text: 'المهام')]),
            ),
          ),
          body: TabBarView(children: [_couriersTab(), _tasksTab()]),
        ),
      );

  Widget _couriersTab() => _SearchList(
        future: _couriers,
        empty: 'لا يوجد عامل توصيل مسجل.',
        hint: 'ابحث بالاسم أو اسم المستخدم أو الهاتف',
        matches: (item, text) => '${item['full_name'] ?? ''} ${item['username'] ?? ''} ${item['phone'] ?? ''} ${item['verification_status'] ?? ''} ${item['work_status'] ?? ''}'.toLowerCase().contains(text),
        filters: const {
          'verification_status': {'not_submitted': 'دون توثيق', 'pending': 'قيد المراجعة', 'verified': 'موثق', 'rejected': 'مرفوض'},
          'work_status': {'offline': 'غير متصل', 'available': 'متاح', 'busy': 'مشغول', 'suspended': 'معلق'},
        },
        builder: (item) {
          final id = item['public_id'] as String? ?? '';
          final busy = _working == 'courier-$id';
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.delivery_dining_outlined)),
              title: Text(item['full_name'] as String? ?? 'عامل توصيل', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${item['phone'] ?? '—'}\nتوثيق: ${item['verification_status'] ?? '—'} · عمل: ${item['work_status'] ?? '—'} · مهام نشطة: ${item['active_task_count'] ?? 0}'),
              isThreeLine: true,
              onTap: id.isEmpty ? null : () => _showCourier(id),
              trailing: busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)) : PopupMenuButton<String>(
                tooltip: 'إجراءات العامل',
                onSelected: (value) {
                  if (value.startsWith('verify:')) _run('courier-$id', () => AppScope.of(context).updateAdminCourierVerification(courierId: id, status: value.substring(7)), 'تم تحديث توثيق العامل.');
                  if (value.startsWith('work:')) _run('courier-$id', () => AppScope.of(context).updateAdminCourierWorkStatus(courierId: id, status: value.substring(5)), 'تم تحديث حالة عمل العامل.');
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'verify:verified', child: Text('اعتماد التوثيق')),
                  PopupMenuItem(value: 'verify:pending', child: Text('إعادة التوثيق إلى المراجعة')),
                  PopupMenuItem(value: 'verify:rejected', child: Text('رفض التوثيق')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'work:available', child: Text('جعله متاحاً')),
                  PopupMenuItem(value: 'work:offline', child: Text('جعله غير متصل')),
                  PopupMenuItem(value: 'work:suspended', child: Text('تعليق عمله')),
                ],
              ),
            ),
          );
        },
      );

  Widget _tasksTab() => _SearchList(
        future: _tasks,
        empty: 'لا توجد مهام توصيل.',
        hint: 'ابحث برقم الطلب أو الصفقة أو العامل أو العميل',
        matches: (item, text) => '${item['source_label'] ?? ''} ${item['courier_name'] ?? ''} ${item['customer_name'] ?? ''} ${item['seller_name'] ?? ''} ${item['task_status'] ?? ''}'.toLowerCase().contains(text),
        filters: const {
          'source_type': {'store_order': 'طلب متجر', 'marketplace_transaction': 'صفقة حراج'},
          'task_status': {'available': 'متاحة', 'accepted': 'مقبولة', 'en_route_pickup': 'إلى الاستلام', 'picked_up': 'تم الاستلام', 'en_route_delivery': 'إلى التسليم', 'delivered': 'تم التسليم', 'completed': 'مكتملة', 'cancelled': 'ملغاة'},
        },
        builder: (item) {
          final id = item['public_id'] as String? ?? '';
          final source = item['source_type'] == 'marketplace_transaction' ? 'حراج' : 'طلب متجر';
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(source == 'حراج' ? Icons.storefront_outlined : Icons.receipt_long_outlined)),
              title: Text(item['source_label'] as String? ?? 'مهمة توصيل', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('$source · ${item['task_status'] ?? '—'}\n${item['courier_name'] ?? 'غير مسندة'} · ${item['delivery_fee_amount'] ?? 0} ${item['currency_code'] ?? ''}'),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: id.isEmpty ? null : () => _showTask(id),
            ),
          );
        },
      );

  Widget _proofSection(Map<String, dynamic> task) {
    final id = task['public_id'] as String? ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      Text('إثباتات المهمة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        if (task['pickup_proof_media_public_id'] != null) OutlinedButton.icon(onPressed: () => _showProof(id, 'pickup'), icon: const Icon(Icons.inventory_2_outlined), label: const Text('إثبات الاستلام')),
        if (task['delivery_proof_media_public_id'] != null) OutlinedButton.icon(onPressed: () => _showProof(id, 'delivery'), icon: const Icon(Icons.task_alt_outlined), label: const Text('إثبات التسليم')),
      ]),
    ]);
  }
}

final class _SearchList extends StatefulWidget {
  const _SearchList({required this.future, required this.empty, required this.hint, required this.matches, required this.builder, this.filters = const {}});
  final Future<List<Map<String, dynamic>>> future;
  final String empty;
  final String hint;
  final bool Function(Map<String, dynamic>, String) matches;
  final Widget Function(Map<String, dynamic>) builder;
  final Map<String, Map<String, String>> filters;

  @override
  State<_SearchList> createState() => _SearchListState();
}

final class _SearchListState extends State<_SearchList> {
  String _search = '';
  final Map<String, String> _filterValues = {};
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: widget.future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text(snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تعذر تحميل البيانات.'));
          final all = snapshot.data ?? const <Map<String, dynamic>>[];
          final query = _search.trim().toLowerCase();
          final byFilters = all.where((item) => _filterValues.entries.every((filter) => filter.value.isEmpty || '${item[filter.key] ?? ''}' == filter.value)).toList(growable: false);
          final items = query.isEmpty ? byFilters : byFilters.where((item) => widget.matches(item, query)).toList(growable: false);
          return Column(children: [
            if (widget.filters.isNotEmpty) Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(spacing: 8, runSpacing: 8, children: widget.filters.entries.map((filter) => SizedBox(width: 176, child: DropdownButtonFormField<String>(
                value: _filterValues[filter.key] ?? '', isExpanded: true, decoration: InputDecoration(labelText: filter.key == 'source_type' ? 'مصدر المهمة' : filter.key == 'task_status' ? 'حالة المهمة' : filter.key == 'work_status' ? 'حالة العمل' : 'التوثيق'),
                items: [const DropdownMenuItem(value: '', child: Text('الكل')), ...filter.value.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))],
                onChanged: (value) => setState(() => _filterValues[filter.key] = value ?? ''),
              ))).toList(growable: false)),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 6), child: TextField(onChanged: (value) => setState(() => _search = value), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: widget.hint))),
            Padding(padding: const EdgeInsetsDirectional.fromSTEB(18, 0, 18, 8), child: Align(alignment: AlignmentDirectional.centerStart, child: Text('${items.length} سجل ظاهر', style: Theme.of(context).textTheme.bodySmall))),
            Expanded(child: items.isEmpty ? Center(child: Text(query.isEmpty ? widget.empty : 'لا توجد نتائج مطابقة.')) : ListView.separated(padding: const EdgeInsets.fromLTRB(16, 2, 16, 28), itemCount: items.length, itemBuilder: (_, index) => widget.builder(items[index]), separatorBuilder: (_, _) => const SizedBox(height: 8))),
          ]);
        },
      );
}

final class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.title, required this.sections});
  final String title;
  final List<Widget> sections;
  @override
  Widget build(BuildContext context) => SafeArea(child: DraggableScrollableSheet(expand: false, initialChildSize: .72, maxChildSize: .94, builder: (context, controller) => ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 14, 20, 30), children: [
    Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(8)))),
    const SizedBox(height: 16), Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), ...sections,
  ])));
}

Widget _detailSection(String title, Map<String, dynamic> values, Map<String, String> labels) {
  final rows = values.entries.where((entry) => entry.value != null && entry.value is! List && entry.value is! Map && '${entry.value}'.trim().isNotEmpty).toList(growable: false);
  if (rows.isEmpty) return const SizedBox.shrink();
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 16), Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 6),
    ...rows.map((entry) => Card(child: ListTile(title: Text(labels[entry.key] ?? entry.key), subtitle: SelectableText('${entry.value}')))),
  ]);
}

Widget _taskListSection(String title, List<Map<String, dynamic>> tasks) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  const SizedBox(height: 16), Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 6),
  ...tasks.map((task) => Card(child: ListTile(title: Text(task['source_label'] as String? ?? 'مهمة'), subtitle: Text('${task['task_status'] ?? '—'} · ${task['created_at'] ?? ''}')))),
]);

Widget _historySection(List<Map<String, dynamic>> history) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  const SizedBox(height: 16), const Text('سجل تغيّر حالة المهمة', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 6),
  ...history.map((entry) => Card(child: ListTile(title: Text('${entry['from_status'] ?? 'بداية'} ← ${entry['to_status'] ?? '—'}'), subtitle: Text('${entry['actor_name'] ?? 'النظام'} · ${entry['created_at'] ?? ''}\n${entry['note'] ?? ''}')))),
]);
