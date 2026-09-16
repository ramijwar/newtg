import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';
import '../data/workspace_repository.dart';
import 'store_banner_management_page.dart';

final class StoreSettingsPage extends StatefulWidget {
  const StoreSettingsPage({super.key, required this.store});
  final Map<String, dynamic> store;

  @override
  State<StoreSettingsPage> createState() => _StoreSettingsPageState();
}

final class _StoreSettingsPageState extends State<StoreSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _tagline;
  late final TextEditingController _phone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _address;
  late final List<_StoreHoliday> _holidays;
  late String? _categoryId;
  late bool _acceptsDelivery;
  late bool _acceptsPickup;
  late bool _retail;
  late bool _preorder;
  late bool _activate;
  late Map<String, _StoreHours> _hours;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _depositTitle;
  late final TextEditingController _depositAddress;
  late final TextEditingController _paymentInstructions;
  late bool _manualPaymentEnabled;
  XFile? _logo;
  Future<Uint8List>? _logoPreview;
  Future<List<StoreCategoryOption>>? _categoriesFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    _name = TextEditingController(text: store['name'] as String? ?? '');
    _description = TextEditingController(
      text: store['description'] as String? ?? '',
    );
    _tagline = TextEditingController(
      text: store['discovery_tagline'] as String? ?? '',
    );
    _phone = TextEditingController(text: store['phone'] as String? ?? '');
    _whatsapp = TextEditingController(text: store['whatsapp_phone'] as String? ?? '');
    _address = TextEditingController(text: store['address_line1'] as String? ?? '');
    _categoryId = store['category_public_id'] as String?;
    _acceptsDelivery = store['accepts_delivery'] != false;
    _acceptsPickup = store['accepts_pickup'] != false;
    _retail = store['allows_retail'] != false;
    _preorder = store['allows_preorder'] == true;
    _activate = store['store_status'] == 'active';
    _latitude = TextEditingController(text: _coordinateText(store['latitude']));
    _longitude = TextEditingController(text: _coordinateText(store['longitude']));
    final manual = store['manual_payment'] is Map ? Map<String, dynamic>.from(store['manual_payment'] as Map) : const <String, dynamic>{};
    _manualPaymentEnabled = manual['enabled'] == true;
    _depositTitle = TextEditingController(text: manual['deposit_title'] as String? ?? '');
    _depositAddress = TextEditingController(text: manual['deposit_address'] as String? ?? '');
    _paymentInstructions = TextEditingController(text: manual['instructions'] as String? ?? '');
    _hours = _parseHours(store['business_hours']);
    _holidays = _parseHolidays(store['holidays']);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _categoriesFuture ??= AppScope.of(context).loadStoreCategories();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _tagline.dispose();
    _phone.dispose();
    _whatsapp.dispose();
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _depositTitle.dispose();
    _depositAddress.dispose();
    _paymentInstructions.dispose();
    for (final holiday in _holidays) { holiday.dispose(); }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final image = await ImageUploadPolicy.pick(ImageSource.gallery);
    if (image != null && mounted) {
      setState(() {
        _logo = image;
        _logoPreview = image.readAsBytes();
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null || _categoryId!.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اختر قسم المتجر.')));
      return;
    }
    if (!_acceptsDelivery && !_acceptsPickup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فعّل التوصيل أو الاستلام المباشر على الأقل.'),
        ),
      );
      return;
    }
    if (!_retail && !_preorder) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فعّل التجزئة أو الطلب المسبق على الأقل.')),
      );
      return;
    }
    if (_manualPaymentEnabled && _depositAddress.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل عنوان أو تفاصيل الإيداع قبل تفعيل التحويل اليدوي.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.of(context).updateMerchantStore(
        logo: _logo,
        values: {
          'name': _name.text.trim(),
          'description': _description.text.trim(),
          'discovery_tagline': _tagline.text.trim(),
          'phone': _phone.text.trim(),
          'whatsapp_phone': _whatsapp.text.trim(),
          'category_public_id': _categoryId,
          'currency_code': widget.store['currency_code'] as String? ?? 'USD',
          'address_line1': _address.text.trim(),
          'holidays': _holidayPayload(),
          if (_acceptsDelivery && _latitude.text.trim().isNotEmpty) 'latitude': _latitude.text.trim(),
          if (_acceptsDelivery && _longitude.text.trim().isNotEmpty) 'longitude': _longitude.text.trim(),
          'accepts_delivery': _acceptsDelivery,
          'accepts_pickup': _acceptsPickup,
          'allows_retail': _retail,
          'allows_preorder': _preorder,
          'manual_payment_enabled': _manualPaymentEnabled,
          'manual_payment_deposit_title': _depositTitle.text.trim(),
          'manual_payment_deposit_address': _depositAddress.text.trim(),
          'manual_payment_instructions': _paymentInstructions.text.trim(),
          'business_hours': _existingHoursOrDefault(),
          'store_enabled': _activate,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    } on FormatException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _dayLabels = <String, String>{
    'saturday': 'السبت',
    'sunday': 'الأحد',
    'monday': 'الاثنين',
    'tuesday': 'الثلاثاء',
    'wednesday': 'الأربعاء',
    'thursday': 'الخميس',
    'friday': 'الجمعة',
  };

  String _coordinateText(Object? value) => value == null ? '' : '$value';

  Map<String, _StoreHours> _parseHours(dynamic existing) {
    return {
      for (final day in _dayLabels.keys)
        day: _StoreHours.fromJson(existing is Map ? existing[day] : null),
    };
  }

  Map<String, dynamic> _existingHoursOrDefault() => {
    for (final entry in _hours.entries) entry.key: entry.value.toJson(),
  };

  List<_StoreHoliday> _parseHolidays(dynamic raw) {
    final values = raw is List ? raw : const [];
    return values.whereType<Map>().map((value) {
      final date = DateTime.tryParse('${value['date'] ?? ''}');
      return _StoreHoliday(date: date ?? DateTime.now(), label: '${value['label'] ?? ''}');
    }).toList(growable: true);
  }

  List<Map<String, dynamic>> _holidayPayload() => _holidays
      .where((holiday) => holiday.date != null)
      .map((holiday) => {'date': _dateValue(holiday.date!), 'label': holiday.controller.text.trim()})
      .toList(growable: false);

  String _dateValue(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickHolidayDate(_StoreHoliday holiday) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: holiday.date ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (chosen != null && mounted) setState(() => holiday.date = chosen);
  }

  void _copySaturdayToWeek() {
    final source = _hours['saturday']!;
    setState(() {
      for (final day in _dayLabels.keys) {
        if (day != 'saturday') _hours[day] = source.copyWith();
      }
    });
  }

  Future<void> _pickTime(String day, {required bool opening}) async {
    final current = _hours[day]!;
    final selected = await showTimePicker(
      context: context,
      initialTime: _StoreHours.toTimeOfDay(
        opening ? current.opensAt : current.closesAt,
      ),
    );
    if (selected == null || !mounted) return;
    final next = opening
        ? current.copyWith(opensAt: _StoreHours.format(selected))
        : current.copyWith(closesAt: _StoreHours.format(selected));
    if (!next.closed && next.closesAt.compareTo(next.opensAt) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('وقت الإغلاق يجب أن يكون بعد وقت الفتح.')),
      );
      return;
    }
    setState(() => _hours[day] = next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إعدادات المتجر'), actions: [IconButton(tooltip: 'إعلانات متجري', icon: const Icon(Icons.campaign_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StoreBannerManagementPage(admin: false))))]),
    body: FutureBuilder<List<StoreCategoryOption>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        final categories = [...?snapshot.data];
        final known = categories.any((item) => item.publicId == _categoryId);
        if (_categoryId != null && _categoryId!.isNotEmpty && !known) {
          categories.add(
            StoreCategoryOption(
              publicId: _categoryId!,
              name: widget.store['category_name'] as String? ?? 'القسم الحالي',
            ),
          );
        }
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            children: [
              _logoPicker(),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                maxLength: 150,
                decoration: const InputDecoration(labelText: 'اسم المتجر'),
                validator: (value) =>
                    (value?.trim().length ?? 0) < 2 ? 'اكتب اسم المتجر.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _description,
                maxLength: 5000,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'وصف المتجر'),
                validator: (value) => (value?.trim().length ?? 0) < 20
                    ? 'الوصف يجب أن يكون 20 حرفاً على الأقل.'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _tagline,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'عبارة تعريفية اختيارية',
                  hintText: 'مثال: استلام مباشر أو يوصل إلى بابك',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                maxLength: 18,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم هاتف المتجر'),
                validator: (value) =>
                    RegExp(r'^\+?[0-9]{7,18}$').hasMatch(value?.trim() ?? '')
                    ? null
                    : 'أدخل رقم هاتف صالحاً.',
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _whatsapp,
                maxLength: 18,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم WhatsApp (اختياري)', helperText: 'رقم مستقل لفتح محادثة WhatsApp'),
                validator: (value) => value == null || value.trim().isEmpty || RegExp(r'^\+?[0-9]{7,18}$').hasMatch(value.trim()) ? null : 'أدخل رقم WhatsApp صالحاً.',
              ),
              const SizedBox(height: 10),
              if (snapshot.connectionState != ConnectionState.done)
                const LinearProgressIndicator()
              else
                DropdownButtonFormField<String>(
                  value: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'قسم المتجر'),
                  items: categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.publicId,
                          child: Text(
                            category.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _categoryId = value),
                ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _address,
                maxLength: 255,
                decoration: const InputDecoration(labelText: 'عنوان المتجر (اختياري)'),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 16),
              if (_acceptsDelivery) ...[
                const SizedBox(height: 4),
                Text('إحداثيات التوصيل', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextFormField(controller: _latitude, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط العرض'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextFormField(controller: _longitude, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط الطول'))),
                ]),
                const SizedBox(height: 14),
              ],
              const Text(
                'خيارات البيع والاستلام',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _retail,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _retail = value),
                title: const Text('بيع بالتجزئة'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _preorder,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _preorder = value),
                title: const Text('طلب مسبق'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _acceptsDelivery,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _acceptsDelivery = value),
                title: const Text('أقبل التوصيل'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _acceptsPickup,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _acceptsPickup = value),
                title: const Text('أقبل الاستلام المباشر'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _activate,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _activate = value),
                title: const Text('تفعيل المتجر'),
                subtitle: const Text(
                  'يتطلب بيانات المتجر الأساسية وأوقات الدوام.',
                ),
              ),
              const SizedBox(height: 14),
              Card(
                color: const Color(0xFFF2FBF7),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _manualPaymentEnabled,
                        onChanged: _saving ? null : (value) => setState(() => _manualPaymentEnabled = value),
                        title: const Text('التحويل اليدوي'),
                        subtitle: const Text('يظهر للعميل عنوان الإيداع داخل سلة وطلب هذا المتجر فقط.'),
                      ),
                      if (_manualPaymentEnabled) ...[
                        const SizedBox(height: 8),
                        TextFormField(controller: _depositTitle, enabled: !_saving, maxLength: 160, decoration: const InputDecoration(labelText: 'عنوان الإيداع', hintText: 'مثال: التحويل إلى الحساب البنكي', counterText: '')),
                        const SizedBox(height: 10),
                        TextFormField(controller: _depositAddress, enabled: !_saving, maxLength: 1500, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'تفاصيل أو عنوان الإيداع', hintText: 'اسم البنك، رقم الحساب، اسم المستفيد…', alignLabelWithHint: true)),
                        const SizedBox(height: 10),
                        TextFormField(controller: _paymentInstructions, enabled: !_saving, maxLength: 1000, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'تعليمات للعميل (اختيارية)', hintText: 'مثال: أرسل صورة التحويل أو رقم العملية.', alignLabelWithHint: true)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded),
                          const SizedBox(width: 8),
                          Expanded(child: Text('ساعات الدوام', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                          TextButton(onPressed: _saving ? null : _copySaturdayToWeek, child: const Text('نسخ السبت')),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ..._hours.entries.map((entry) => _hoursRow(entry.key, entry.value)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        const Icon(Icons.event_busy_outlined),
                        const SizedBox(width: 8),
                        Expanded(child: Text('عطل استثنائية', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                        IconButton(tooltip: 'إضافة عطلة', onPressed: _saving ? null : () => setState(() => _holidays.add(_StoreHoliday(date: DateTime.now()))), icon: const Icon(Icons.add_circle_outline_rounded)),
                      ]),
                      ..._holidays.map(_holidayRow),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('حفظ إعدادات المتجر'),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _hoursRow(String day, _StoreHours hours) => Card(
    margin: const EdgeInsets.only(top: 8),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(children: [
            Icon(hours.closed ? Icons.do_not_disturb_on_outlined : Icons.calendar_today_outlined, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text(_dayLabels[day]!, style: const TextStyle(fontWeight: FontWeight.w900))),
            FilterChip(
              label: const Text('عطلة'),
              selected: hours.closed,
              onSelected: _saving ? null : (closed) => setState(() => _hours[day] = hours.copyWith(closed: closed)),
            ),
          ]),
          if (!hours.closed) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _saving ? null : () => _pickTime(day, opening: true), icon: const Icon(Icons.login_rounded, size: 18), label: Text(hours.opensAt))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _saving ? null : () => _pickTime(day, opening: false), icon: const Icon(Icons.logout_rounded, size: 18), label: Text(hours.closesAt))),
            ]),
          ],
        ],
      ),
    ),
  );

  Widget _holidayRow(_StoreHoliday holiday) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(children: [
          OutlinedButton.icon(onPressed: _saving ? null : () => _pickHolidayDate(holiday), icon: const Icon(Icons.calendar_month_outlined, size: 18), label: Text(_dateValue(holiday.date!))),
          const SizedBox(height: 7),
          TextField(controller: holiday.controller, enabled: !_saving, maxLength: 120, decoration: const InputDecoration(labelText: 'اسم العطلة (اختياري)', counterText: '')),
        ]),
      ),
      IconButton(tooltip: 'حذف العطلة', onPressed: _saving ? null : () => setState(() { _holidays.remove(holiday); holiday.dispose(); }), icon: const Icon(Icons.close_rounded)),
    ]),
  );

  Widget _logoPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        onPressed: _saving ? null : _pickLogo,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(_logo == null ? 'اختيار شعار المتجر' : 'تغيير شعار المتجر'),
      ),
      const SizedBox(height: 10),
      if (_logoPreview != null)
        FutureBuilder<Uint8List>(
          future: _logoPreview,
          builder: (context, snapshot) => _logoPreviewBox(
            snapshot.data == null
                ? null
                : Image.memory(snapshot.data!, fit: BoxFit.cover),
          ),
        )
      else if (widget.store['logo_media_public_id'] is String)
        _logoPreviewBox(
          CachedMediaImage(
            mediaPublicId: widget.store['logo_media_public_id'] as String,
            errorIcon: Icons.storefront_outlined,
          ),
        )
      else
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'أضف شعاراً عاماً حتى يمكن تفعيل المتجر.',
            textAlign: TextAlign.center,
          ),
        ),
    ],
  );

  Widget _logoPreviewBox(Widget? image) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(
      height: 150,
      child: ColoredBox(
        color: const Color(0xFFF0F2F4),
        child: Center(child: image ?? const CircularProgressIndicator()),
      ),
    ),
  );
}


