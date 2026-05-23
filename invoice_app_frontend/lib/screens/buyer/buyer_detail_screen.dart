import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/address_search_field.dart';

class BuyerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> buyer;
  final bool isDeleted;

  const BuyerDetailScreen({super.key, required this.buyer, this.isDeleted = false});

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
  late final TextEditingController _emailController;
  late final TextEditingController _taxIdController;

  double? _selectedLat;
  double? _selectedLng;

  bool _isLoading = false;
  bool _isFetchingBusiness = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.buyer['buyer_code']);
    _nameController = TextEditingController(text: widget.buyer['buyer_name']);
    _addressController = TextEditingController(text: widget.buyer['address']);
    _phoneController = TextEditingController(text: widget.buyer['phone_number']);
    _idCardController = TextEditingController(text: widget.buyer['id_card_number']);
    _emailController = TextEditingController(text: widget.buyer['email']);
    _taxIdController = TextEditingController(text: widget.buyer['tax_id']);
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
    _emailController.dispose();
    _taxIdController.dispose();
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
      if (_emailController.text != widget.buyer['email']) updates['email'] = _emailController.text.trim().isEmpty ? null : _emailController.text.trim();
      if (_taxIdController.text != widget.buyer['tax_id']) updates['taxId'] = _taxIdController.text;
      
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

  Future<void> _restoreBuyer() async {
    setState(() => _isLoading = true);
    try {
      await _apiService.restoreBuyer(widget.buyer['buyer_id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Khôi phục người mua thành công')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteBuyer() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: const Text(
            'Bạn có chắc chắn muốn xóa người mua này không? Bạn có thể khôi phục lại từ Thùng rác.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              child: const Text('XÓA'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _apiService.deleteBuyer(widget.buyer['buyer_id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xóa người mua thành công')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDeleted ? 'Chi tiết người mua (Đã xóa)' : 'Chi tiết người mua'),
        actions: [
          if (widget.isDeleted)
            IconButton(
              icon: const Icon(Icons.restore_rounded),
              onPressed: _isLoading ? null : _restoreBuyer,
              tooltip: 'Khôi phục',
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _isLoading ? null : _deleteBuyer,
              tooltip: 'Xóa người mua',
            ),
            if (!_isLoading)
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _updateBuyer,
                tooltip: 'Lưu thay đổi',
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
          ]
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
                color: colorScheme.primaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _codeController,
                        enabled: !widget.isDeleted,
                        decoration: InputDecoration(
                          labelText: 'Mã người mua',
                          prefixIcon: const Icon(Icons.qr_code),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: colorScheme.surface,
                        ),
                        validator: (v) => v!.isEmpty ? 'Không được để trống' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _taxIdController,
                        enabled: !widget.isDeleted,
                        decoration: InputDecoration(
                          labelText: 'Mã số thuế (MST)',
                          prefixIcon: const Icon(Icons.description),
                          suffixIcon: widget.isDeleted
                            ? null
                            : (_isFetchingBusiness
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.search),
                                  onPressed: _lookupVietQR,
                                  tooltip: 'Lấy thông tin từ MST',
                                )),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: colorScheme.surface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        enabled: !widget.isDeleted,
                        decoration: InputDecoration(
                          labelText: 'Tên người mua',
                          prefixIcon: const Icon(Icons.person),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: colorScheme.surface,
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
              AddressSearchField(
                controller: _addressController,
                initialAddress: widget.buyer['address'],
                initialLat: _selectedLat,
                initialLng: _selectedLng,
                readOnly: widget.isDeleted,
                onLocationSelected: (lat, lng) {
                  setState(() {
                    _selectedLat = lat;
                    _selectedLng = lng;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                enabled: !widget.isDeleted,
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
                enabled: !widget.isDeleted,
                decoration: const InputDecoration(
                  labelText: 'Số CCCD / CMND',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                enabled: !widget.isDeleted,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final emailRegex = RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
                  if (!emailRegex.hasMatch(value.trim())) {
                    return 'Định dạng email không hợp lệ';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : (widget.isDeleted ? _restoreBuyer : _updateBuyer),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: widget.isDeleted ? colorScheme.primaryContainer : colorScheme.primary,
                    foregroundColor: widget.isDeleted ? colorScheme.onPrimaryContainer : colorScheme.onPrimary,
                  ),
                  icon: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(widget.isDeleted ? Icons.restore_rounded : Icons.save_rounded),
                  label: Text(
                    widget.isDeleted ? 'KHÔI PHỤC NGƯỜI MUA' : 'LƯU THAY ĐỔI',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
