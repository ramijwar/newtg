import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/map_location_picker.dart';
import '../domain/commerce_models.dart';

/// A customer has one current delivery address, reused by store checkout and
/// marketplace delivery requests. Orders retain their own address snapshots.
final class AddressesPage extends StatefulWidget {
  const AddressesPage({super.key});

  @override
  State<AddressesPage> createState() => _AddressesPageState();
}

final class _AddressesPageState extends State<AddressesPage> {
  Future<List<CustomerAddress>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).loadAddresses();
  }

  void _reload() => setState(() => _future = AppScope.of(context).loadAddresses());

  Future<void> _openForm([CustomerAddress? address]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => AddressFormPage(address: address)),
    );
    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('عنوان التوصيل')),
        body: FutureBuilder<List<CustomerAddress>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              );
            }
            final address = (snapshot.data ?? const <CustomerAddress>[]).isEmpty
                ? null
                : snapshot.data!.first;
            if (address == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(25),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 43,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'حدّد عنوان التوصيل',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'سيُستخدم هذا العنوان تلقائياً عند الشراء أو طلب خدمة التوصيل.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _openForm,
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: const Text('إعداد عنوان التوصيل'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            final location = [
              address.city,
              address.district,
              address.addressLine1,
              address.addressLine2,
            ].whereType<String>().where((part) => part.trim().isNotEmpty).join('، ');
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                Text(
                  'عنوانك المعتمد للتوصيل',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  'يُستخدم تلقائياً في الطلبات وخدمة التوصيل. يمكنك تعديله في أي وقت.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            Icons.home_work_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('عنوان التوصيل', style: TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 5),
                              Text(location),
                              if (address.latitude != null && address.longitude != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.verified_rounded, size: 17, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 5),
                                    const Text('تم تحديد الموقع على الخريطة'),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () => _openForm(address),
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('تعديل عنوان التوصيل'),
                ),
              ],
            );
          },
        ),
      );
}

final class AddressFormPage extends StatefulWidget {
  const AddressFormPage({super.key, this.address});
  final CustomerAddress? address;

  @override
  State<AddressFormPage> createState() => _AddressFormPageState();
}

final class _AddressFormPageState extends State<AddressFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _country;
  late final TextEditingController _city;
  late final TextEditingController _district;
  late final TextEditingController _line1;
  late final TextEditingController _line2;
  LatLng? _selectedPoint;
  bool _saving = false;
  bool _reverseGeocoding = false;
  String? _locationMessage;
  int _lookupVersion = 0;

  @override
  void initState() {
    super.initState();
    final item = widget.address;
    _country = TextEditingController(text: item?.countryCode ?? '');
    _city = TextEditingController(text: item?.city ?? '');
    _district = TextEditingController(text: item?.district ?? '');
    _line1 = TextEditingController(text: item?.addressLine1 ?? '');
    _line2 = TextEditingController(text: item?.addressLine2 ?? '');
    _selectedPoint = item?.latitude != null && item?.longitude != null
        ? LatLng(item!.latitude!, item!.longitude!)
        : null;
  }

  @override
  void dispose() {
    for (final controller in [_country, _city, _district, _line1, _line2]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value, String label, int min) =>
      (value?.trim().length ?? 0) < min ? '$label مطلوب.' : null;

  Future<void> _applyMapPoint(LatLng point) async {
    final version = ++_lookupVersion;
    setState(() {
      _selectedPoint = point;
      _reverseGeocoding = true;
      _locationMessage = 'جارٍ التعرف على العنوان من الموقع…';
    });
    try {
      final result = await AppScope.of(context).reverseGeocodeAddress(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (!mounted || version != _lookupVersion) return;
      final country = result['country_code'] as String? ?? '';
      final city = result['city'] as String? ?? '';
      final district = result['district'] as String? ?? '';
      final line1 = result['address_line1'] as String? ?? '';
      setState(() {
        if (country.isNotEmpty) _country.text = country;
        if (city.isNotEmpty) _city.text = city;
        if (district.isNotEmpty) _district.text = district;
        if (line1.isNotEmpty) _line1.text = line1;
        _locationMessage = city.isNotEmpty || line1.isNotEmpty
            ? 'تمت تعبئة بيانات العنوان من الخريطة. راجعها قبل الحفظ.'
            : 'تم تحديد الموقع. أدخل المدينة والشارع لإكمال العنوان.';
      });
    } on ApiException catch (error) {
      if (!mounted || version != _lookupVersion) return;
      setState(() => _locationMessage = error.message);
    } catch (_) {
      if (!mounted || version != _lookupVersion) return;
      setState(() => _locationMessage = 'تم تحديد الموقع، لكن تعذر تعبئة العنوان تلقائياً. أكمل الحقول يدوياً.');
    } finally {
      if (mounted && version == _lookupVersion) {
        setState(() => _reverseGeocoding = false);
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد موقع التوصيل على الخريطة أو استخدم GPS أولاً.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final session = AppScope.of(context).session;
      await AppScope.of(context).saveAddress(
        CustomerAddress(
          publicId: widget.address?.publicId ?? '',
          label: 'عنوان التوصيل',
          recipientName: session?.fullName ?? widget.address?.recipientName ?? '',
          phone: session?.user['phone'] as String? ?? widget.address?.phone ?? '',
          countryCode: _country.text,
          city: _city.text,
          district: _district.text.trim().isEmpty ? null : _district.text,
          addressLine1: _line1.text,
          addressLine2: _line2.text.trim().isEmpty ? null : _line2.text,
          latitude: _selectedPoint!.latitude,
          longitude: _selectedPoint!.longitude,
          isDefault: true,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.address == null ? 'إعداد عنوان التوصيل' : 'تعديل عنوان التوصيل'),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                'حدّد موقعك أولاً',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                'استخدم GPS أو انقر على الخريطة؛ سنملأ المدينة والشارع تلقائياً عندما تكون البيانات متاحة.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              MapLocationPicker(
                initialLocation: _selectedPoint,
                onChanged: _applyMapPoint,
              ),
              if (_reverseGeocoding || _locationMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(.52),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      if (_reverseGeocoding)
                        const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(Icons.auto_fix_high_rounded, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 9),
                      Expanded(child: Text(_locationMessage ?? 'تم تحديد الموقع.')),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Text('تفاصيل العنوان', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(
                  labelText: 'المدينة *',
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                validator: (value) => _required(value, 'المدينة', 2),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _line1,
                decoration: const InputDecoration(
                  labelText: 'الشارع ورقم المبنى *',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
                validator: (value) => _required(value, 'الشارع ورقم المبنى', 3),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _district,
                decoration: const InputDecoration(
                  labelText: 'المنطقة أو الحي (اختياري)',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _line2,
                decoration: const InputDecoration(
                  labelText: 'تفاصيل إضافية (اختيارية)',
                  hintText: 'مثال: الطابق أو رقم الشقة',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ عنوان التوصيل'),
              ),
            ],
          ),
        ),
      );
}
