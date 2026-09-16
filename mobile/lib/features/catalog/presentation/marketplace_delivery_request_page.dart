import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/map_location_picker.dart';
import '../../commerce/domain/commerce_models.dart';

/// A marketplace sale keeps separate pickup/drop-off points. The customer's
/// single saved delivery address is preselected as the drop-off point.
final class MarketplaceDeliveryRequestPage extends StatefulWidget {
  const MarketplaceDeliveryRequestPage({super.key, required this.transactionId});
  final String transactionId;

  @override
  State<MarketplaceDeliveryRequestPage> createState() => _MarketplaceDeliveryRequestPageState();
}

final class _MarketplaceDeliveryRequestPageState extends State<MarketplaceDeliveryRequestPage> {
  LatLng? _pickup;
  LatLng? _dropoff;
  CustomerAddress? _savedAddress;
  bool _addressLoading = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_savedAddress == null && !_addressLoading) _loadSavedAddress();
  }

  Future<void> _loadSavedAddress() async {
    setState(() => _addressLoading = true);
    try {
      final addresses = await AppScope.of(context).loadAddresses();
      if (!mounted || addresses.isEmpty) return;
      final address = addresses.first;
      setState(() {
        _savedAddress = address;
        if (_dropoff == null && address.latitude != null && address.longitude != null) {
          _dropoff = LatLng(address.latitude!, address.longitude!);
        }
      });
    } catch (_) {
      // The picker remains usable if the address cannot be loaded now.
    } finally {
      if (mounted) setState(() => _addressLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_saving || _pickup == null || _dropoff == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدد نقطة الاستلام ونقطة التسليم على الخريطة.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.of(context).requestMarketplaceDelivery(
        transactionId: widget.transactionId,
        pickupAddress: {'latitude': _pickup!.latitude, 'longitude': _pickup!.longitude},
        deliveryAddress: {'latitude': _dropoff!.latitude, 'longitude': _dropoff!.longitude},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء طلب التوصيل، وسيحسب الخادم الرسوم ومسار المهمة.')));
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('طلب توصيل الصفقة')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'حدّد الموقعين بدقة. رسوم التوصيل لا تدخل يدوياً؛ يحسبها الخادم وفق المسافة.',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 18),
            Text('موقع استلام السلعة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            MapLocationPicker(height: 220, initialLocation: _pickup, onChanged: (point) => setState(() => _pickup = point)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Text('موقع تسليم السلعة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                if (_savedAddress != null) const Icon(Icons.verified_rounded, color: Color(0xFF125F4F), size: 19),
              ],
            ),
            if (_addressLoading) const Padding(padding: EdgeInsets.only(top: 7), child: LinearProgressIndicator())
            else if (_savedAddress != null)
              Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 8),
                child: Text(
                  'تم استخدام عنوان التوصيل المعتمد: ${[_savedAddress!.city, _savedAddress!.district, _savedAddress!.addressLine1].whereType<String>().where((value) => value.trim().isNotEmpty).join('، ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 5, bottom: 8),
                child: Text('لا يوجد عنوان توصيل محفوظ؛ حدده هنا أو أضفه من حسابي.'),
              ),
            MapLocationPicker(height: 220, initialLocation: _dropoff, onChanged: (point) => setState(() => _dropoff = point)),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(_saving ? 'جارٍ إنشاء الطلب…' : 'إرسال طلب التوصيل'),
            ),
          ],
        ),
      );
}
