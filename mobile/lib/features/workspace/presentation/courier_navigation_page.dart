import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Task map for an assigned courier. Addresses originate from immutable order
/// snapshots, while the moving blue marker comes only from device GPS.
final class CourierNavigationPage extends StatefulWidget {
  const CourierNavigationPage({super.key, required this.task});
  final Map<String, dynamic> task;

  @override
  State<CourierNavigationPage> createState() => _CourierNavigationPageState();
}

final class _CourierNavigationPageState extends State<CourierNavigationPage> {
  StreamSubscription<Position>? _positionSubscription;
  Position? _position;
  String? _locationMessage;

  Map<String, dynamic> _map(Object? raw) => raw is Map
      ? Map<String, dynamic>.from(raw)
      : const <String, dynamic>{};

  double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse('${value ?? ''}');

  LatLng? _location(Object? raw) {
    final value = _map(raw);
    final latitude = _number(value['latitude']);
    final longitude = _number(value['longitude']);
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }

  Future<void> _track() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _locationMessage = 'فعّل خدمة الموقع في الجهاز لاستخدام الملاحة.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => _locationMessage = 'إذن الموقع غير متاح. يمكنك فتح المسار الخارجي فقط.');
      return;
    }
    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((value) {
      if (mounted) setState(() => _position = value);
    });
  }

  @override
  void initState() {
    super.initState();
    _track();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _openNavigation(LatLng destination) async {
    final from = _position == null
        ? ''
        : '${_position!.latitude},${_position!.longitude};';
    final uri = Uri.parse(
      'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=$from${destination.latitude},${destination.longitude}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح تطبيق الملاحة.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _map(widget.task['store']);
    final pickupAddress = _map(widget.task['pickup_address'] ?? store);
    final dropoff = _location(widget.task['delivery_address']);
    final pickup = _location(pickupAddress);
    final status = widget.task['task_status'] as String? ?? '';
    final destination = status == 'accepted' || status == 'en_route_pickup'
        ? pickup
        : dropoff;
    final center = destination ?? dropoff ?? pickup ?? const LatLng(50.1109, 8.6821);
    final markers = <Marker>[
      if (pickup != null)
        Marker(point: pickup, width: 56, height: 56, child: const Icon(Icons.storefront_rounded, color: Color(0xFF125F4F), size: 38)),
      if (dropoff != null)
        Marker(point: dropoff, width: 56, height: 56, child: const Icon(Icons.location_on_rounded, color: Colors.red, size: 44)),
      if (_position != null)
        Marker(point: LatLng(_position!.latitude, _position!.longitude), width: 42, height: 42, child: const Icon(Icons.navigation_rounded, color: Colors.blue, size: 36)),
    ];
    final customerAddress = _map(widget.task['delivery_address']);
    return Scaffold(
      appBar: AppBar(title: const Text('خريطة المهمة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.task['order_number'] as String? ?? 'مهمة توصيل', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 6),
                Text('المسافة المعتمدة: ${widget.task['delivery_distance_km'] ?? '—'} كم'),
                Text('رسوم المهمة: ${widget.task['delivery_fee_amount'] ?? 0} ${widget.task['currency_code'] ?? 'USD'}'),
                if (_position != null) Text('سرعتك الحالية: ${(_position!.speed * 3.6).clamp(0, 240).toStringAsFixed(0)} كم/س'),
                if (_locationMessage != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text(_locationMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 350,
              child: FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 14),
                children: [
                  TileLayer(urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', subdomains: const ['a', 'b', 'c'], userAgentPackageName: 'com.tijarti.mobile'),
                  if (pickup != null && dropoff != null) PolylineLayer(polylines: [Polyline(points: [pickup, dropoff], strokeWidth: 3, color: Theme.of(context).colorScheme.primary)]),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(widget.task['source_type'] == 'marketplace_transaction'
                  ? 'نقطة استلام السلعة'
                  : 'نقطة الاستلام: ${store['name'] ?? 'المتجر'}'),
              subtitle: Text('${pickupAddress['city'] ?? ''} ${pickupAddress['address_line1'] ?? 'الموقع مسجل على الخريطة'}'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_pin_circle_outlined),
              title: Text('تسليم إلى: ${customerAddress['recipient_name'] ?? 'العميل'}'),
              subtitle: Text('${customerAddress['city'] ?? ''} ${customerAddress['address_line1'] ?? ''}'),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: destination == null ? null : () => _openNavigation(destination),
            icon: const Icon(Icons.navigation_rounded),
            label: Text(status == 'accepted' || status == 'en_route_pickup' ? 'ابدأ الملاحة إلى المتجر' : 'ابدأ الملاحة إلى العميل'),
          ),
          const SizedBox(height: 7),
          const Text('الخريطة تستخدم OpenStreetMap؛ فتح الملاحة يستخدم مسار OSRM العام التجريبي.', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
