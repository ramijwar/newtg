import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';

/// Merchant-only campaign composer. The backend owns recipient selection and
/// does not create any subscriber notification until an administrator approves.
final class MerchantNotificationCampaignPage extends StatefulWidget {
  const MerchantNotificationCampaignPage({super.key});

  @override
  State<MerchantNotificationCampaignPage> createState() => _MerchantNotificationCampaignPageState();
}

final class _MerchantNotificationCampaignPageState extends State<MerchantNotificationCampaignPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  Map<String, dynamic>? _product;
  Future<List<Map<String, dynamic>>>? _history;
  bool _loaded = false;
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _history = AppScope.of(context).loadMerchantNotificationCampaigns();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  String _status(Map<String, dynamic> campaign) => switch (campaign['campaign_status']) {
        'approved' => 'نجحت الحملة',
        'rejected' => 'مرفوضة',
        _ => 'بانتظار موافقة الإدارة',
      };

  IconData _statusIcon(Map<String, dynamic> campaign) => switch (campaign['campaign_status']) {
        'approved' => Icons.check_circle_outline_rounded,
        'rejected' => Icons.cancel_outlined,
        _ => Icons.hourglass_top_rounded,
      };

  Future<void> _chooseProduct() async {
    final product = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _MerchantCampaignProductPicker(),
    );
    if (product != null && mounted) setState(() => _product = product);
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final productId = _product?['public_id'] as String? ?? '';
    if (productId.isEmpty) {
      _message('اختر منتجاً نشطاً من منتجات متجرك للحملة.');
      return;
    }
    setState(() => _sending = true);
    try {
      final result = await AppScope.of(context).createMerchantNotificationCampaign({
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'product_public_id': productId,
      });
      _message(result['replayed'] == true ? 'طلب الحملة مسجل مسبقاً.' : 'تم إرسال طلب الحملة إلى الإدارة للموافقة.');
      setState(() {
        _title.clear();
        _body.clear();
        _product = null;
        _history = AppScope.of(context).loadMerchantNotificationCampaigns();
      });
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('حملة للمشتركين والعملاء')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('طلب حملة جديدة', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 7),
                    const Text('تصل الحملة إلى متابعي متجرك والعملاء ذوي الطلبات المكتملة فقط. لن يرسل النظام شيئاً قبل موافقة الإدارة، ويعاد حساب المؤهلين عند الموافقة.'),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _title,
                      maxLength: 180,
                      decoration: const InputDecoration(labelText: 'العنوان'),
                      validator: (value) => (value ?? '').trim().length < 2 ? 'اكتب عنواناً من حرفين على الأقل.' : null,
                    ),
                    TextFormField(
                      controller: _body,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 1000,
                      decoration: const InputDecoration(labelText: 'النص'),
                      validator: (value) => (value ?? '').trim().length < 2 ? 'اكتب نص الحملة.' : null,
                    ),
                    const SizedBox(height: 6),
                    const Text('المنتج المرتبط', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 7),
                    if (_product == null)
                      OutlinedButton.icon(
                        onPressed: _chooseProduct,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('بحث واختيار منتج من متجري'),
                      )
                    else
                      Card(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(_product?['name'] as String? ?? 'منتج'),
                          subtitle: Text(_product?['sku'] == null || '${_product?['sku']}'.isEmpty ? 'منتج نشط من متجرك' : 'SKU: ${_product?['sku']}'),
                          trailing: IconButton(
                            tooltip: 'تغيير المنتج',
                            onPressed: _chooseProduct,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    const Text('تُحترم تفضيلات المستخدم لإشعارات تحديثات المتاجر.', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: _sending ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_outlined),
                      label: Text(_sending ? 'جارٍ إرسال طلب الحملة…' : 'إرسال طلب الحملة للموافقة'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              const Text('سجل حملاتي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _history,
                builder: (_, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) return const Center(child: Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator()));
                  if (snapshot.hasError) return const Card(child: ListTile(title: Text('تعذر تحميل سجل الحملات.')));
                  final campaigns = snapshot.data ?? const [];
                  if (campaigns.isEmpty) return const Card(child: ListTile(title: Text('لا توجد حملات بعد.')));
                  return Column(
                    children: campaigns.map((campaign) {
                      final approved = campaign['campaign_status'] == 'approved';
                      final rejected = campaign['campaign_status'] == 'rejected';
                      final title = (campaign['approved_title'] ?? campaign['requested_title'] ?? 'حملة متجر') as String;
                      final outcome = approved
                          ? 'تمت الموافقة ووضع ${campaign['queued_notification_count'] ?? 0} إشعاراً في الطابور. Push ناجح: ${campaign['recipients_with_sent_push'] ?? 0}.'
                          : rejected
                              ? (campaign['review_note'] as String? ?? 'لم تتم الموافقة على الحملة.')
                              : 'لم يُرسل أي إشعار بعد.';
                      return Card(
                        child: ListTile(
                          leading: Icon(_statusIcon(campaign)),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('${campaign['target_product_label'] ?? 'منتج المتجر'}\n$outcome\nالمستلمون عند الطلب: ${campaign['recipient_count_at_request'] ?? 0}'),
                          isThreeLine: true,
                          trailing: SizedBox(width: 92, child: Text(_status(campaign), textAlign: TextAlign.center, style: TextStyle(color: approved ? Theme.of(context).colorScheme.primary : rejected ? Theme.of(context).colorScheme.error : null, fontWeight: FontWeight.w800, fontSize: 12))),
                        ),
                      );
                    }).toList(growable: false),
                  );
                },
              ),
            ],
          ),
        ),
      );
}

