import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';

/// Merchant-only, final review queue for manual-payment notices.
final class MerchantPaymentReviewPage extends StatefulWidget {
  const MerchantPaymentReviewPage({super.key});

  @override
  State<MerchantPaymentReviewPage> createState() => _MerchantPaymentReviewPageState();
}

final class _MerchantPaymentReviewPageState extends State<MerchantPaymentReviewPage> {
  Future<List<Map<String, dynamic>>>? _future;
  String? _working;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).loadMerchantPaymentQueue();
  }

  void _reload() => setState(() => _future = AppScope.of(context).loadMerchantPaymentQueue());

  Future<void> _showReceipt(String orderId) async {
    try {
      final Uint8List bytes = await AppScope.of(context).loadMerchantPaymentReceipt(orderId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('صورة إيصال الدفع'),
          content: InteractiveViewer(child: Image.memory(bytes)),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق'))],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<String?> _note({required bool reject}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reject ? 'رفض إشعار الدفع' : 'اعتماد إشعار الدفع'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: reject ? 'سبب الرفض' : 'ملاحظة للتأكيد (اختيارية)',
            hintText: reject ? 'هذا الحقل مطلوب للعميل.' : null,
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (reject && value.length < 2) return;
              Navigator.of(context).pop(value);
            },
            style: reject ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
            child: Text(reject ? 'رفض الإشعار' : 'اعتماد الدفع'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _review(Map<String, dynamic> item, String decision) async {
    final orderId = item['order_public_id'] as String? ?? '';
    if (orderId.isEmpty) return;
    final note = await _note(reject: decision == 'reject');
    if (note == null || !mounted) return;
    setState(() => _working = orderId);
    try {
      await AppScope.of(context).reviewMerchantPayment(orderId: orderId, decision: decision, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(decision == 'approve' ? 'تم اعتماد الدفع وإرسال النتيجة للعميل.' : 'تم رفض إشعار الدفع وإرسال السبب للعميل.')));
      _reload();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('مراجعة إشعارات الدفع'),
      actions: [IconButton(onPressed: _working == null ? _reload : null, icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث')],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تعذر تحميل إشعارات الدفع.';
          return Center(child: FilledButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), label: Text(message)));
        }
        final items = snapshot.data ?? const <Map<String, dynamic>>[];
        if (items.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(26), child: Text('لا توجد إشعارات دفع بانتظار قرارك.', textAlign: TextAlign.center)));
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final orderId = item['order_public_id'] as String? ?? '';
              final working = _working == orderId;
              final note = item['payer_note'] as String? ?? '';
              final reference = item['transfer_reference'] as String? ?? '';
              final hasReceipt = item['has_receipt'] == true;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(item['order_number'] as String? ?? 'طلب', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                      const Chip(label: Text('قيد المراجعة')),
                    ]),
                    Text('${item['customer_name'] ?? 'عميل'} · ${item['total_amount'] ?? 0} ${item['currency_code'] ?? ''}'),
                    if (reference.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 9), child: SelectableText('مرجع التحويل: $reference')),
                    if (note.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note, style: const TextStyle(height: 1.55))),
                    if (hasReceipt) Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton.icon(onPressed: working ? null : () => _showReceipt(orderId), icon: const Icon(Icons.image_outlined), label: const Text('عرض صورة الإيصال'))),
                    const SizedBox(height: 8),
                    if (working)
                      const Align(alignment: AlignmentDirectional.centerEnd, child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                    else
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(onPressed: () => _review(item, 'reject'), icon: const Icon(Icons.close_rounded), label: const Text('رفض')),
                        FilledButton.icon(onPressed: () => _review(item, 'approve'), icon: const Icon(Icons.verified_rounded), label: const Text('اعتماد الدفع')),
                      ]),
                  ]),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}
