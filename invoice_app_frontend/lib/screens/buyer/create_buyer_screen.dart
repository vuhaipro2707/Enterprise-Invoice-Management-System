import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/address_search_field.dart';

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
  final _taxIdController = TextEditingController();

  double? _selectedLat;
  double? _selectedLng;

  bool _isLoading = false;
  bool _isGeneratingCode = false;
  bool _isFetchingBusiness = false;

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
        'taxId': _taxIdController.text.trim().isEmpty ? null : _taxIdController.text.trim(),
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
        } else if (errorMessage.contains('Code mismatch!')) {
          final nextCode = errorMessage.split('is ').last;
          errorMessage = 'Nhảy số! Mã tiếp theo phải là $nextCode. Vui lòng làm mới.';
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

  Future<void> _lookupVietQR() async {
    final taxId = _taxIdController.text.trim();
    if (taxId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mã số thuế')),
      );
      return;
    }

    setState(() => _isFetchingBusiness = true);
    try {
      final business = await _apiService.fetchVietQRBusiness(taxId);
      if (business != null) {
        setState(() {
          _nameController.text = business['name'] ?? '';
          _addressController.text = business['address'] ?? '';
        });

        final address = business['address'];
        if (address != null && address.isNotEmpty) {
          final coords = await _apiService.googleGeocode(address);
          if (coords != null) {
            setState(() {
              _selectedLat = coords['lat'];
              _selectedLng = coords['lng'];
            });
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã tự động điền thông tin doanh nghiệp')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không tìm thấy thông tin doanh nghiệp cho MST này')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi truy vấn thông tin doanh nghiệp: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingBusiness = false);
      }
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
                            controller: _taxIdController,
                            decoration: InputDecoration(
                              labelText: 'Mã số thuế (MST)',
                              prefixIcon: const Icon(Icons.description),
                              suffixIcon: _isFetchingBusiness
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: _lookupVietQR,
                                    tooltip: 'Lấy thông tin từ MST',
                                  ),
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                            ),
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
                  AddressSearchField(
                    controller: _addressController,
                    initialLat: _selectedLat,
                    initialLng: _selectedLng,
                    onLocationSelected: (lat, lng) {
                      setState(() {
                        _selectedLat = lat;
                        _selectedLng = lng;
                      });
                    },
                  ),
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

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _idCardController.dispose();
    _taxIdController.dispose();
    super.dispose();
  }
}
