import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/address_search_field.dart';

class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key});

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _buyerCodeController = TextEditingController();
  final _invoiceCodeController = TextEditingController();
  final _buyerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _selectedBuyerId;
  double? _selectedLat;
  double? _selectedLng;
  bool _isLoading = false;
  bool _isFetchingBuyer = false;
  bool _isFetchingInvoiceCode = false;

  @override
  void initState() {
    super.initState();
    _fetchNextInvoiceCode();
  }

  Future<void> _fetchNextInvoiceCode() async {
    setState(() => _isFetchingInvoiceCode = true);
    try {
      final code = await ApiService().getNextInvoiceCode();
      if (code.isNotEmpty) {
        _invoiceCodeController.text = code;
      }
    } catch (e) {
      debugPrint('Error fetching next invoice code: $e');
    } finally {
      if (mounted) setState(() => _isFetchingInvoiceCode = false);
    }
  }

  Future<void> _lookupBuyer() async {
    final code = _buyerCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isFetchingBuyer = true);
    try {
      final buyer = await ApiService().getBuyerByCode(code);
      setState(() {
        _selectedBuyerId = buyer['buyer_id'];
        _buyerNameController.text = buyer['buyer_name'] ?? '';
        _selectedLat = buyer['lat'] != null ? (buyer['lat'] as num).toDouble() : null;
        _selectedLng = buyer['lng'] != null ? (buyer['lng'] as num).toDouble() : null;
        _addressController.text = buyer['address'] ?? '';
        _phoneController.text = buyer['phone_number'] ?? '';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tìm thấy mã khách hàng: $code')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingBuyer = false);
    }
  }

  Future<void> _searchBuyerAdvanced() async {
    final buyer = await Navigator.pushNamed(context, '/buyer_search');
    if (buyer != null && buyer is Map<String, dynamic>) {
      setState(() {
        _selectedBuyerId = buyer['buyer_id'];
        _buyerCodeController.text = buyer['buyer_code'] ?? '';
        _buyerNameController.text = buyer['buyer_name'] ?? '';
        _selectedLat = buyer['lat'] != null ? (buyer['lat'] as num).toDouble() : null;
        _selectedLng = buyer['lng'] != null ? (buyer['lng'] as num).toDouble() : null;
        _addressController.text = buyer['address'] ?? '';
        _phoneController.text = buyer['phone_number'] ?? '';
      });
    }
  }

  Future<void> _createInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final response = await ApiService().createInvoice(
        buyerId: _selectedBuyerId,
        invoiceCode: _invoiceCodeController.text.trim(),
        buyerNameSnapshot: _buyerNameController.text.trim(),
        latSnapshot: _selectedLat,
        lngSnapshot: _selectedLng,
        addressSnapshot: _addressController.text.trim(),
        phoneNumberSnapshot: _phoneController.text.trim(),
      );

      if (mounted) {
        final invoiceId = response['data']['invoice_id'];
        // Chuyển sang màn hình edit (sẽ tạo sau)
        Navigator.pushReplacementNamed(
          context,
          '/edit_invoice',
          arguments: {'invoiceId': invoiceId},
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg.contains('23505') || errorMsg.contains('duplicate key')) {
          _showDuplicateCodeDialog();
        } else if (errorMsg.contains('Code mismatch!')) {
          final nextCode = errorMsg.split('is ').last;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nhảy số! Mã tiếp theo phải là $nextCode'),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: 'LÀM MỚI',
                textColor: Colors.white,
                onPressed: _fetchNextInvoiceCode,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi khi tạo hóa đơn: $e')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDuplicateCodeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Trùng mã hóa đơn'),
          ],
        ),
        content: const Text(
          'Mã hóa đơn này đã tồn tại trong hệ thống. Vui lòng làm mới để lấy mã khác hoặc nhập mã mới thủ công.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ĐÓNG'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _fetchNextInvoiceCode();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('LẤY MÃ MỚI'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo hóa đơn mới'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Card(
                        color: colorScheme.surfaceContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Thông tin chung',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _invoiceCodeController,
                                      readOnly: true,
                                      style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                                      decoration: InputDecoration(
                                        labelText: 'Mã hóa đơn *',
                                        border: const OutlineInputBorder(),
                                        filled: true,
                                        fillColor: colorScheme.onSurface.withValues(alpha: 0.05),
                                      ),
                                      validator: (val) => val == null || val.isEmpty ? 'Vui lòng nhập mã hóa đơn' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _isFetchingInvoiceCode
                                      ? const Padding(
                                          padding: EdgeInsets.all(12.0),
                                          child: SizedBox(
                                              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                        )
                                      : IconButton.filled(
                                          onPressed: _fetchNextInvoiceCode,
                                          icon: const Icon(Icons.refresh),
                                          tooltip: 'Lấy mã mới',
                                        ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        color: colorScheme.surfaceContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Thông tin khách hàng',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _buyerCodeController,
                                      decoration: const InputDecoration(
                                        labelText: 'Mã khách hàng (Tùy chọn)',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _isFetchingBuyer
                                      ? const Padding(
                                          padding: EdgeInsets.all(12.0),
                                          child: SizedBox(
                                              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                        )
                                      : Row(
                                          children: [
                                            IconButton.filled(
                                              onPressed: _lookupBuyer,
                                              icon: const Icon(Icons.person_search),
                                              tooltip: 'Truy vấn nhanh theo mã',
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton.filledTonal(
                                              onPressed: _searchBuyerAdvanced,
                                              icon: const Icon(Icons.search),
                                              tooltip: 'Tìm kiếm nâng cao',
                                            ),
                                          ],
                                        ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _buyerNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Tên khách hàng *',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (val) => val == null || val.isEmpty ? 'Vui lòng nhập tên khách hàng' : null,
                              ),
                              const SizedBox(height: 16),
                              AddressSearchField(
                                controller: _addressController,
                                initialLat: _selectedLat,
                                initialLng: _selectedLng,
                                initialAddress: _addressController.text,
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
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.phone,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _createInvoice,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                          ),
                          child: const Text('TIẾP TỤC & CHỈNH SỬA', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _buyerCodeController.dispose();
    _invoiceCodeController.dispose();
    _buyerNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
