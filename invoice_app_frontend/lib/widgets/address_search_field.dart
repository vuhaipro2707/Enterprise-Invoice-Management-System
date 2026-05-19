import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_service.dart';

class AddressSearchField extends StatefulWidget {
  final TextEditingController controller;
  final Function(double lat, double lng) onLocationSelected;
  final String? initialAddress;
  final double? initialLat;
  final double? initialLng;

  const AddressSearchField({
    super.key,
    required this.controller,
    required this.onLocationSelected,
    this.initialAddress,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  final _apiService = ApiService();
  String? _sessionToken;
  final FocusNode _focusNode = FocusNode();
  bool _isMapLoading = false;
  bool _isGeocoding = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }

    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition();
  }

  void _showMapPicker() async {
    setState(() => _isMapLoading = true);

    try {
      final LatLng initialPoint =
          (widget.initialLat != null && widget.initialLng != null)
          ? LatLng(widget.initialLat!, widget.initialLng!)
          : const LatLng(10.762622, 106.660172); // Mặc định TP.HCM

      LatLng selectedPoint = initialPoint;
      LatLng? userLocation;

      // Lấy vị trí ngay từ đầu nếu không có initial pin
      if (widget.initialLat == null || widget.initialLng == null) {
        final pos = await _getCurrentLocation();
        if (pos != null) {
          userLocation = LatLng(pos.latitude, pos.longitude);
          selectedPoint = userLocation;
        }
      } else {
        // Nếu có pin rồi, vẫn lấy user location để hiện chấm xanh
        _getCurrentLocation().then((pos) {
          if (pos != null && mounted) {
            userLocation = LatLng(pos.latitude, pos.longitude);
          }
        });
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) {
          final mapController = MapController();
          return StatefulBuilder(
            builder: (builderContext, setDialogState) => AlertDialog(
              title: const Text('Chọn vị trí từ bản đồ'),
              contentPadding: EdgeInsets.zero,
              content: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(builderContext).colorScheme.outlineVariant,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                width: double.maxFinite,
                height: 400,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: selectedPoint,
                        initialZoom: 15,
                        onTap: (tapPosition, point) {
                          setDialogState(() {
                            selectedPoint = point;
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.thanhhai.invoice_app',
                          maxZoom: 19,
                        ),
                        // Copyright widget
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                builderContext,
                              ).colorScheme.surface.withValues(alpha: 0.8),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                              ),
                            ),
                            child: InkWell(
                              onTap: () => _apiService.launchURL(
                                'https://openstreetmap.org/copyright',
                              ),
                              child: const Text(
                                '© OpenStreetMap',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ),
                        ),
                        MarkerLayer(
                          markers: [
                            // User Location Marker (Blue Dot)
                            if (userLocation != null)
                              Marker(
                                point: userLocation!,
                                width: 20,
                                height: 20,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.3),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // Selected Pin Marker
                            Marker(
                              point: selectedPoint,
                              width: 40,
                              height: 40,
                              alignment: Alignment.topCenter,
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Nút Zoom & GPS
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Column(
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'zoom_in',
                            onPressed: () {
                              mapController.move(
                                mapController.camera.center,
                                mapController.camera.zoom + 1,
                              );
                            },
                            child: const Icon(Icons.add),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'zoom_out',
                            onPressed: () {
                              mapController.move(
                                mapController.camera.center,
                                mapController.camera.zoom - 1,
                              );
                            },
                            child: const Icon(Icons.remove),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'my_location',
                            onPressed: () async {
                              final pos = await _getCurrentLocation();
                              if (pos != null) {
                                final newPos = LatLng(
                                  pos.latitude,
                                  pos.longitude,
                                );
                                setDialogState(() {
                                  userLocation = newPos;
                                });
                                mapController.move(newPos, 16);
                              }
                            },
                            child: const Icon(Icons.my_location),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'go_to_pin',
                            onPressed: () {
                              mapController.move(selectedPoint, 16);
                            },
                            child: const Icon(
                              Icons.location_searching,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Chạm để chọn vị trí',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final lat = selectedPoint.latitude;
                    final lng = selectedPoint.longitude;
                    Navigator.pop(dialogContext);

                    // Nếu tọa độ không đổi so với lúc mở map, không làm gì cả
                    if (lat == initialPoint.latitude &&
                        lng == initialPoint.longitude &&
                        widget.controller.text.isNotEmpty) {
                      return;
                    }

                    // Hiển thị loading trong TextField
                    setState(() {
                      _isGeocoding = true;
                      widget.controller.text = 'Đang xác định địa chỉ...';
                    });

                    final address = await _apiService.googleReverseGeocode(
                      lat,
                      lng,
                    );

                    if (mounted) {
                      setState(() {
                        _isGeocoding = false;
                        if (address != null) {
                          widget.controller.text = address;
                          widget.onLocationSelected(lat, lng);
                          // Bỏ focus để không hiện suggestion của TypeAhead
                          _focusNode.unfocus();
                        } else {
                          widget.controller.text = '';
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Không thể xác định địa chỉ từ tọa độ đã chọn',
                              ),
                            ),
                          );
                        }
                      });
                    }
                  },
                  child: const Text('Xác nhận'),
                ),
              ],
            ),
          );
        },
      ).then((_) {
        if (mounted) {
          setState(() => _isMapLoading = false);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isMapLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi khi mở bản đồ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TypeAheadField<dynamic>(
          controller: widget.controller,
          focusNode: _focusNode,
          builder: (context, controller, focusNode) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              enabled: !_isGeocoding,
              decoration: InputDecoration(
                labelText: 'Địa chỉ',
                prefixIcon: const Icon(Icons.location_on),
                suffixIcon: _isMapLoading || _isGeocoding
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.map),
                        onPressed: _showMapPicker,
                        tooltip: 'Chọn từ bản đồ',
                      ),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            );
          },
          suggestionsCallback: (search) async {
            if (search.trim().length < 3 ||
                (widget.initialAddress != null &&
                    search.trim() == widget.initialAddress)) {
              return [];
            }
            _sessionToken ??= const Uuid().v4();
            return await _apiService.googleAutocomplete(
              search,
              sessionToken: _sessionToken,
            );
          },
          itemBuilder: (context, prediction) {
            return ListTile(
              leading: const Icon(Icons.location_on),
              title: Text(
                prediction['structured_formatting']?['main_text'] ??
                    prediction['description'] ??
                    '',
              ),
              subtitle: Text(
                prediction['structured_formatting']?['secondary_text'] ?? '',
              ),
            );
          },
          emptyBuilder: (builderContext) => const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Hãy nhập địa chỉ cần tìm kiếm',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          onSelected: (prediction) async {
            widget.controller.text = prediction['description'];
            final placeId = prediction['place_id'];
            final details = await _apiService.googlePlaceDetails(
              placeId,
              sessionToken: _sessionToken,
            );

            _sessionToken = null;

            if (details != null && details['geometry']?['location'] != null) {
              final lat = (details['geometry']['location']['lat'] as num)
                  .toDouble();
              final lng = (details['geometry']['location']['lng'] as num)
                  .toDouble();
              widget.onLocationSelected(lat, lng);
            }
          },
        ),
        const SizedBox(height: 16),
        getCoordinateWidget(),
      ],
    );
  }

  Widget getCoordinateWidget() {
    final hasCoords = widget.initialLat != null && widget.initialLng != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasCoords
            ? colorScheme.primary.withValues(alpha: 0.1)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasCoords
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasCoords ? Icons.check_circle : Icons.location_off,
            color: hasCoords ? colorScheme.primary : colorScheme.outline,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasCoords
                  ? 'Đã xác định tọa độ: ${widget.initialLat!.toStringAsFixed(4)}, ${widget.initialLng!.toStringAsFixed(4)}'
                  : 'Chưa xác định tọa độ (Chọn địa chỉ hoặc Ghim map)',
              style: TextStyle(
                color: hasCoords
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          if (hasCoords && !kIsWeb && Platform.isAndroid)
            IconButton(
              icon: Icon(Icons.directions, color: colorScheme.primary),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
              onPressed: () async {
                final url =
                    'https://www.google.com/maps/dir/?api=1&destination=${widget.initialLat},${widget.initialLng}';
                await _apiService.launchURL(url);
              },
              tooltip: 'Dẫn đường',
            ),
        ],
      ),
    );
  }
}
