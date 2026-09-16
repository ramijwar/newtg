import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import 'admin_navigation.dart';

/// Builds durable campaigns. Delivery stays server-side; device tokens never enter this UI.
final class AdminNotificationCampaignPage extends StatefulWidget {
  const AdminNotificationCampaignPage({super.key});
  @override
  State<AdminNotificationCampaignPage> createState() => _AdminNotificationCampaignPageState();
}

final class _AdminNotificationCampaignPageState extends State<AdminNotificationCampaignPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _roles = <String>{};
  final _users = <String, Map<String, dynamic>>{};
  String _mode = 'all';
  String _category = 'system';
  String _targetType = 'none';
  Map<String, dynamic>? _targetStore;
  Map<String, dynamic>? _target;
  bool _sending = false;
  bool _loaded = false;
  late Future<List<Map<String, dynamic>>> _history;
  Future<Map<String, dynamic>>? _preview;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _history = AppScope.of(context).loadAdminNotificationCampaigns();
    _preview = AppScope.of(context).previewAdminNotificationCampaign(_payload);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _payload => {
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'category': _category,
        'audience_mode': _mode,
        'role_codes': _mode == 'roles' ? _roles.toList(growable: false) : const <String>[],
        'user_ids': _mode == 'users' ? _users.keys.toList(growable: false) : const <String>[],
        'target_type': _targetType,
        'target_entity_public_id': _targetType == 'none' ? '' : (_target?['entity_public_id'] as String? ?? ''),
      };

  void _refreshPreview() {
    if ((_mode == 'roles' && _roles.isEmpty) || (_mode == 'users' && _users.isEmpty)) {
      setState(() => _preview = null);
      return;
    }
    setState(() => _preview = AppScope.of(context).previewAdminNotificationCampaign(_payload));
  }

  String _role(String code) => switch (code) {
        'customer' => 'العملاء',
        'merchant' => 'التجار',
        'courier' => 'عمال التوصيل',
        _ => code,
      };

  String _destinationType(String code) => switch (code) {
        'store' => 'متجر',
        'product' => 'منتج',
        'marketplace_listing' => 'إعلان حراج',
        _ => 'بدون وجهة مباشرة',
      };

  String _audience(Map<String, dynamic> campaign) {
    if (campaign['audience_mode'] == 'all') return 'كل الحسابات النشطة غير الإدارية';
    if (campaign['audience_mode'] == 'roles') {
      return 'الأدوار: ${(campaign['target_roles'] as List? ?? const []).map((role) => _role('$role')).join('، ')}';
    }
    return 'مستخدمون محددون: ${(campaign['target_user_ids'] as List? ?? const []).length}';
  }

  String _historyDestination(Map<String, dynamic> campaign) {
    final type = campaign['target_entity_type'] as String?;
    if (type == null || type.isEmpty) return 'بدون وجهة مباشرة';
    return '${_destinationType(type)}: ${campaign['target_label'] ?? 'عنصر محفوظ'}';
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _chooseUsers() async {
    final input = TextEditingController();
    Future<List<Map<String, dynamic>>>? found;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, modalSet) {
          void search() {
            final term = input.text.trim();
            if (term.isEmpty) return;
            modalSet(() => found = AppScope.of(context).searchAdminUsers(search: term));
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(sheetContext).bottom + 18),
              child: SizedBox(
                height: 480,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('اختيار مستخدمين', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: input,
                    autofocus: true,
                    onSubmitted: (_) => search(),
                    decoration: InputDecoration(labelText: 'الاسم أو اسم المستخدم أو الهاتف', suffixIcon: IconButton(onPressed: search, icon: const Icon(Icons.search_rounded))),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: found == null
                        ? const Center(child: Text('ابحث ثم اختر حساباً أو أكثر.'))
                        : FutureBuilder<List<Map<String, dynamic>>>(
                            future: found,
                            builder: (_, snap) {
                              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                              if (snap.hasError) return const Center(child: Text('تعذر البحث عن الحسابات.'));
                              final rows = snap.data ?? const [];
                              if (rows.isEmpty) return const Center(child: Text('لا توجد حسابات نشطة مطابقة.'));
                              return ListView.builder(
                                itemCount: rows.length,
                                itemBuilder: (_, index) {
                                  final user = rows[index];
                                  final id = user['public_id'] as String? ?? '';
                                  return CheckboxListTile(
                                    value: _users.containsKey(id),
                                    onChanged: id.isEmpty
                                        ? null
                                        : (value) {
                                            setState(() { if (value == true) _users[id] = user; else _users.remove(id); });
                                            modalSet(() {});
                                          },
                                    controlAffinity: ListTileControlAffinity.leading,
                                    title: Text(user['full_name'] as String? ?? 'مستخدم'),
                                    subtitle: Text('@${user['username'] ?? '—'} · ${user['phone'] ?? '—'}'),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () { _refreshPreview(); Navigator.pop(sheetContext); }, child: const Text('تم'))),
                ]),
              ),
            ),
          );
        },
      ),
    );
    input.dispose();
  }

  Future<Map<String, dynamic>?> _searchDestination({required String type, required String title, required String hint, String storeId = ''}) => showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _CampaignTargetSearchSheet(type: type, title: title, hint: hint, storeId: storeId),
      );

  Future<void> _chooseStore() async {
    final store = await _searchDestination(type: 'store', title: 'اختيار متجر', hint: 'اسم المتجر أو اسم التاجر');
    if (store == null || !mounted) return;
    setState(() { _targetStore = store; _target = _targetType == 'store' ? store : null; });
  }

  Future<void> _chooseDestination() async {
    if (_targetType == 'product' && _targetStore == null) {
      await _chooseStore();
      return;
    }
    final config = switch (_targetType) {
      'store' => ('store', 'اختيار متجر', 'اسم المتجر أو اسم التاجر', ''),
      'product' => ('product', 'اختيار منتج', 'اسم المنتج أو SKU', _targetStore?['entity_public_id'] as String? ?? ''),
      'marketplace_listing' => ('marketplace_listing', 'اختيار إعلان حراج', 'عنوان الإعلان أو المدينة أو المنطقة', ''),
      _ => ('', '', '', ''),
    };
    if (config.$1.isEmpty) return;
    final item = await _searchDestination(type: config.$1, title: config.$2, hint: config.$3, storeId: config.$4);
    if (item == null || !mounted) return;
    setState(() => _target = item);
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    if (_mode == 'roles' && _roles.isEmpty) { _message('اختر دوراً واحداً على الأقل.'); return; }
    if (_mode == 'users' && _users.isEmpty) { _message('اختر مستخدماً واحداً على الأقل.'); return; }
    if (_targetType != 'none' && (_target?['entity_public_id'] as String? ?? '').isEmpty) {
      _message('اختر العنصر الذي سيفتحه الإشعار، أو اختر بدون وجهة مباشرة.');
      return;
    }
    setState(() => _sending = true);
    try {
      final result = await AppScope.of(context).createAdminNotificationCampaign(_payload);
      _message(result['replayed'] == true ? 'الحملة مسجلة مسبقاً.' : 'تم إنشاء الحملة ووضع ${result['campaign']?['queued_notification_count'] ?? 0} إشعار في الطابور.');
      setState(() {
        _title.clear(); _body.clear(); _roles.clear(); _users.clear(); _mode = 'all';
        _targetType = 'none'; _targetStore = null; _target = null;
        _history = AppScope.of(context).loadAdminNotificationCampaigns();
      });
      _refreshPreview();
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _destinationPicker() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _targetType,
          decoration: const InputDecoration(labelText: 'الوجهة عند الضغط (اختيارية)'),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('بدون وجهة مباشرة')),
            DropdownMenuItem(value: 'store', child: Text('متجر محدد')),
            DropdownMenuItem(value: 'product', child: Text('منتج ضمن متجر')),
            DropdownMenuItem(value: 'marketplace_listing', child: Text('إعلان حراج محدد')),
          ],
          onChanged: (value) => setState(() { _targetType = value ?? 'none'; _targetStore = null; _target = null; }),
        ),
        if (_targetType != 'none') ...[
          const SizedBox(height: 10),
          const Text('تظهر هنا العناصر المتاحة للمستخدمين فقط؛ البحث فوري ومحدود النتائج.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          if (_targetType == 'product' && _targetStore == null)
            OutlinedButton.icon(onPressed: _chooseStore, icon: const Icon(Icons.storefront_outlined), label: const Text('1. بحث واختيار متجر')),
          if (_targetType == 'product' && _targetStore != null)
            Card(color: Theme.of(context).colorScheme.secondaryContainer, child: ListTile(
              leading: const Icon(Icons.storefront_outlined), title: Text(_targetStore?['label'] as String? ?? 'متجر'), subtitle: Text(_targetStore?['subtitle'] as String? ?? ''),
              trailing: TextButton(onPressed: () => setState(() { _targetStore = null; _target = null; }), child: const Text('تغيير')),
            )),
          if (_targetType != 'product' || _targetStore != null)
            OutlinedButton.icon(onPressed: _chooseDestination, icon: Icon(_targetType == 'marketplace_listing' ? Icons.storefront_outlined : _targetType == 'product' ? Icons.inventory_2_outlined : Icons.search_rounded), label: Text(_target == null ? (_targetType == 'product' ? '2. بحث واختيار منتج' : 'بحث واختيار ${_destinationType(_targetType)}') : 'تغيير ${_destinationType(_targetType)}')),
          if (_target != null)
            Card(color: Theme.of(context).colorScheme.secondaryContainer, child: ListTile(
              leading: Icon(_targetType == 'store' ? Icons.storefront_outlined : _targetType == 'product' ? Icons.inventory_2_outlined : Icons.campaign_outlined),
              title: Text(_target?['label'] as String? ?? 'عنصر'), subtitle: Text(_target?['subtitle'] as String? ?? ''),
              trailing: IconButton(tooltip: 'إزالة الوجهة', onPressed: () => setState(() => _target = null), icon: const Icon(Icons.close_rounded)),
            )),
        ],
      ]);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('إرسال إشعار إداري'), bottom: adminControlBottom(context, 'activity')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('حملة جديدة', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    const Text('يحفظ الإشعار أولاً ثم يرسله Cron تدريجياً. لا تظهر بيانات الأجهزة هنا.'),
                    const SizedBox(height: 14),
                    TextFormField(controller: _title, maxLength: 180, decoration: const InputDecoration(labelText: 'العنوان'), validator: (value) => (value ?? '').trim().length < 2 ? 'اكتب عنواناً من حرفين على الأقل.' : null),
                    TextFormField(controller: _body, minLines: 3, maxLines: 5, maxLength: 1000, decoration: const InputDecoration(labelText: 'النص'), validator: (value) => (value ?? '').trim().length < 2 ? 'اكتب نص الإشعار.' : null),
                    DropdownButtonFormField<String>(value: _category, decoration: const InputDecoration(labelText: 'الفئة'), items: const [DropdownMenuItem(value: 'system', child: Text('النظام')), DropdownMenuItem(value: 'marketplace', child: Text('الحراج')), DropdownMenuItem(value: 'orders', child: Text('الطلبات')), DropdownMenuItem(value: 'delivery', child: Text('التوصيل')), DropdownMenuItem(value: 'wallet', child: Text('المحفظة')), DropdownMenuItem(value: 'support', child: Text('الدعم'))], onChanged: (value) { setState(() => _category = value!); _refreshPreview(); }),
                    _destinationPicker(),
                    const SizedBox(height: 12),
                    const Text('الجمهور', style: TextStyle(fontWeight: FontWeight.w800)),
                    RadioListTile<String>(value: 'all', groupValue: _mode, contentPadding: EdgeInsets.zero, title: const Text('كل الحسابات النشطة غير الإدارية'), onChanged: (value) { setState(() => _mode = value!); _refreshPreview(); }),
                    RadioListTile<String>(value: 'roles', groupValue: _mode, contentPadding: EdgeInsets.zero, title: const Text('حسب الأدوار'), onChanged: (value) { setState(() => _mode = value!); _refreshPreview(); }),
                    if (_mode == 'roles') Wrap(spacing: 8, children: ['customer', 'merchant', 'courier'].map((role) => FilterChip(label: Text(_role(role)), selected: _roles.contains(role), onSelected: (chosen) { setState(() { if (chosen) _roles.add(role); else _roles.remove(role); }); _refreshPreview(); })).toList(growable: false)),
                    RadioListTile<String>(value: 'users', groupValue: _mode, contentPadding: EdgeInsets.zero, title: const Text('مستخدمون محددون'), onChanged: (value) { setState(() => _mode = value!); _refreshPreview(); }),
                    if (_mode == 'users') Column(crossAxisAlignment: CrossAxisAlignment.start, children: [OutlinedButton.icon(onPressed: _chooseUsers, icon: const Icon(Icons.person_search_outlined), label: const Text('بحث واختيار مستخدمين')), if (_users.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: _users.values.map((user) => InputChip(label: Text(user['full_name'] as String? ?? 'مستخدم'), onDeleted: () { setState(() => _users.remove(user['public_id'])); _refreshPreview(); })).toList(growable: false))]),
                    const SizedBox(height: 12),
                    _preview == null
                        ? const Text('سيظهر عدد المستلمين بعد اختيار جمهور صالح.', style: TextStyle(fontWeight: FontWeight.w700))
                        : FutureBuilder<Map<String, dynamic>>(future: _preview, builder: (_, snapshot) { if (snapshot.connectionState != ConnectionState.done) return const LinearProgressIndicator(); if (snapshot.hasError) return const Text('تعذر حساب العدد حالياً.'); final data = snapshot.data ?? const {}; return Text('المطابقون: ${data['selected_user_count'] ?? 0} · المؤهلون وفق إعداداتهم: ${data['eligible_user_count'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)); }),
                    const SizedBox(height: 16),
                    FilledButton.icon(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined), label: Text(_sending ? 'جارٍ إنشاء الحملة…' : 'إنشاء الحملة ووضعها في الطابور')),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              const Text('سجل الحملات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _history,
                builder: (_, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) return const Center(child: Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator()));
                  if (snapshot.hasError) return const Card(child: ListTile(title: Text('تعذر تحميل سجل الحملات.')));
                  final rows = snapshot.data ?? const [];
                  if (rows.isEmpty) return const Card(child: ListTile(title: Text('لا توجد حملات مسجلة.')));
                  return Column(children: rows.map((campaign) => Card(child: ListTile(leading: const Icon(Icons.campaign_outlined), title: Text(campaign['title'] as String? ?? 'إشعار'), subtitle: Text('${_audience(campaign)}\n${_historyDestination(campaign)}\n${campaign['created_at'] ?? ''} · بواسطة ${campaign['sender_name'] ?? 'مدير'}'), isThreeLine: true, trailing: Text('${campaign['queued_notification_count'] ?? 0}\nفي الطابور', textAlign: TextAlign.center)))).toList(growable: false));
                },
              ),
            ],
          ),
        ),
      );
}

