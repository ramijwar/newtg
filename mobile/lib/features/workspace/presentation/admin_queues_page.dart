import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import 'admin_navigation.dart';
import '../data/workspace_repository.dart';

/// Operational queues for decisions which must always be explicit. Manual
/// payments are visible to administration but are final when the merchant decides.
final class AdminQueuesPage extends StatefulWidget {
  const AdminQueuesPage({super.key});

  @override
  State<AdminQueuesPage> createState() => _AdminQueuesPageState();
}

final class _AdminQueuesPageState extends State<AdminQueuesPage> {
  late Future<AdminDecisionQueues> _future;
  bool _loaded = false;
  String? _working;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _future = AppScope.of(context).loadAdminDecisionQueues();
    }
  }

  void _reload() =>
      setState(() => _future = AppScope.of(context).loadAdminDecisionQueues());

  Future<void> _run(
    String key,
    Future<void> Function() operation,
    String message,
  ) async {
    setState(() => _working = key);
    try {
      await operation();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        _reload();
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<String?> _noteDialog({
    required String title,
    required String label,
    bool required = false,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final note = controller.text.trim();
              if (required && note.length < 2) return;
              Navigator.pop(context, note);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _viewPrivateImage(Future<Uint8List> Function() loader) async {
    try {
      final bytes = await loader();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('سند خاص'),
          content: InteractiveViewer(child: Image.memory(bytes)),
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

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 6,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('الطوابير الإدارية'),
        actions: [
          IconButton(
            tooltip: 'تحديث الطوابير',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _working == null ? _reload : null,
          ),
        ],
        bottom: adminTabbedBottom(
          context,
          'queues',
          const TabBar(
            isScrollable: true,
          tabs: [
            Tab(text: 'الدفعات'),
            Tab(text: 'السحوبات'),
            Tab(text: 'الدعم'),
            Tab(text: 'البلاغات'),
            Tab(text: 'النزاعات'),
              Tab(text: 'الترويج'),
            ],
          ),
        ),
      ),
      body: FutureBuilder<AdminDecisionQueues>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'تعذر تحميل طوابير الإدارة.';
            return Center(
              child: FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(message),
              ),
            );
          }
          final queues = snapshot.data!;
          return TabBarView(
            children: [
              _QueueList(
                empty: 'لا توجد إشعارات دفع يدوي مسجلة حتى الآن.',
                children: queues.payments.map(_paymentCard).toList(),
              ),
              _QueueList(
                empty: 'لا توجد طلبات سحب معلقة.',
                children: queues.withdrawals.map(_withdrawalCard).toList(),
              ),
              _QueueList(
                empty: 'لا توجد تذاكر دعم حالياً.',
                children: queues.supportTickets.map(_supportCard).toList(),
              ),
              _QueueList(
                empty: 'لا توجد بلاغات حراج تحتاج قراراً.',
                children: queues.reports.map(_reportCard).toList(),
              ),
              _QueueList(
                empty: 'لا توجد نزاعات حراج مفتوحة.',
                children: queues.disputes.map(_disputeCard).toList(),
              ),
              _QueueList(
                empty: 'لا توجد سندات ترويج بانتظار المراجعة.',
                children: queues.promotions.map(_promotionCard).toList(),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _paymentCard(Map<String, dynamic> item) {
    final id = item['order_public_id'] as String? ?? '';
    final hasReceipt = item['has_receipt'] == true;
    final paid = item['order_payment_status'] == 'paid';
    return _DecisionCard(
      title: '${item['order_number'] ?? 'طلب'} — ${item['store_name'] ?? 'متجر'}',
      details: item,
      detailsTitle: 'سجل إشعار الدفع',
      subtitle: '${paid ? 'تم الدفع' : item['payment_status'] ?? '—'} · ${item['amount'] ?? 0} ${item['currency_code'] ?? ''}${item['invoice_number'] != null ? ' · فاتورة ${item['invoice_number']}' : ''}',
      busy: false,
      actions: [
        if (hasReceipt && id.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _viewPrivateImage(() => AppScope.of(context).loadAdminPaymentReceipt(id)),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('الإيصال'),
          ),
      ],
    );
  }

  Widget _withdrawalCard(Map<String, dynamic> item) {
    final id = item['public_id'] as String? ?? '';
    final pending = item['request_status'] == 'pending';
    return _DecisionCard(
      title: '${item['amount'] ?? 0} ${item['currency_code'] ?? 'USD'}',
      details: item,
      detailsTitle: 'طلب سحب',
      subtitle: 'الحالة: ${item['request_status'] ?? ''}',
      busy: _working == 'withdrawal-$id',
      actions: [
        TextButton(
          onPressed: !pending || id.isEmpty
              ? null
              : () async {
                  final note = await _noteDialog(
                    title: 'رفض السحب',
                    label: 'سبب الرفض',
                    required: true,
                  );
                  if (note != null) {
                    _run(
                      'withdrawal-$id',
                      () => AppScope.of(context).decideAdminWithdrawal(
                        withdrawalId: id,
                        decision: 'reject',
                        note: note,
                      ),
                      'تم رفض السحب وإعادة الرصيد للمحفظة.',
                    );
                  }
                },
          child: const Text('رفض'),
        ),
        FilledButton(
          onPressed: !pending || id.isEmpty
              ? null
              : () => _run(
                  'withdrawal-$id',
                  () => AppScope.of(context).decideAdminWithdrawal(
                    withdrawalId: id,
                    decision: 'approve',
                  ),
                  'تم اعتماد طلب السحب.',
                ),
          child: const Text('اعتماد'),
        ),
      ],
    );
  }

  Widget _supportCard(Map<String, dynamic> item) {
    final id = item['public_id'] as String? ?? '';
    return _DecisionCard(
      title: item['subject'] as String? ?? 'تذكرة دعم',
      details: item,
      detailsTitle: 'تذكرة الدعم',
      subtitle:
          '${item['ticket_status'] ?? ''} · ${item['requester_name'] ?? ''}',
      busy: _working == 'support-$id',
      actions: [
        OutlinedButton(
          onPressed: id.isEmpty
              ? null
              : () async {
                  final reply = await _noteDialog(
                    title: 'الرد على التذكرة',
                    label: 'الرد',
                    required: true,
                  );
                  if (reply != null) {
                    _run(
                      'support-$id',
                      () => AppScope.of(context)
                          .replyAdminSupportTicket(ticketId: id, body: reply),
                      'تم إرسال رد الإدارة.',
                    );
                  }
                },
          child: const Text('رد'),
        ),
        FilledButton.tonal(
          onPressed: id.isEmpty
              ? null
              : () => _run(
                  'support-$id',
                  () => AppScope.of(
                    context,
                  ).updateAdminSupportTicket(ticketId: id, status: 'resolved'),
                  'تم إغلاق التذكرة كحلٍّ مكتمل.',
                ),
          child: const Text('حل وإغلاق'),
        ),
      ],
    );
  }

  Widget _reportCard(Map<String, dynamic> item) {
    final id = item['public_id'] as String? ?? '';
    return _DecisionCard(
      title: item['reason_code'] as String? ?? 'بلاغ حراج',
      details: item,
      detailsTitle: 'بلاغ الحراج',
      subtitle:
          '${item['reporter_name'] ?? 'مستخدم'} · ${item['details'] ?? 'دون تفاصيل'}',
      busy: _working == 'report-$id',
      actions: [
        OutlinedButton(
          onPressed: id.isEmpty
              ? null
              : () => _run(
                  'report-$id',
                  () => AppScope.of(context)
                      .updateAdminReport(reportId: id, status: 'under_review'),
                  'تم تحويل البلاغ إلى قيد المراجعة.',
                ),
          child: const Text('مراجعة'),
        ),
        TextButton(
          onPressed: id.isEmpty
              ? null
              : () => _run(
                  'report-$id',
                  () =>
                      AppScope.of(context)
                          .updateAdminReport(reportId: id, status: 'rejected'),
                  'تم رفض البلاغ.',
                ),
          child: const Text('رفض'),
        ),
        FilledButton(
          onPressed: id.isEmpty
              ? null
              : () => _run(
                  'report-$id',
                  () =>
                      AppScope.of(context)
                          .updateAdminReport(reportId: id, status: 'resolved'),
                  'تمت معالجة البلاغ.',
                ),
          child: const Text('حل'),
        ),
      ],
    );
  }

  Widget _disputeCard(Map<String, dynamic> item) {
    final id = item['public_id'] as String? ?? '';
    return _DecisionCard(
      title: item['reason_code'] as String? ?? 'نزاع حراج',
      details: item,
      detailsTitle: 'نزاع الحراج',
      subtitle: item['details'] as String? ?? 'لا توجد تفاصيل إضافية.',
      busy: _working == 'dispute-$id',
      actions: [
        OutlinedButton(
          onPressed: id.isEmpty
              ? null
              : () => _decideDispute(id, 'resolve_buyer', 'لصالح المشتري'),
          child: const Text('للمشتري'),
        ),
        OutlinedButton(
          onPressed: id.isEmpty
              ? null
              : () => _decideDispute(id, 'resolve_seller', 'لصالح البائع'),
          child: const Text('للبائع'),
        ),
        TextButton(
          onPressed: id.isEmpty
              ? null
              : () => _decideDispute(id, 'cancel', 'إلغاء الصفقة'),
          child: const Text('إلغاء الصفقة'),
        ),
      ],
    );
  }

  Future<void> _decideDispute(String id, String decision, String label) async {
    final note = await _noteDialog(
      title: 'قرار النزاع: $label',
      label: 'ملاحظة القرار للطرفين',
      required: true,
    );
    if (note == null) return;
    _run(
      'dispute-$id',
      () => AppScope.of(context)
          .decideAdminDispute(disputeId: id, decision: decision, note: note),
      'تم تسجيل قرار النزاع.',
    );
  }

  Widget _promotionCard(Map<String, dynamic> item) {
    final id = item['public_id'] as String? ?? '';
    return _DecisionCard(
      title: item['listing_title'] as String? ?? 'ترويج حراج',
      details: item,
      detailsTitle: 'طلب ترويج',
      subtitle:
          '${item['amount'] ?? 0} ${item['currency_code'] ?? 'USD'} · ${item['requester_name'] ?? ''}',
      busy: _working == 'promotion-$id',
      actions: [
        OutlinedButton.icon(
          onPressed: id.isEmpty
              ? null
              : () => _viewPrivateImage(
                  () => AppScope.of(context).loadAdminPromotionReceipt(id),
                ),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('السند'),
        ),
        TextButton(
          onPressed: id.isEmpty
              ? null
              : () => _run(
                  'promotion-$id',
                  () => AppScope.of(
                    context,
                  ).reviewAdminPromotion(promotionId: id, decision: 'reject'),
                  'تم رفض دفع الترويج.',
                ),
          child: const Text('رفض'),
        ),
        FilledButton(
          onPressed: id.isEmpty
              ? null
              : () => _run(
                  'promotion-$id',
                  () => AppScope.of(
                    context,
                  ).reviewAdminPromotion(promotionId: id, decision: 'approve'),
                  'تم اعتماد الترويج.',
                ),
          child: const Text('اعتماد'),
        ),
      ],
    );
  }
}

final class _QueueList extends StatelessWidget {
  const _QueueList({required this.empty, required this.children});
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async {},
    child: children.isEmpty
        ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: 260,
                child: Center(child: Text(empty, textAlign: TextAlign.center)),
              ),
            ],
          )
        : ListView(padding: const EdgeInsets.all(16), children: children),
  );
}

void _showQueueDetails(
  BuildContext context, {
  required String title,
  required Map<String, dynamic> item,
}) {
  const labels = {
    'public_id': 'المعرف',
    'order_public_id': 'معرف الطلب',
    'order_number': 'رقم الطلب',
    'store_name': 'المتجر',
    'requester_name': 'مقدم الطلب',
    'reporter_name': 'مقدم البلاغ',
    'listing_title': 'الإعلان',
    'amount': 'المبلغ',
    'total_amount': 'الإجمالي',
    'currency_code': 'العملة',
    'transfer_reference': 'مرجع التحويل',
    'request_status': 'الحالة',
    'ticket_status': 'حالة التذكرة',
    'report_status': 'حالة البلاغ',
    'dispute_status': 'حالة النزاع',
    'reason_code': 'السبب',
    'subject': 'العنوان',
    'details': 'التفاصيل',
    'created_at': 'تاريخ الإنشاء',
    'updated_at': 'آخر تحديث',
  };
  final rows = item.entries
      .where((entry) => entry.value != null && '${entry.value}'.trim().isNotEmpty)
      .map((entry) => (label: labels[entry.key] ?? entry.key, value: '${entry.value}'))
      .toList(growable: false);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .64,
        maxChildSize: .92,
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
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ...rows.map((row) => Card(
              child: ListTile(title: Text(row.label), subtitle: SelectableText(row.value)),
            )),
          ],
        ),
      ),
    ),
  );
}

final class _DecisionCard extends StatelessWidget {
  const _DecisionCard({
    required this.title,
    required this.subtitle,
    required this.details,
    required this.detailsTitle,
    required this.busy,
    required this.actions,
  });
  final String title;
  final String subtitle;
  final Map<String, dynamic> details;
  final String detailsTitle;
  final bool busy;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (busy)
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showQueueDetails(
                    context,
                    title: detailsTitle,
                    item: details,
                  ),
                  icon: const Icon(Icons.info_outline_rounded),
                  label: const Text('تفاصيل'),
                ),
                ...actions,
              ],
            ),
        ],
      ),
    ),
  );
}
