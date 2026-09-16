import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';

/// Manual-payment promotion flow used by the web: select a compatible plan,
/// then submit a private receipt for the administrator's review.
final class MarketplacePromotionPage extends StatefulWidget {
  const MarketplacePromotionPage({super.key, required this.listingId, required this.currencyCode});
  final String listingId;
  final String currencyCode;
  @override
  State<MarketplacePromotionPage> createState() => _MarketplacePromotionPageState();
}

final class _MarketplacePromotionPageState extends State<MarketplacePromotionPage> {
  Future<List<Map<String, dynamic>>>? _future;
  String? _planCode;
  bool _saving = false;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); _future ??= AppScope.of(context).loadMarketplacePromotionPlans(); }
  Future<void> _request() async {
    if (_planCode == null || _saving) return;
    setState(() => _saving = true);
    try {
      final promotion = await AppScope.of(context).requestMarketplacePromotion(listingId: widget.listingId, planCode: _planCode!);
      final id = promotion['public_id'] as String? ?? '';
      if (!mounted || id.isEmpty) return;
      final submitted = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => MarketplacePromotionPaymentPage(promotionId: id)));
      if (submitted == true && mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('ترويج الإعلان')), body: FutureBuilder<List<Map<String, dynamic>>>(future: _future, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return Center(child: OutlinedButton.icon(onPressed: () => setState(() => _future = AppScope.of(context).loadMarketplacePromotionPlans()), icon: const Icon(Icons.refresh_rounded), label: const Text('تعذر تحميل الخطط')));
    final plans = (snapshot.data ?? const <Map<String, dynamic>>[]).where((plan) => plan['currency_code'] == widget.currencyCode).toList();
    if (plans.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد خطط ترويج مفعلة لعملة هذا الإعلان.', textAlign: TextAlign.center)));
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('اختر خطة الترويج. بعد ذلك أرفق سند التحويل الخاص ليُراجع من الإدارة.', style: TextStyle(height: 1.6)), const SizedBox(height: 14),
      ...plans.map((plan) => Card(child: RadioListTile<String>(value: plan['code'] as String? ?? '', groupValue: _planCode, onChanged: (value) => setState(() => _planCode = value), title: Text(plan['display_name_ar'] as String? ?? 'خطة ترويج', style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${plan['price_amount'] ?? 0} ${plan['currency_code'] ?? ''} · ${plan['duration_hours'] ?? 0} ساعة')))),
      const SizedBox(height: 14), FilledButton.icon(onPressed: _planCode == null || _saving ? null : _request, icon: const Icon(Icons.arrow_forward_rounded), label: Text(_saving ? 'جارٍ الإنشاء…' : 'اختيار الخطة والمتابعة')),
    ]);
  }));
}

final class MarketplacePromotionPaymentPage extends StatefulWidget {
  const MarketplacePromotionPaymentPage({super.key, required this.promotionId});
  final String promotionId;
  @override
  State<MarketplacePromotionPaymentPage> createState() => _MarketplacePromotionPaymentPageState();
}

final class _MarketplacePromotionPaymentPageState extends State<MarketplacePromotionPaymentPage> {
  final _form = GlobalKey<FormState>(); final _reference = TextEditingController(); XFile? _receipt; bool _saving = false;
  @override void dispose() { _reference.dispose(); super.dispose(); }
  Future<void> _submit() async {
    if (_saving || !(_form.currentState?.validate() ?? false) || _receipt == null) { if (_receipt == null) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أرفق سند التحويل أولاً.'))); return; }
    setState(() => _saving = true);
    try { await AppScope.of(context).submitMarketplacePromotionPayment(promotionId: widget.promotionId, transferReference: _reference.text, receipt: _receipt!); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال سند الترويج للمراجعة.'))); Navigator.of(context).pop(true); } }
    on ApiException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); }
    on FormatException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('سند دفع الترويج')), body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [
    const Text('يحفظ السند كملف خاص ولا يظهر للزوار.', style: TextStyle(height: 1.6)), const SizedBox(height: 16),
    TextFormField(controller: _reference, maxLength: 120, decoration: const InputDecoration(labelText: 'مرجع التحويل *'), validator: (value) => (value?.trim().length ?? 0) < 2 ? 'أدخل مرجعاً صحيحاً.' : null), const SizedBox(height: 10),
    OutlinedButton.icon(onPressed: () async { final image = await ImageUploadPolicy.pick(ImageSource.gallery); if (image != null && mounted) setState(() => _receipt = image); }, icon: Icon(_receipt == null ? Icons.receipt_long_outlined : Icons.check_circle_outline_rounded), label: Text(_receipt == null ? 'اختيار سند التحويل *' : 'تم اختيار السند — تغيير')),
    const SizedBox(height: 18), FilledButton.icon(onPressed: _saving ? null : _submit, icon: const Icon(Icons.send_rounded), label: Text(_saving ? 'جارٍ الإرسال…' : 'إرسال السند للمراجعة')),
  ])));
}
