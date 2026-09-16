import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';
import 'admin_navigation.dart';

/// Administrative control plane for approval policy, delivery fee rules and
/// global notification circuit breakers. Manual transfer receipts are not a
/// switch here: they always remain in the protected review queue.
final class AdminOperationsPage extends StatefulWidget {
  const AdminOperationsPage({super.key});

  @override
  State<AdminOperationsPage> createState() => _AdminOperationsPageState();
}

final class _AdminOperationsPageState extends State<AdminOperationsPage> {
  late Future<List<Object>> _future;
  bool _loaded = false;
  bool _saving = false;
  bool _autoListings = false;
  bool _requireImage = true;
  bool _inApp = true;
  bool _push = true;
  int _imageQuality = ImageUploadPolicy.quality;
  int _imageMaxWidth = ImageUploadPolicy.maxWidth;
  List<Map<String, dynamic>> _feeRules = const [];
  List<Map<String, dynamic>> _promotionPlans = const [];
  bool _hydrated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _future = _load();
    }
  }

  Future<List<Object>> _load() => Future.wait<Object>([
    AppScope.of(context).loadAdminModerationSettings(),
    AppScope.of(context).loadAdminFeeRules(),
    AppScope.of(context).loadAdminNotificationSettings(),
    AppScope.of(context).loadAdminPromotionPlans(),
  ]);

  void _hydrate(List<Object> values) {
    final moderation = values[0] as Map<String, dynamic>;
    final fees = values[1] as List<Map<String, dynamic>>;
    final notifications = values[2] as Map<String, dynamic>;
    final promotionPlans = values[3] as List<Map<String, dynamic>>;
    _autoListings = moderation['auto_approve_listings'] == true;
    _requireImage = moderation['require_listing_image'] != false;
    _inApp = notifications['in_app_enabled'] != false;
    _push = notifications['push_enabled'] != false;
    _feeRules = fees;
    _promotionPlans = promotionPlans;
    _hydrated = true;
  }

  Future<void> _savePolicies() async {
    setState(() => _saving = true);
    try {
      await Future.wait([
        AppScope.of(context).updateAdminModerationSettings(
          autoApproveListings: _autoListings,
          requireListingImage: _requireImage,
        ),
        AppScope.of(context).updateAdminNotificationSettings(
          inAppEnabled: _inApp,
          pushEnabled: _push,
        ),
        ImageUploadPolicy.update(
          quality: _imageQuality,
          maxWidth: _imageMaxWidth,
        ),
      ]);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ سياسات الإدارة.')));
    } on ApiException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editFee(Map<String, dynamic> rule) async {
    final minimum = TextEditingController(
      text: '${rule['default_delivery_fee'] ?? 0}',
    );
    final perKm = TextEditingController(
      text: '${rule['delivery_per_km_fee'] ?? 0}',
    );
    final platform = TextEditingController(
      text: '${rule['platform_fee_percent'] ?? 0}',
    );
    final courier = TextEditingController(
      text: '${rule['courier_share_percent'] ?? 100}',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('رسوم التوصيل ${rule['currency_code']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minimum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'الحد الأدنى للتوصيل',
                ),
              ),
              TextField(
                controller: perKm,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'رسوم كل كيلومتر'),
              ),
              TextField(
                controller: platform,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'نسبة المنصة %'),
              ),
              TextField(
                controller: courier,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'نصيب عامل التوصيل %',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (save != true) return;
    try {
      await AppScope.of(context).updateAdminFeeRule({
        'currency_code': rule['currency_code'],
        'default_delivery_fee': minimum.text.trim(),
        'delivery_per_km_fee': perKm.text.trim(),
        'platform_fee_percent': platform.text.trim(),
        'courier_share_percent': courier.text.trim(),
        'is_active': rule['is_active'] != false,
      });
      if (!mounted) return;
      setState(() {
        _hydrated = false;
        _future = _load();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث قاعدة الرسوم.')));
    } on ApiException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      minimum.dispose();
      perKm.dispose();
      platform.dispose();
      courier.dispose();
    }
  }

  Future<void> _editPromotionPlan([Map<String, dynamic>? plan]) async {
    final code = TextEditingController(text: plan?['code'] as String? ?? '');
    final name = TextEditingController(
      text: plan?['display_name_ar'] as String? ?? '',
    );
    final price = TextEditingController(text: '${plan?['price_amount'] ?? ''}');
    final hours = TextEditingController(
      text: '${plan?['duration_hours'] ?? ''}',
    );
    var currency = plan?['currency_code'] as String? ?? 'USD';
    var active = plan?['is_active'] != false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(plan == null ? 'خطة ترويج جديدة' : 'تعديل خطة ترويج'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  enabled: plan == null,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'رمز الخطة بالإنجليزية',
                  ),
                ),
                TextField(
                  controller: name,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'اسم الخطة بالعربية',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'العملة'),
                  items: const [
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'SYP', child: Text('SYP')),
                  ],
                  onChanged: plan == null
                      ? (value) =>
                            setModalState(() => currency = value ?? currency)
                      : null,
                ),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'السعر'),
                ),
                TextField(
                  controller: hours,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'المدة بالساعات',
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (value) => setModalState(() => active = value),
                  title: const Text('الخطة مفعّلة'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) {
      code.dispose();
      name.dispose();
      price.dispose();
      hours.dispose();
      return;
    }
    try {
      final body = {
        if (plan == null) 'code': code.text.trim().toLowerCase(),
        'display_name_ar': name.text.trim(),
        if (plan == null) 'currency_code': currency,
        'price_amount': price.text.trim(),
        'duration_hours': int.tryParse(hours.text.trim()) ?? 0,
        'is_active': active,
      };
      await AppScope.of(context).saveAdminPromotionPlan(
        code: plan?['code'] as String?,
        currencyCode: plan?['currency_code'] as String?,
        body: body,
      );
      if (mounted) {
        setState(() {
          _hydrated = false;
          _future = _load();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم حفظ خطة الترويج.')));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      code.dispose();
      name.dispose();
      price.dispose();
      hours.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('سياسات ورسوم المنصة'),
      bottom: adminControlBottom(context, 'operations'),
    ),
    body: FutureBuilder<List<Object>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: FilledButton.icon(
              onPressed: () => setState(() => _future = _load()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          );
        if (!_hydrated) _hydrate(snapshot.data!);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
          children: [
            Text(
              'الموافقة التلقائية',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.storefront_outlined),
                    title: Text('تنشيط المتاجر بواسطة صاحب المتجر'),
                    subtitle: Text('لا توجد موافقة إدارية على إنشاء المتجر؛ التوثيق منفصل داخل إدارة المتاجر.'),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    value: _autoListings,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _autoListings = value),
                    title: const Text('نشر إعلانات الحراج تلقائياً'),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    value: _requireImage,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _requireImage = value),
                    title: const Text('إلزام صورة للإعلان'),
                  ),
                ],
              ),
            ),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(15),
                child: Text(
                  'سندات الدفع اليدوي لا يمكن اعتمادها تلقائياً، وتبقى دائماً ضمن مراجعة الإدارة للحماية المالية.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'رسوم التوصيل حسب المسافة',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ..._feeRules.map(
              (rule) => Card(
                child: ListTile(
                  leading: const Icon(Icons.route_rounded),
                  title: Text(
                    '${rule['currency_code']} — حد أدنى ${rule['default_delivery_fee'] ?? 0}',
                  ),
                  subtitle: Text(
                    '+ ${rule['delivery_per_km_fee'] ?? 0} لكل كم · نصيب العامل ${rule['courier_share_percent'] ?? 0}%',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editFee(rule),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'خطط ترويج الحراج',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'إضافة خطة',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _saving ? null : () => _editPromotionPlan(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._promotionPlans.map(
              (plan) => Card(
                child: ListTile(
                  leading: Icon(
                    plan['is_active'] == true
                        ? Icons.campaign_outlined
                        : Icons.pause_circle_outline,
                  ),
                  title: Text(
                    plan['display_name_ar'] as String? ?? 'خطة ترويج',
                  ),
                  subtitle: Text(
                    '${plan['price_amount'] ?? 0} ${plan['currency_code'] ?? ''} · ${plan['duration_hours'] ?? 0} ساعة',
                  ),
                  trailing: IconButton(
                    tooltip: 'تعديل',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _saving ? null : () => _editPromotionPlan(plan),
                  ),
                ),
              ),
            ),
            if (_promotionPlans.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('أضف خطط ترويج مستقلة بعملتي USD وSYP.'),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'التنبيهات العامة',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    value: _inApp,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _inApp = value),
                    title: const Text('إظهار إشعارات داخل التطبيق'),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    value: _push,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _push = value),
                    title: const Text('إرسال Push عبر Firebase FCM'),
                    subtitle: const Text('يتأثر أيضاً بإعداد كل مستخدم وفئة.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ضغط الصور قبل الرفع',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الجودة: $_imageQuality%'),
                    Slider(
                      value: _imageQuality.toDouble(),
                      min: 35,
                      max: 100,
                      divisions: 13,
                      label: '$_imageQuality%',
                      onChanged: _saving
                          ? null
                          : (value) =>
                                setState(() => _imageQuality = value.round()),
                    ),
                    Text('أكبر عرض: $_imageMaxWidth px'),
                    Slider(
                      value: _imageMaxWidth.toDouble(),
                      min: 720,
                      max: 3000,
                      divisions: 19,
                      label: '$_imageMaxWidth px',
                      onChanged: _saving
                          ? null
                          : (value) =>
                                setState(() => _imageMaxWidth = value.round()),
                    ),
                    const Text(
                      'تطبّق هذه الإعدادات محلياً على الشعار وصور المنتجات وسندات الدفع وإثباتات التوصيل والصور الجديدة قبل رفعها.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _savePolicies,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('حفظ السياسات'),
            ),
          ],
        );
      },
    ),
  );
}
