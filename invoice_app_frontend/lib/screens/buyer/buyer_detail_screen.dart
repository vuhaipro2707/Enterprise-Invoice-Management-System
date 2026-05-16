import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:uuid/uuid.dart';
import '../../services/api_service.dart';

class BuyerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> buyer;

  const BuyerDetailScreen({super.key, required this.buyer});

  @override
  State<BuyerDetailScreen> createState() => _BuyerDetailScreenState();
}

class _BuyerDetailScreenState extends State<BuyerDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();

  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _idCardController;

  String? _sessionToken;
  double? _selectedLat;
  double? _selectedLng;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.buyer['buyer_code']);
    _nameController = TextEditingController(text: widget.buyer['buyer_name']);
    _addressController = TextEditingController(text: widget.buyer['address']);
    _phoneController = TextEditingController(text: widget.buyer['phone_number']);
    _idCardController = TextEditingController(text: widget.buyer['id_card_number']);
    _selectedLat = widget.buyer['lat'] != null ? (widget.buyer['lat'] as num).toDouble() : null;
    _selectedLng = widget.buyer['lng'] != null ? (widget.buyer['lng'] as num).toDouble() : null;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _idCardController.dispose();
    super.dispose();
  }

  Future<void> _updateBuyer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final updates = <String, dynamic>{};
      if (_codeController.text != widget.buyer['buyer_code']) updates['buyerCode'] = _codeController.text;
      if (_nameController.text != widget.buyer['buyer_name']) updates['buyerName'] = _nameController.text;
      if (_addressController.text != widget.buyer['address']) updates['address'] = _addressController.text;
      if (_phoneController.text != widget.buyer['phone_number']) updates['phoneNumber'] = _phoneController.text;
      if (_idCardController.text != widget.buyer['id_card_number']) updates['idCardNumber'] = _idCardController.text;
      
      // Update coordinates if they changed or were not set
      if (_selectedLat != (widget.buyer['lat'] != null ? (widget.buyer['lat'] as num).toDouble() : null)) {
        updates['lat'] = _selectedLat;
      }
      if (_selectedLng != (widget.buyer['lng'] != null ? (widget.buyer['lng'] as num).toDouble() : null)) {
        updates['lng'] = _selectedLng;
      }

      if (updates.isEmpty) {
        Navigator.pop(context);
        return;
      }

      await _apiService.patchBuyer(widget.buyer['buyer_id'], updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật người mua thành công')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        bool isDuplicate = errorMessage.contains('buyers_buyer_code_key');

        if (isDuplicate) {
          errorMessage = 'Mã khách hàng đã tồn tại. Vui lòng sử dụng mã khác.';
        } else if (errorMessage.contains('Exception: ')) {
          errorMessage = errorMessage.replaceAll('Exception: ', '');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết người mua'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _updateBuyer,
            )
          else
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _codeController,
                        decoration: InputDecoration(
                          labelText: 'Mã người mua',
                          prefixIcon: const Icon(Icons.qr_code),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                        validator: (v) => v!.isEmpty ? 'Không được để trống' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Tên người mua',
                          prefixIcon: const Icon(Icons.person),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                        validator: (v) => v!.isEmpty ? 'Không được để trống' : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Thông tin liên hệ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TypeAheadField<dynamic>(
                controller: _addressController,
                builder: (context, controller, focusNode) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ',
                      prefixIcon: Icon(Icons.location_on),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  );
                },
                suggestionsCallback: (search) async {
                  if (search.trim().length < 3 || search.trim() == widget.buyer['address']) return [];
                  _sessionToken ??= const Uuid().v4();
                  return await _apiService.googleAutocomplete(search, sessionToken: _sessionToken);
                },
                itemBuilder: (context, prediction) {
                  return ListTile(
                    leading: const Icon(Icons.location_on),
                    title: Text(prediction['structured_formatting']?['main_text'] ?? prediction['description'] ?? ''),
                    subtitle: Text(prediction['structured_formatting']?['secondary_text'] ?? ''),
                  );
                },
                emptyBuilder: (context) => const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Hãy nhập địa chỉ cần tìm kiếm', style: TextStyle(color: Colors.grey)),
                ),
                onSelected: (prediction) async {
                  _addressController.text = prediction['description'];
                  final placeId = prediction['place_id'];
                  final details = await _apiService.googlePlaceDetails(placeId, sessionToken: _sessionToken);
                  
                  _sessionToken = null;

                  if (details != null && details['geometry']?['location'] != null) {
                    setState(() {
                      _selectedLat = (details['geometry']['location']['lat'] as num).toDouble();
                      _selectedLng = (details['geometry']['location']['lng'] as num).toDouble();
                    });
                    debugPrint('New selection location: $_selectedLat, $_selectedLng');
                  }
                },
              ),
              const SizedBox(height: 16),
              getCoordinateWidget(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idCardController,
                decoration: const InputDecoration(
                  labelText: 'Số CCCD / CMND',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateBuyer,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator()
                    : const Text('LƯU THAY ĐỔI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget getCoordinateWidget() {
    final hasCoords = _selectedLat != null && _selectedLng != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                  ? 'Đã xác định tọa độ: ${_selectedLat!.toStringAsFixed(4)}, ${_selectedLng!.toStringAsFixed(4)}'
                  : 'Chưa xác định tọa độ (Chọn địa chỉ từ gợi ý)',
              style: TextStyle(
                color: hasCoords ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
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
                final url = 'https://www.google.com/maps/dir/?api=1&destination=$_selectedLat,$_selectedLng';
                await _apiService.launchURL(url);
              },
              tooltip: 'Dẫn đường',
            ),
        ],
      ),
    );
  }
}