/// The endpoint returns only active, public products owned by the authenticated merchant.
final class _MerchantCampaignProductPicker extends StatefulWidget {
  const _MerchantCampaignProductPicker();
  @override
  State<_MerchantCampaignProductPicker> createState() => _MerchantCampaignProductPickerState();
}

final class _MerchantCampaignProductPickerState extends State<_MerchantCampaignProductPicker> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() { _items = const []; _loading = false; _error = null; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 240), () async {
      if (!mounted) return;
      setState(() { _loading = true; _error = null; });
      try {
        final items = await AppScope.of(context).searchMerchantNotificationCampaignProducts(search: value.trim());
        if (mounted && value.trim() == _query.text.trim()) setState(() { _items = items; _loading = false; });
      } on ApiException catch (error) {
        if (mounted) setState(() { _items = const []; _loading = false; _error = error.message; });
      } catch (_) {
        if (mounted) setState(() { _items = const []; _loading = false; _error = 'تعذر البحث في المنتجات حالياً.'; });
      }
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
          child: SizedBox(
            height: 520,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('اختيار منتج من متجري', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              const Text('تظهر المنتجات النشطة المتاحة للمستخدمين من متجرك فقط.'),
              const SizedBox(height: 12),
              TextField(controller: _query, autofocus: true, onChanged: _search, decoration: const InputDecoration(labelText: 'اسم المنتج أو SKU', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!))
                        : _query.text.trim().length < 2
                            ? const Center(child: Text('اكتب حرفين على الأقل لبدء البحث.'))
                            : _items.isEmpty
                                ? const Center(child: Text('لا توجد منتجات نشطة مطابقة.'))
                                : ListView.separated(
                                    itemCount: _items.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (_, index) {
                                      final product = _items[index];
                                      final sku = product['sku'] as String?;
                                      return ListTile(
                                        leading: const Icon(Icons.inventory_2_outlined),
                                        title: Text(product['name'] as String? ?? 'منتج'),
                                        subtitle: Text(sku == null || sku.isEmpty ? 'منتج نشط' : 'SKU: $sku'),
                                        trailing: const Icon(Icons.chevron_left_rounded),
                                        onTap: () => Navigator.of(context).pop(product),
                                      );
                                    },
                                  ),
              ),
            ]),
          ),
        ),
      );
}