/// Debounced server-side lookup. The API itself only returns public/active content and caps results.
final class _CampaignTargetSearchSheet extends StatefulWidget {
  const _CampaignTargetSearchSheet({required this.type, required this.title, required this.hint, required this.storeId});
  final String type;
  final String title;
  final String hint;
  final String storeId;
  @override State<_CampaignTargetSearchSheet> createState() => _CampaignTargetSearchSheetState();
}

final class _CampaignTargetSearchSheetState extends State<_CampaignTargetSearchSheet> {
  final _input = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _debounce?.cancel(); _input.dispose(); super.dispose(); }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) { setState(() { _items = const []; _loading = false; _error = null; }); return; }
    _debounce = Timer(const Duration(milliseconds: 240), () async {
      if (!mounted) return;
      setState(() { _loading = true; _error = null; });
      try {
        final rows = await AppScope.of(context).searchAdminNotificationCampaignTargets(type: widget.type, search: value, storeId: widget.storeId);
        if (mounted && _input.text.trim() == value.trim()) setState(() { _items = rows; _loading = false; });
      } on ApiException catch (error) {
        if (mounted) setState(() { _items = const []; _loading = false; _error = error.message; });
      } catch (_) {
        if (mounted) setState(() { _items = const []; _loading = false; _error = 'تعذر البحث حالياً.'; });
      }
    });
  }

  IconData get _icon => switch (widget.type) { 'store' => Icons.storefront_outlined, 'product' => Icons.inventory_2_outlined, _ => Icons.campaign_outlined };

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
          child: SizedBox(
            height: 540,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              const Text('نتائج عامة متاحة للمستخدمين فقط، بحد أقصى 12 نتيجة.'),
              const SizedBox(height: 12),
              TextField(controller: _input, autofocus: true, onChanged: _onChanged, decoration: InputDecoration(labelText: widget.hint, prefixIcon: const Icon(Icons.search_rounded))),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!))
                        : _input.text.trim().length < 2
                            ? const Center(child: Text('اكتب حرفين على الأقل لبدء البحث الفوري.'))
                            : _items.isEmpty
                                ? const Center(child: Text('لا توجد عناصر عامة مطابقة.'))
                                : ListView.separated(
                                    itemCount: _items.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (_, index) {
                                      final item = _items[index];
                                      return ListTile(
                                        leading: Icon(_icon),
                                        title: Text(item['label'] as String? ?? 'عنصر'),
                                        subtitle: Text(item['subtitle'] as String? ?? ''),
                                        trailing: const Icon(Icons.chevron_left_rounded),
                                        onTap: () => Navigator.of(context).pop(item),
                                      );
                                    },
                                  ),
              ),
            ]),
          ),
        ),
      );
}
