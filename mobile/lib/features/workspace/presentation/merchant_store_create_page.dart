import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import '../data/workspace_repository.dart';

/// Recovery/onboarding flow for merchant accounts that do not yet have the
/// automatically provisioned store shell (for example legacy accounts).
final class MerchantStoreCreatePage extends StatefulWidget {
  const MerchantStoreCreatePage({super.key});

  @override
  State<MerchantStoreCreatePage> createState() => _MerchantStoreCreatePageState();
}

final class _MerchantStoreCreatePageState extends State<MerchantStoreCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  Future<List<StoreCategoryOption>>? _categories;
  String? _categoryId;
  String _currency = 'USD';
  bool _acceptsPickup = true;
  bool _acceptsDelivery = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _categories ??= AppScope.of(context).loadStoreCategories();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId == null || _categoryId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر قسم المتجر أولاً.')));
      return;
    }
    if (!_acceptsPickup && !_acceptsDelivery) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فعّل الاستلام المباشر أو التوصيل على الأقل.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.of(context).createMerchantStore(values: {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'phone': _phone.text.trim(),
        'category_public_id': _categoryId,
        'currency_code': _currency,
        'accepts_delivery': _acceptsDelivery,
        'accepts_pickup': _acceptsPickup,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إنشاء متجر')),
    body: FutureBuilder<List<StoreCategoryOption>>(
      future: _categories,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _CreateStoreState(
          icon: Icons.cloud_off_rounded,
          message: 'تعذر تحميل أقسام المتاجر.',
          action: () => setState(() => _categories = AppScope.of(context).loadStoreCategories()),
          actionLabel: 'إعادة المحاولة',
        );
        final categories = snapshot.data ?? const <StoreCategoryOption>[];
        if (categories.isEmpty) return const _CreateStoreState(
          icon: Icons.category_outlined,
          message: 'لا توجد أقسام متاجر مفعّلة حالياً. أضف قسماً من لوحة الإدارة أولاً.',
        );
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              Text('ابدأ متجرك', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('أكمل الحقول المطلوبة ثم فعّل المتجر من الإعدادات.'),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                maxLength: 150,
                decoration: const InputDecoration(labelText: 'اسم المتجر *'),
                validator: (value) => (value?.trim().length ?? 0) < 2 ? 'اكتب اسم المتجر.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 5,
                maxLength: 5000,
                decoration: const InputDecoration(labelText: 'وصف المتجر *'),
                validator: (value) => (value?.trim().length ?? 0) < 20 ? 'اكتب وصفاً من 20 حرفاً على الأقل.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                maxLength: 18,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم هاتف المتجر *'),
                validator: (value) => RegExp(r'^\+?[0-9]{7,18}$').hasMatch(value?.trim() ?? '') ? null : 'أدخل رقم هاتف صالحاً.',
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'قسم المتجر *'),
                items: categories.map((item) => DropdownMenuItem(value: item.publicId, child: Text(item.name))).toList(growable: false),
                onChanged: (value) => setState(() => _categoryId = value),
                validator: (value) => value == null || value.isEmpty ? 'اختر القسم.' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: const InputDecoration(labelText: 'عملة المتجر'),
                items: const [DropdownMenuItem(value: 'USD', child: Text('USD — دولار أمريكي')), DropdownMenuItem(value: 'SYP', child: Text('ل.س — ليرة سورية'))],
                onChanged: (value) => setState(() => _currency = value ?? 'USD'),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                value: _acceptsPickup,
                onChanged: _saving ? null : (value) => setState(() => _acceptsPickup = value),
                title: const Text('استلام مباشر من المتجر'),
              ),
              SwitchListTile.adaptive(
                value: _acceptsDelivery,
                onChanged: _saving ? null : (value) => setState(() => _acceptsDelivery = value),
                title: const Text('توصيل'),
                              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.storefront_outlined),
                label: Text(_saving ? 'جارٍ إنشاء المتجر…' : 'إنشاء المتجر'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

final class _CreateStoreState extends StatelessWidget {
  const _CreateStoreState({required this.icon, required this.message, this.action, this.actionLabel});
  final IconData icon;
  final String message;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 50, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(onPressed: action, icon: const Icon(Icons.refresh_rounded), label: Text(actionLabel ?? 'إعادة المحاولة')),
        ],
      ]),
    ),
  );
}
