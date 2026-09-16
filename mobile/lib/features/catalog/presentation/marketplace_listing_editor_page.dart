import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';

/// Creates a marketplace listing through the same structured location, media
/// and attribute contract used by the web form.
final class MarketplaceListingEditorPage extends StatefulWidget {
  const MarketplaceListingEditorPage({super.key});

  @override
  State<MarketplaceListingEditorPage> createState() => _MarketplaceListingEditorPageState();
}

final class _MarketplaceListingEditorPageState extends State<MarketplaceListingEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _attributeText = <String, TextEditingController>{};
  final _attributes = <String, dynamic>{};

  Future<({List<Map<String, dynamic>> categories, List<Map<String, dynamic>> locations})>? _setup;
  Future<List<Map<String, dynamic>>>? _categoryAttributes;
  String? _categoryId;
  String? _countryId;
  String? _cityId;
  String? _districtId;
  Map<String, dynamic>? _selectedLocation;
  String _type = 'goods';
  String _currency = 'USD';
  XFile? _image;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setup ??= _loadSetup();
  }

  Future<({List<Map<String, dynamic>> categories, List<Map<String, dynamic>> locations})> _loadSetup() async {
    final controller = AppScope.of(context);
    final result = await Future.wait([
      controller.loadMarketplaceCategories(),
      controller.loadMarketplaceLocationOptions(),
    ]);
    return (categories: result[0], locations: result[1]);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    for (final item in _attributeText.values) {
      item.dispose();
    }
    super.dispose();
  }

  void _setCategory(String? value) {
    setState(() {
      _categoryId = value;
      _categoryAttributes = value == null
          ? null
          : AppScope.of(context).loadMarketplaceAttributes(value);
      _attributes.clear();
      for (final item in _attributeText.values) {
        item.dispose();
      }
      _attributeText.clear();
    });
  }

  Future<void> _pickLocation(List<Map<String, dynamic>> options) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MarketplaceLocationPickerSheet(options: options),
    );
    if (result == null || !mounted) return;
    final kind = result['kind'] as String? ?? '';
    final publicId = result['public_id'] as String? ?? '';
    setState(() {
      _selectedLocation = result;
      _countryId = result['country_public_id'] as String? ?? '';
      _cityId = null;
      _districtId = null;
      if (kind == 'country') {
        _countryId = publicId;
      } else if (kind == 'city') {
        _cityId = publicId;
      } else if (kind == 'district') {
        _cityId = result['city_public_id'] as String? ?? '';
        _districtId = publicId;
      }
    });
  }

  Future<void> _pickImage() async {
    final image = await ImageUploadPolicy.pick(ImageSource.gallery);
    if (image != null && mounted) setState(() => _image = image);
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId == null || _countryId == null || _countryId!.isEmpty || _cityId == null || _cityId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر مدينة أو منطقة من قائمة الموقع لإكمال الدولة والمدينة.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      for (final entry in _attributeText.entries) {
        final value = entry.value.text.trim();
        if (value.isNotEmpty) _attributes[entry.key] = value;
      }
      await AppScope.of(context).createMarketplaceListing(
        title: _title.text,
        description: _description.text,
        categoryId: _categoryId!,
        listingType: _type,
        currencyCode: _currency,
        countryId: _countryId!,
        cityId: _cityId!,
        districtId: _districtId,
        priceAmount: _price.text,
        attributes: _attributes,
        image: _image,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعلان. تتحدد حالة النشر وفق سياسة الإدارة.')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on FormatException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('إضافة إعلان جديد')),
        body: FutureBuilder<({List<Map<String, dynamic>> categories, List<Map<String, dynamic>> locations})>(
          future: _setup,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _setup = _loadSetup()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('تعذر التحميل — أعد المحاولة'),
                ),
              );
            }
            final setup = snapshot.data!;
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                children: [
                  Text('تفاصيل الإعلان', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  const SizedBox(height: 12),
                  _PhotoField(image: _image, onPick: _pickImage),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _title,
                    maxLength: 180,
                    decoration: const InputDecoration(labelText: 'عنوان الإعلان *'),
                    validator: (value) => (value?.trim().length ?? 0) < 4 ? 'اكتب عنواناً من 4 أحرف على الأقل.' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _description,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 5000,
                    decoration: const InputDecoration(labelText: 'الوصف *'),
                    validator: (value) => (value?.trim().length ?? 0) < 10 ? 'اكتب وصفاً واضحاً من 10 أحرف على الأقل.' : null,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'القسم *'),
                    items: setup.categories.map((item) => DropdownMenuItem(
                      value: item['public_id'] as String?,
                      child: Text(item['name'] as String? ?? 'قسم'),
                    )).toList(),
                    onChanged: _setCategory,
                    validator: (value) => value == null ? 'اختر القسم.' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: DropdownButtonFormField<String>(
                        value: _type,
                        decoration: const InputDecoration(labelText: 'نوع الإعلان'),
                        items: const [DropdownMenuItem(value: 'goods', child: Text('سلعة')), DropdownMenuItem(value: 'service', child: Text('خدمة'))],
                        onChanged: (value) => setState(() => _type = value ?? 'goods'),
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: DropdownButtonFormField<String>(
                        value: _currency,
                        decoration: const InputDecoration(labelText: 'العملة'),
                        items: const [DropdownMenuItem(value: 'USD', child: Text('USD')), DropdownMenuItem(value: 'SYP', child: Text('ل.س'))],
                        onChanged: (value) => setState(() => _currency = value ?? 'USD'),
                      )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    maxLength: 16,
                    decoration: const InputDecoration(
                      labelText: 'السعر *',
                      hintText: 'مثال: 25000',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      if (raw.isEmpty) return 'أدخل سعر الإعلان.';
                      final amount = num.tryParse(raw);
                      return amount == null || amount < 0 ? 'أدخل سعراً صحيحاً يساوي صفراً أو أكثر.' : null;
                    },
                  ),
                  const SizedBox(height: 8),
                  _MarketplaceLocationField(
                    selected: _selectedLocation,
                    hasSelectedCity: _cityId != null && _cityId!.isNotEmpty,
                    enabled: setup.locations.isNotEmpty,
                    onTap: () => _pickLocation(setup.locations),
                  ),
                  if (_categoryAttributes != null) ...[
                    const SizedBox(height: 20),
                    Text('خصائص القسم', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    _AttributeFields(
                      future: _categoryAttributes!,
                      values: _attributes,
                      textControllers: _attributeText,
                      onChanged: () => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ الإعلان'),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

final class _PhotoField extends StatelessWidget {
  const _PhotoField({required this.image, required this.onPick});
  final XFile? image;
  final VoidCallback onPick;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPick,
        icon: Icon(image == null ? Icons.add_photo_alternate_outlined : Icons.check_circle_outline_rounded),
        label: Text(image == null ? 'إرفاق صورة الإعلان' : 'تم اختيار صورة — تغييرها'),
      );
}

final class _MarketplaceLocationField extends StatelessWidget {
  const _MarketplaceLocationField({
    required this.selected,
    required this.hasSelectedCity,
    required this.enabled,
    required this.onTap,
  });
  final Map<String, dynamic>? selected;
  final bool hasSelectedCity;
  final bool enabled;
  final VoidCallback onTap;

  String _title() {
    final item = selected;
    if (item == null) return 'ابحث عن دولة أو مدينة أو منطقة';
    final kind = item['kind'] as String? ?? '';
    if (kind == 'district') return '${item['name'] ?? ''}، ${item['city_name'] ?? ''}';
    return item['name'] as String? ?? 'اختر الموقع';
  }

  String _subtitle() {
    final item = selected;
    if (item == null) return 'اختيار مدينة أو منطقة يحدد الدولة والمدينة تلقائياً.';
    if (!hasSelectedCity) return 'اختر مدينة من القائمة نفسها لإكمال الموقع.';
    return item['subtitle'] as String? ?? '';
  }

  @override
  Widget build(BuildContext context) => FormField<bool>(
        initialValue: hasSelectedCity,
        validator: (_) => hasSelectedCity ? null : 'اختر مدينة أو منطقة لموقع الإعلان.',
        builder: (field) => InputDecorator(
          decoration: InputDecoration(labelText: 'الموقع *', errorText: field.errorText),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(Icons.travel_explore_rounded, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_title(), style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(enabled ? _subtitle() : 'لا توجد مواقع مفعلة حالياً.', style: Theme.of(context).textTheme.bodySmall)])),
                  const Icon(Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
          ),
        ),
      );
}

final class _MarketplaceLocationPickerSheet extends StatefulWidget {
  const _MarketplaceLocationPickerSheet({required this.options});
  final List<Map<String, dynamic>> options;

  @override
  State<_MarketplaceLocationPickerSheet> createState() => _MarketplaceLocationPickerSheetState();
}

final class _MarketplaceLocationPickerSheetState extends State<_MarketplaceLocationPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _matches {
    final term = _search.text.trim().toLowerCase();
    if (term.isEmpty) return widget.options;
    return widget.options.where((item) => '${item['name'] ?? ''} ${item['subtitle'] ?? ''}'.toLowerCase().contains(term)).toList(growable: false);
  }

  String _kindLabel(String kind) => switch (kind) {
        'district' => 'منطقة / حي',
        'city' => 'مدينة',
        _ => 'دولة',
      };

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .74,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('حدد موقع الإعلان', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text('ابحث في قائمة واحدة. تظهر الدولة التابعة أسفل كل مدينة أو منطقة.'),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'ابحث عن دولة أو مدينة أو منطقة'),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: matches.isEmpty
                    ? const Center(child: Text('لا توجد نتائج مطابقة.'))
                    : ListView.separated(
                        itemCount: matches.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = matches[index];
                          return ListTile(
                            leading: Icon(item['kind'] == 'district' ? Icons.location_on_outlined : item['kind'] == 'city' ? Icons.location_city_outlined : Icons.public_outlined),
                            title: Text('${_kindLabel(item['kind'] as String? ?? '')}: ${item['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(item['subtitle'] as String? ?? ''),
                            onTap: () => Navigator.of(context).pop(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _AttributeFields extends StatelessWidget {
  const _AttributeFields({required this.future, required this.values, required this.textControllers, required this.onChanged});
  final Future<List<Map<String, dynamic>>> future;
  final Map<String, dynamic> values;
  final Map<String, TextEditingController> textControllers;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
      return Column(children: (snapshot.data ?? const <Map<String, dynamic>>[]).map((attribute) {
        final id = attribute['public_id'] as String? ?? '';
        final label = '${attribute['label'] as String? ?? 'خاصية'}${attribute['is_required'] == true ? ' *' : ''}';
        final type = attribute['field_type'] as String? ?? 'text';
        final required = attribute['is_required'] == true;
        if (type == 'boolean') {
          if (required && !values.containsKey(id)) values[id] = false;
          return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: values[id] == true,
          onChanged: (value) { values[id] = value; onChanged(); },
        );
        }
        if (type == 'select') {
          final options = (attribute['options'] as List? ?? const []).map((value) => value.toString()).toList();
          return Padding(padding: const EdgeInsets.only(top: 8), child: DropdownButtonFormField<String>(
            value: values[id] as String?, isExpanded: true, decoration: InputDecoration(labelText: label),
            items: options.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
            onChanged: (value) { values[id] = value; onChanged(); },
            validator: (value) => required && (value == null || value.isEmpty) ? 'هذه الخاصية مطلوبة.' : null,
          ));
        }
        final field = textControllers.putIfAbsent(id, TextEditingController.new);
        return Padding(padding: const EdgeInsets.only(top: 8), child: TextFormField(
          controller: field,
          keyboardType: type == 'number' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          decoration: InputDecoration(labelText: label),
          validator: (value) => required && (value?.trim().isEmpty ?? true) ? 'هذه الخاصية مطلوبة.' : null,
        ));
      }).toList());
    },
  );
}