final class _StoreHoliday {
  _StoreHoliday({DateTime? date, String label = ''}) : date = date, controller = TextEditingController(text: label);
  DateTime? date;
  final TextEditingController controller;
  void dispose() => controller.dispose();
}

final class _StoreHours {
  const _StoreHours({
    required this.closed,
    required this.opensAt,
    required this.closesAt,
  });
  final bool closed;
  final String opensAt;
  final String closesAt;

  factory _StoreHours.fromJson(dynamic value) {
    final data = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return _StoreHours(
      closed: data['closed'] == true,
      opensAt: _validTime(data['opens_at'] as String?) ?? '09:00',
      closesAt: _validTime(data['closes_at'] as String?) ?? '20:00',
    );
  }

  _StoreHours copyWith({bool? closed, String? opensAt, String? closesAt}) =>
      _StoreHours(
        closed: closed ?? this.closed,
        opensAt: opensAt ?? this.opensAt,
        closesAt: closesAt ?? this.closesAt,
      );

  Map<String, dynamic> toJson() => {
    'closed': closed,
    'opens_at': closed ? null : opensAt,
    'closes_at': closed ? null : closesAt,
  };

  static TimeOfDay toTimeOfDay(String raw) {
    final parts = raw.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  static String format(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String? _validTime(String? raw) =>
      raw != null && RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(raw)
      ? raw
      : null;
}
