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
  final _idCardController = TextEditingController();
  final _emailController = TextEditingController();
  final _taxIdController = TextEditingController();

  String? _selectedBuyerId;
  double? _selectedLat;
  double? _selectedLng;
  bool _isLoading = false;
  bool _isFetchingBuyer = false;
  bool _isFetchingInvoiceCode = false;
  bool _isFetchingBusiness = false;

  String? _autoApplyPriceListId;
  List<dynamic>? _clonedItems;
  bool _isArgumentsParsed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isArgumentsParsed) {
      _isArgumentsParsed = true;
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        if (args.containsKey('auto_apply_pricelist_id')) {
          _autoApplyPriceListId = args['auto_apply_pricelist_id'] as String?;
        }
        if (args.containsKey('cloned_items')) {
          _clonedItems = args['cloned_items'] as List?;
        }
      }
    }
  }

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
        _selectedBuyerId = buyer['buyerId'];
        _buyerNameController.text = buyer['buyerName'] ?? '';
        _selectedLat = buyer['lat'] != null ? (buyer['lat'] as num).toDouble() : null;
        _selectedLng = buyer['lng'] != null ? (buyer['lng'] as num).toDouble() : null;
        _addressController.text = buyer['address'] ?? '';
        _phoneController.text = buyer['phoneNumber'] ?? '';
        _idCardController.text = buyer['idCardNumber'] ?? '';
        _emailController.text = buyer['email'] ?? '';
        _taxIdController.text = buyer['taxId'] ?? '';
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
        _selectedBuyerId = buyer['buyerId'];
        _buyerCodeController.text = buyer['buyerCode'] ?? '';
        _buyerNameController.text = buyer['buyerName'] ?? '';
        _selectedLat = buyer['lat'] != null ? (buyer['lat'] as num).toDouble() : null;
        _selectedLng = buyer['lng'] != null ? (buyer['lng'] as num).toDouble() : null;
        _addressController.text = buyer['address'] ?? '';
        _phoneController.text = buyer['phoneNumber'] ?? '';
        _idCardController.text = buyer['idCardNumber'] ?? '';
        _emailController.text = buyer['email'] ?? '';
        _taxIdController.text = buyer['taxId'] ?? '';
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
        idCardNumberSnapshot: _idCardController.text.trim().isEmpty ? null : _idCardController.text.trim(),
        emailSnapshot: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        taxIdSnapshot: _taxIdController.text.trim().isEmpty ? null : _taxIdController.text.trim(),
      );

      if (mounted) {
        final invoiceId = response['data']['invoiceId'];
        if (_clonedItems != null && _clonedItems!.isNotEmpty) {
          try {
            for (final item in _clonedItems!) {
              final Map<String, dynamic> itemMap = Map<String, dynamic>.from(item);
              await ApiService().createLineItem(invoiceId, {
                "itemId": itemMap['itemId'],
                "unitId": itemMap['unitId'],
                "itemNameSnapshot": itemMap['itemNameSnapshot'],
                "unitNameSnapshot": itemMap['unitNameSnapshot'],
                "quantity": (itemMap['quantity'] as num?)?.toInt() ?? 1,
                "unitPriceCustom": itemMap['unitPriceCustom'],
              });
            }
          } catch (e) {
            debugPrint('Error applying cloned items: $e');
          }
        } else if (_autoApplyPriceListId != null) {
          final pickedItems = await Navigator.pushNamed(
            context,
            '/pricelist_item_picker',
            arguments: _autoApplyPriceListId,
          );

          if (pickedItems != null && pickedItems is List && pickedItems.isNotEmpty) {
            if (!mounted) return;
            final buyerName = _buyerNameController.text.trim().isNotEmpty
                ? _buyerNameController.text.trim()
                : 'Khách lẻ';
            final itemCount = pickedItems.length;

            final bool? confirm = await showDialog<bool>(
              context: context,
              builder: (dialogContext) {
                final colorScheme = Theme.of(context).colorScheme;
                return AlertDialog(
                  title: const Text('Xác nhận thêm mặt hàng'),
                  content: Text(
                    'Bạn có chắc chắn muốn thêm $itemCount mặt hàng đã chọn vào hóa đơn mới cho $buyerName không?'
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('HỦY'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
                      child: const Text('XÁC NHẬN'),
                    ),
                  ],
                );
              },
            );

            if (confirm == true) {
              if (mounted) setState(() => _isLoading = true);
              try {
                for (final item in pickedItems) {
                  final Map<String, dynamic> itemMap = Map<String, dynamic>.from(item);
                  await ApiService().createLineItem(invoiceId, {
                    "itemId": itemMap['itemId'],
                    "unitId": itemMap['unitId'],
                    "itemNameSnapshot": itemMap['itemName'],
                    "unitNameSnapshot": itemMap['unitName'],
                    "quantity": (itemMap['quantity'] as num?)?.toInt() ?? 1,
                    "unitPriceCustom": itemMap['price'],
                  });
                }
              } catch (e) {
                debugPrint('Error applying auto price list items: $e');
              }
            }
          }
        }

        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/edit_invoice',
            arguments: {'invoiceId': invoiceId},
          );
        }
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
      final business = await ApiService().fetchVietQRBusiness(taxId);
      if (business != null) {
        setState(() {
          _buyerNameController.text = business['name'] ?? '';
          _addressController.text = business['address'] ?? '';
        });

        final address = business['address'];
        if (address != null && address.isNotEmpty) {
          final coords = await ApiService().googleGeocode(address);
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
                                controller: _taxIdController,
                                decoration: InputDecoration(
                                  labelText: 'Mã số thuế (Tùy chọn)',
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
                                ),
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
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _idCardController,
                                decoration: const InputDecoration(
                                  labelText: 'Số CMND/CCCD (Tùy chọn)',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  labelText: 'Email (Tùy chọn)',
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
    _idCardController.dispose();
    _emailController.dispose();
    _taxIdController.dispose();
    super.dispose();
  }
}
