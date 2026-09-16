import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// OpenStreetMap location selector. A tap or device GPS always moves both the
/// marker and map camera; parents can then reverse-geocode the selected point.
final class MapLocationPicker extends StatefulWidget {
  const MapLocationPicker({
    super.key,
    required this.onChanged,
    this.initialLocation,
    this.height = 270,
  });

  final ValueChanged<LatLng> onChanged;
  final LatLng? initialLocation;
  final double height;

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

final class _MapLocationPickerState extends State<MapLocationPicker> {
  static const _fallback = LatLng(50.1109, 8.6821); // Neutral initial map view.
  final MapController _mapController = MapController();
  late LatLng _point;
  LatLng? _pendingCameraMove;
  bool _mapReady = false;
  bool _locating = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _point = widget.initialLocation ?? _fallback;
  }

  @override
  void didUpdateWidget(covariant MapLocationPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialLocation;
    if (next != null && next != oldWidget.initialLocation) {
      _point = next;
      _moveCamera(next);
    }
  }

  void _moveCamera(LatLng point) {
    if (_mapReady) {
      _mapController.move(point, 16);
    } else {
      _pendingCameraMove = point;
    }
  }

  void _setPoint(LatLng value, {bool fromGps = false}) {
    setState(() {
      _point = value;
      _message = fromGps
          ? 'تم تحديد موقعك الحالي وتحديث الخريطة.'
          : 'تم تحديد الموقع على الخريطة.';
    });
    _moveCamera(value);
    widget.onChanged(value);
  }

  Future<void> _useDeviceLocation() async {
    setState(() {
      _locating = true;
      _message = 'جارٍ طلب موقعك الحالي…';
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationMessage('فعّل خدمة الموقع GPS في الجهاز ثم أعد المحاولة.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw const _LocationMessage('لم يتم منح إذن الموقع. اختر نقطة من الخريطة أو فعّل الإذن من الإعدادات.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _setPoint(LatLng(position.latitude, position.longitude), fromGps: true);
    } on _LocationMessage catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'تعذر تحديد موقعك. تحقق من GPS والإنترنت ثم أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: widget.height,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _point,
                initialZoom: widget.initialLocation == null ? 12 : 16,
                onMapReady: () {
                  _mapReady = true;
                  final pending = _pendingCameraMove;
                  if (pending != null) {
                    _pendingCameraMove = null;
                    _mapController.move(pending, 16);
                  }
                },
                onTap: (_, point) => _setPoint(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.tijarti.mobile',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _point,
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.location_on_rounded,
                        color: scheme.primary,
                        size: 46,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _locating ? null : _useDeviceLocation,
              icon: _locating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded),
              label: const Text('استخدم GPS'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _message ?? 'انقر على الخريطة لتحديد عنوان التوصيل بدقة.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final class _LocationMessage implements Exception {
  const _LocationMessage(this.message);
  final String message;
}
