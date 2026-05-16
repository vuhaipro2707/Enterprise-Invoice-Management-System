import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:uuid/uuid.dart';
import '../../services/api_service.dart';

class CreateBuyerScreen extends StatefulWidget {
  const CreateBuyerScreen({super.key});

  @override
  State<CreateBuyerScreen> createState() => _CreateBuyerScreenState();
}

class _CreateBuyerScreenState extends State<CreateBuyerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _idCardController = TextEditingController();

  String? _sessionToken;
  double? _selectedLat;
  double? _selectedLng;

  bool _isLoading = false;
  bool _isGeneratingCode = false;

  @override
  void initState() {
    super.initState();
    _autoGenerateCode();
  }

  Future<void> _autoGenerateCode() async {
    setState(() => _isGeneratingCode = true);
    try {
      final code = await _apiService.getNextBuyerCode();
      setState(() {
        _codeController.text = code;
      });
    } catch (e) {
      debugPrint('Error generating code: $e');
    } finally {
      setState(() => _isGeneratingCode = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final body = {
        'buyerCode': _codeController.text.trim(),
        'buyerName': _nameController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        'phoneNumber': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'idCardNumber': _idCardController.text.trim().isEmpty ? null : _idCardController.text.trim(),
        'lat': _selectedLat,
        'lng': _selectedLng,
      };

      await _apiService.createBuyer(body);
      
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo người mua thành công')),
        );
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
        title: const Text('Thêm người mua mới'),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
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
                              labelText: 'Mã người mua *',
                              prefixIcon: const Icon(Icons.badge),
                              suffixIcon: _isGeneratingCode 
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.refresh),
                                    onPressed: _autoGenerateCode,
                                    tooltip: 'Tự động tạo mã',
                                  ),
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                            ),
                            validator: (value) => 
                              value == null || value.isEmpty ? 'Vui lòng nhập mã' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Tên người mua *',
                              prefixIcon: const Icon(Icons.person),
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                            ),
                            validator: (value) => 
                               value == null || value.isEmpty ? 'Vui lòng nhập tên' : null,
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
                      if (search.trim().length < 3) return [];
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
                      
                      // Clear token after session ends
                      _sessionToken = null;

                      if (details != null && details['geometry']?['location'] != null) {
                        setState(() {
                          _selectedLat = (details['geometry']['location']['lat'] as num).toDouble();
                          _selectedLng = (details['geometry']['location']['lng'] as num).toDouble();
                        });
                        debugPrint('Selected location: $_selectedLat, $_selectedLng');
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  getCoordinateWidget(),
                  const SizedBox(height: 8),
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
                      labelText: 'Số CMND/CCCD',
                      prefixIcon: Icon(Icons.credit_card),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Tạo người mua', 
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _idCardController.dispose();
    super.dispose();
  }
}
