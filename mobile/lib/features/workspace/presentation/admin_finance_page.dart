import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import 'admin_navigation.dart';

/// Read-only financial oversight. Decisions on withdrawals remain in AdminQueuesPage
/// so the same protected decision workflow is used from every admin workspace.
final class AdminFinancePage extends StatefulWidget {
  const AdminFinancePage({super.key});
  @override
  State<AdminFinancePage> createState() => _AdminFinancePageState();
}

final class _AdminFinancePageState extends State<AdminFinancePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late Future<Map<String, dynamic>> _summary;
  late Future<List<Map<String, dynamic>>> _wallets;
  late Future<List<Map<String, dynamic>>> _entries;
  late Future<List<Map<String, dynamic>>> _invoices;
  late Future<List<Map<String, dynamic>>> _withdrawals;
  String _query = '';
  String _currency = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _reload();
  }

  void _reload() {
    final api = AppScope.of(context);
    setState(() {
      _summary = api.loadAdminFinancialSummary();
      _wallets = api.loadAdminFinancialWallets();
      _entries = api.loadAdminFinancialEntries();
      _invoices = api.loadAdminFinancialInvoices();
      _withdrawals = api.loadAdminDecisionQueues().then((queues) => queues.withdrawals);
    });
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> source) {
    final term = _query.trim().toLowerCase();
    return source.where((item) => (_currency.isEmpty || item['currency_code'] == _currency) && (term.isEmpty || item.values.any((v) => '$v'.toLowerCase().contains(term)))).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('السجل المالي'),
      bottom: adminControlBottom(context, 'finance'),
      actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث')],
    ),
    body: Column(children: [
      FutureBuilder<Map<String, dynamic>>(
        future: _summary,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const LinearProgressIndicator(minHeight: 2);
          final values = snapshot.data!;
          final wallets = (values['wallets'] as List? ?? const []).whereType<Map>().toList();
          final entries = (values['entries'] as List? ?? const []).whereType<Map>().toList();
          final invoices = (values['invoices'] as List? ?? const []).whereType<Map>().toList();
          return SizedBox(height: 78, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 10, 16, 8), children: [
            _metric('المحافظ', wallets.fold<int>(0, (n, row) => n + ((row['wallet_count'] as num?)?.toInt() ?? 0)), Icons.account_balance_wallet_outlined),
            _metric('القيود', entries.fold<int>(0, (n, row) => n + ((row['entry_count'] as num?)?.toInt() ?? 0)), Icons.receipt_long_outlined),
            _metric('الفواتير', invoices.fold<int>(0, (n, row) => n + ((row['invoice_count'] as num?)?.toInt() ?? 0)), Icons.description_outlined),
          ]));
        },
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 6), child: Row(children: [
        Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'بحث بالاسم أو المرجع أو المعرف', border: OutlineInputBorder()), onChanged: (value) => setState(() => _query = value))),
        const SizedBox(width: 8),
        SizedBox(width: 132, child: DropdownButtonFormField<String>(value: _currency, isExpanded: true, decoration: const InputDecoration(labelText: 'العملة', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: '', child: Text('الكل')), DropdownMenuItem(value: 'USD', child: Text('USD')), DropdownMenuItem(value: 'SYP', child: Text('ل.س'))], onChanged: (value) => setState(() => _currency = value ?? ''))),
      ])),
      TabBar(controller: _tabs, isScrollable: true, tabs: const [Tab(text: 'المحافظ'), Tab(text: 'القيود'), Tab(text: 'الفواتير'), Tab(text: 'السحوبات')]),
      Expanded(child: TabBarView(controller: _tabs, children: [_walletsTab(), _entriesTab(), _invoicesTab(), _withdrawalsTab()])),
    ]),
  );

  Widget _metric(String label, int value, IconData icon) => Container(
    width: 126, margin: const EdgeInsetsDirectional.only(end: 8), padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(14)),
    child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)]))]),
  );

  Widget _walletsTab() => FutureBuilder<List<Map<String, dynamic>>>(future: _wallets, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return const Center(child: Text('تعذر تحميل المحافظ.'));
    final rows = _filter(snapshot.data ?? const []);
    if (rows.isEmpty) return const Center(child: Text('لا توجد محافظ مطابقة.'));
    return ListView.separated(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), itemCount: rows.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (_, i) {
      final row = rows[i]; final key = row['account_key'] as String? ?? ''; final currency = row['currency_code'] as String? ?? '';
      return Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet_outlined)),
        title: Text(row['owner_name'] as String? ?? (row['owner_type'] == 'platform' ? 'محفظة المنصة' : key), style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('متاح: ${row['available_amount'] ?? 0} $currency · محجوز: ${row['held_amount'] ?? 0}\n${row['owner_type'] ?? '—'} · $key'),
        isThreeLine: true, trailing: const Icon(Icons.chevron_left_rounded), onTap: key.isEmpty || currency.isEmpty ? null : () => _showWallet(key, currency),
      ));
    });
  });

  Widget _entriesTab() => FutureBuilder<List<Map<String, dynamic>>>(future: _entries, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return const Center(child: Text('تعذر تحميل القيود المالية.'));
    final rows = _filter(snapshot.data ?? const []);
    if (rows.isEmpty) return const Center(child: Text('لا توجد قيود مطابقة.'));
    return ListView.separated(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), itemCount: rows.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (_, i) {
      final row = rows[i]; final plus = row['direction'] == 'credit';
      return Card(child: ListTile(
        leading: CircleAvatar(backgroundColor: plus ? Colors.green.shade50 : Colors.red.shade50, child: Icon(plus ? Icons.add_rounded : Icons.remove_rounded, color: plus ? Colors.green : Colors.red)),
        title: Text('${plus ? '+' : '−'}${row['amount'] ?? 0} ${row['currency_code'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${row['entry_type'] ?? 'قيد'} · ${row['owner_name'] ?? row['account_key'] ?? ''}\n${row['reference_type'] ?? ''}: ${row['reference_id'] ?? ''}\n${row['note'] ?? row['created_at'] ?? ''}'),
        isThreeLine: true,
      ));
    });
  });

  Widget _invoicesTab() => FutureBuilder<List<Map<String, dynamic>>>(future: _invoices, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return const Center(child: Text('تعذر تحميل الفواتير.'));
    final rows = _filter(snapshot.data ?? const []);
    if (rows.isEmpty) return const Center(child: Text('لا توجد فواتير مطابقة.'));
    return ListView.separated(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), itemCount: rows.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (_, i) {
      final row = rows[i];
      return Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
        title: Text(row['invoice_number'] as String? ?? 'فاتورة', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${row['store_name'] ?? 'متجر'} · ${row['customer_name'] ?? 'عميل'}\nالإجمالي: ${row['total_amount'] ?? 0} ${row['currency_code'] ?? ''} · ${row['order_status'] ?? '—'}'),
        isThreeLine: true, onTap: () => _showRows('تفاصيل الفاتورة', row),
      ));
    });
  });

  Widget _withdrawalsTab() => FutureBuilder<List<Map<String, dynamic>>>(future: _withdrawals, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return const Center(child: Text('تعذر تحميل طلبات السحب.'));
    final rows = _filter(snapshot.data ?? const []);
    if (rows.isEmpty) return const Center(child: Text('لا توجد طلبات سحب مطابقة.'));
    return ListView.separated(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), itemCount: rows.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (_, i) {
      final row = rows[i];
      return Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.payments_outlined)),
        title: Text('${row['amount'] ?? 0} ${row['currency_code'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${row['request_status'] ?? '—'} · ${row['created_at'] ?? ''}\n${row['decision_note'] ?? 'افتح طابور الإدارة لاتخاذ القرار.'}'),
        isThreeLine: true,
        trailing: row['request_status'] == 'pending' ? TextButton(onPressed: () => openAdminDestination(context, AdminDestination.queues), child: const Text('مراجعة')) : null,
        onTap: () => _showRows('تفاصيل طلب السحب', row),
      ));
    });
  });

  Future<void> _showWallet(String key, String currency) async {
    try {
      final data = await AppScope.of(context).loadAdminFinancialWalletDetail(key, currency);
      if (!mounted) return;
      final wallet = Map<String, dynamic>.from(data['wallet'] as Map? ?? const {});
      final entries = (data['entries'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final withdrawals = (data['withdrawals'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => SafeArea(child: DraggableScrollableSheet(expand: false, initialChildSize: .78, maxChildSize: .94, builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 18, 20, 30), children: [
        Text('تفاصيل المحفظة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        _rows('الرصيد والمالك', wallet),
        if (withdrawals.isNotEmpty) ...[const SizedBox(height: 14), const Text('طلبات السحب', style: TextStyle(fontWeight: FontWeight.w900)), ...withdrawals.map((r) => Card(child: ListTile(title: Text('${r['amount']} ${r['currency_code']} · ${r['request_status']}'), subtitle: Text('${r['decision_note'] ?? ''}\n${r['created_at'] ?? ''}'))))],
        if (entries.isNotEmpty) ...[const SizedBox(height: 14), const Text('آخر القيود', style: TextStyle(fontWeight: FontWeight.w900)), ...entries.map((r) => Card(child: ListTile(title: Text('${r['direction'] == 'credit' ? '+' : '−'}${r['amount']} · ${r['entry_type']}'), subtitle: Text('${r['reference_type']}: ${r['reference_id']}\n${r['note'] ?? r['created_at'] ?? ''}'))))],
      ]))));
    } on ApiException catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message))); }
  }

  void _showRows(String title, Map<String, dynamic> values) => showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), ...values.entries.where((e) => e.value != null).map((e) => ListTile(title: Text(e.key), subtitle: SelectableText('${e.value}')))])));
  Widget _rows(String title, Map<String, dynamic> values) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const SizedBox(height: 12), Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), ...values.entries.where((e) => e.value != null).map((e) => ListTile(dense: true, title: Text(e.key), subtitle: SelectableText('${e.value}')))]);
}
