import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import '../data/notification_repository.dart';

final class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  State<NotificationPreferencesPage> createState() => _NotificationPreferencesPageState();
}

final class _NotificationPreferencesPageState extends State<NotificationPreferencesPage> {
  late Future<List<NotificationPreference>> _future;
  List<NotificationPreference>? _items;
  bool _loaded = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _future = AppScope.of(context).loadNotificationPreferences();
    }
  }

  Future<void> _save() async {
    final items = _items;
    if (items == null) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).saveNotificationPreferences(items);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات الإشعارات.')));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _update(int index, {bool? inApp, bool? push}) => setState(() {
    _items![index] = _items![index].copyWith(inAppEnabled: inApp, pushEnabled: push);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إعدادات الإشعارات')),
    body: FutureBuilder<List<NotificationPreference>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: FilledButton.icon(onPressed: () => setState(() => _future = AppScope.of(context).loadNotificationPreferences()), icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة')));
        _items ??= List<NotificationPreference>.from(snapshot.data ?? const []);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
          children: [
            const Card(child: Padding(padding: EdgeInsets.all(15), child: Text('تحكم بما يظهر داخل التطبيق وما يصل عبر FCM لكل نوع من التنبيهات. تعطيل Push لا يلغي تسجيل جهازك، بل يوقف الإرسال لهذه الفئة فقط.'))),
            const SizedBox(height: 12),
            ..._items!.asMap().entries.map((entry) {
              final item = entry.value;
              return Card(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_label(item.category), style: const TextStyle(fontWeight: FontWeight.w900)),
                    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('إظهار داخل التطبيق'), value: item.inAppEnabled, onChanged: _saving ? null : (value) => _update(entry.key, inApp: value)),
                    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('إرسال إشعار Push'), value: item.pushEnabled, onChanged: _saving ? null : (value) => _update(entry.key, push: value)),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined), label: const Text('حفظ الإعدادات')),
          ],
        );
      },
    ),
  );

  String _label(String category) => switch (category) {
    'orders' => 'الطلبات',
    'payments' => 'الدفعات',
    'delivery' => 'التوصيل',
    'marketplace' => 'الحراج',
    'store' => 'تحديثات المتاجر',
    'support' => 'الدعم',
    'wallet' => 'المحفظة',
    'system' => 'النظام',
    _ => category,
  };
}
