import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';


final class StoreFollowButton extends StatefulWidget {
  const StoreFollowButton({super.key, required this.storeId, this.initialFollowing = false});
  final String storeId;
  final bool initialFollowing;
  @override
  State<StoreFollowButton> createState() => _StoreFollowButtonState();
}

final class _StoreFollowButtonState extends State<StoreFollowButton> {
  late bool _following;
  bool _busy = false;
  @override void initState() { super.initState(); _following = widget.initialFollowing; }
  Future<void> _toggle() async {
    if (_busy) return;
    final controller = AppScope.of(context);
    if (!controller.isCustomer) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('متابعة المتاجر متاحة لحساب العميل فقط.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final next = !_following;
      await controller.setStoreFollowing(storeId: widget.storeId, following: next);
      if (mounted) setState(() => _following = next);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(backgroundColor: _following ? const Color(0xFFFBECE8) : Colors.white, foregroundColor: _following ? const Color(0xFFC74D3C) : const Color(0xFF125D49), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12)),
    onPressed: _busy ? null : _toggle,
    icon: _busy ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_following ? Icons.favorite_rounded : Icons.favorite_border_rounded),
    label: Text(_following ? 'إلغاء المتابعة' : 'متابعة المتجر'),
  );
}

/// Store follow state and verified-purchase reviews, both backed by the store
/// contracts rather than local optimistic counters.
final class StoreEngagementPanel extends StatefulWidget {
  const StoreEngagementPanel({super.key, required this.storeId});
  final String storeId;
  @override
  State<StoreEngagementPanel> createState() => _StoreEngagementPanelState();
}

final class _StoreEngagementPanelState extends State<StoreEngagementPanel> {
  Future<List<Map<String, dynamic>>>? _reviews;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); _reviews ??= AppScope.of(context).loadStoreReviews(widget.storeId); }
  Future<void> _review() async {
    final controller = AppScope.of(context);
    if (!controller.isCustomer) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('التقييم متاح لحساب العميل فقط.'))); return; }
    try {
      final orders = await controller.loadStoreReviewEligibility(widget.storeId);
      if (!mounted) return;
      if (orders.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد طلبات مكتملة غير مقيّمة من هذا المتجر.'))); return; }
      final submitted = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => StoreReviewEditorPage(storeId: widget.storeId, orders: orders)));
      if (submitted == true && mounted) setState(() => _reviews = controller.loadStoreReviews(widget.storeId));
    } on ApiException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); }
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(children: [Expanded(child: Text('آراء العملاء', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))), TextButton.icon(onPressed: _review, icon: const Icon(Icons.star_outline_rounded), label: const Text('قيّم مشترياتك'))]),
    FutureBuilder<List<Map<String, dynamic>>>(future: _reviews, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
      final reviews = snapshot.data ?? const <Map<String, dynamic>>[];
      if (reviews.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('لا توجد تقييمات مكتملة بعد.'));
      return Column(children: reviews.map((review) => Card(child: ListTile(leading: CircleAvatar(child: Text('${review['rating'] ?? 0}★')), title: Text(review['customer_name'] as String? ?? 'عميل'), subtitle: Text(review['comment'] as String? ?? 'لم يضف العميل تعليقاً.')))).toList());
    }),
  ]);
}

final class StoreReviewEditorPage extends StatefulWidget {
  const StoreReviewEditorPage({super.key, required this.storeId, required this.orders});
  final String storeId; final List<Map<String, dynamic>> orders;
  @override State<StoreReviewEditorPage> createState() => _StoreReviewEditorPageState();
}

final class _StoreReviewEditorPageState extends State<StoreReviewEditorPage> {
  late String _orderId; int _rating = 5; final _comment = TextEditingController(); bool _saving = false;
  @override void initState() { super.initState(); _orderId = widget.orders.first['order_id'] as String? ?? ''; }
  @override void dispose() { _comment.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_saving || _orderId.isEmpty) return; setState(() => _saving = true);
    try { await AppScope.of(context).createStoreReview(storeId: widget.storeId, orderId: _orderId, rating: _rating, comment: _comment.text); if (mounted) Navigator.of(context).pop(true); }
    on ApiException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('تقييم المتجر')), body: ListView(padding: const EdgeInsets.all(16), children: [
    DropdownButtonFormField<String>(value: _orderId, isExpanded: true, decoration: const InputDecoration(labelText: 'الطلب المكتمل'), items: widget.orders.map((order) => DropdownMenuItem(value: order['order_id'] as String? ?? '', child: Text(order['order_number'] as String? ?? 'طلب مكتمل'))).toList(), onChanged: (value) => setState(() => _orderId = value ?? '')),
    const SizedBox(height: 12), DropdownButtonFormField<int>(value: _rating, decoration: const InputDecoration(labelText: 'التقييم'), items: List.generate(5, (i) { final rating = 5 - i; return DropdownMenuItem(value: rating, child: Text('$rating من 5 نجوم')); }), onChanged: (value) => setState(() => _rating = value ?? 5)),
    const SizedBox(height: 12), TextField(controller: _comment, maxLength: 1500, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'تعليقك (اختياري)')), const SizedBox(height: 14),
    FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.star_rounded), label: Text(_saving ? 'جارٍ النشر…' : 'نشر التقييم')),
  ]));
}
