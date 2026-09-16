import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';

/// Role-scoped settlement wallet. The backend remains the balance authority;
/// Android only displays returned amounts and submits an idempotent request.
final class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.role});
  final String role;
  @override
  State<WalletPage> createState() => _WalletPageState();
}

final class _WalletPageState extends State<WalletPage> {
  String _currency = 'USD';
  Future<Map<String, dynamic>>? _future;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); _future ??= _load(); }
  Future<Map<String, dynamic>> _load() => AppScope.of(context).loadWallet(role: widget.role, currencyCode: _currency);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المحفظة والسحوبات')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.account_balance_wallet_outlined, size: 48, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 12),
          Text(snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'تعذر تحميل المحفظة.', textAlign: TextAlign.center), const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => setState(() => _future = _load()), icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة')),
        ])));
        final wallet = snapshot.data!;
        return ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<String>(value: _currency, decoration: const InputDecoration(labelText: 'العملة'), items: const [DropdownMenuItem(value: 'USD', child: Text('USD — دولار أمريكي')), DropdownMenuItem(value: 'SYP', child: Text('ل.س — ليرة سورية'))], onChanged: (value) { if (value != null) setState(() { _currency = value; _future = _load(); }); }),
          const SizedBox(height: 18),
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('الرصيد المتاح', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6),
            Text('${wallet['available_amount'] ?? 0} ${wallet['currency_code'] ?? _currency}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 10), Text('رصيد محجوز للسحب: ${wallet['held_amount'] ?? 0} ${wallet['currency_code'] ?? _currency}'),
          ]))),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: () async { final result = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => WithdrawalRequestPage(role: widget.role, currency: _currency))); if (result == true && mounted) setState(() => _future = _load()); }, icon: const Icon(Icons.south_west_rounded), label: const Text('طلب سحب')),
          const SizedBox(height: 10),
          const Text('يعرض الرصيد المعتمد من الخادم فقط. راجع بيانات التحويل قبل إرسال الطلب.', style: TextStyle(height: 1.6)),
        ]);
      },
    ),
  );
}

final class WithdrawalRequestPage extends StatefulWidget {
  const WithdrawalRequestPage({super.key, required this.role, required this.currency});
  final String role; final String currency;
  @override
  State<WithdrawalRequestPage> createState() => _WithdrawalRequestPageState();
}

final class _WithdrawalRequestPageState extends State<WithdrawalRequestPage> {
  final _form = GlobalKey<FormState>(); final _amount = TextEditingController(); final _method = TextEditingController(); final _account = TextEditingController(); bool _saving = false;
  @override void dispose() { _amount.dispose(); _method.dispose(); _account.dispose(); super.dispose(); }
  Future<void> _submit() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).requestWalletWithdrawal(role: widget.role, currencyCode: widget.currency, amount: _amount.text.trim(), payoutDetails: {'method': _method.text.trim(), 'account': _account.text.trim()});
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلب السحب للمراجعة.'))); Navigator.of(context).pop(true); }
    } on ApiException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('طلب سحب')), body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [
    Text('العملة: ${widget.currency}', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 14),
    TextFormField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ *'), validator: (value) => (num.tryParse(value?.trim() ?? '') ?? 0) <= 0 ? 'أدخل مبلغاً أكبر من صفر.' : null), const SizedBox(height: 10),
    TextFormField(controller: _method, decoration: const InputDecoration(labelText: 'طريقة التحويل *', hintText: 'حوالة، محفظة إلكترونية…'), validator: (value) => (value?.trim().isEmpty ?? true) ? 'حدد طريقة التحويل.' : null), const SizedBox(height: 10),
    TextFormField(controller: _account, decoration: const InputDecoration(labelText: 'بيانات الاستلام *'), validator: (value) => (value?.trim().isEmpty ?? true) ? 'أدخل بيانات الاستلام.' : null), const SizedBox(height: 18),
    FilledButton.icon(onPressed: _saving ? null : _submit, icon: const Icon(Icons.send_rounded), label: Text(_saving ? 'جارٍ الإرسال…' : 'إرسال طلب السحب')),
  ])));
}
