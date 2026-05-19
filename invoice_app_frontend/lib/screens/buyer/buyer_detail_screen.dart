import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/address_search_field.dart';

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
              AddressSearchField(
                controller: _addressController,
                initialAddress: widget.buyer['address'],
                initialLat: _selectedLat,
                initialLng: _selectedLng,
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
}
