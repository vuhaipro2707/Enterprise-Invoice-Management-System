import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/string_utils.dart';
import '../../widgets/line_item_card.dart';
import '../../widgets/address_search_field.dart';

class EditInvoiceScreen extends StatefulWidget {
  const EditInvoiceScreen({super.key});

  @override
  State<EditInvoiceScreen> createState() => _EditInvoiceScreenState();
}

class _EditInvoiceScreenState extends State<EditInvoiceScreen> {
  final ApiService _apiService = ApiService();
  String? _invoiceId;
  Map<String, dynamic>? _invoiceData;
  bool _isLoading = true;
  int? _pickedIndex;
  String _localSearchQuery = '';

  final _buyerCodeController = TextEditingController();
  final _buyerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _taxIdController = TextEditingController();
  String? _selectedBuyerId;
  double? _selectedLat;
  double? _selectedLng;
  bool _isFetchingBuyer = false;
  bool _isFetchingBusiness = false;

  Timer? _pingTimer;
  int _failedPingCount = 0;
  bool _isShowingAlert = false;

  @override
  void initState() {
    super.initState();
    _startPingTimer();
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _failedPingCount = 0;
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_invoiceId != null && !_isShowingAlert) {
        _pingInvoice();
      }
    });
  }

  Future<void> _pingInvoice() async {
    try {
      final response = await _apiService.get('/invoice/ping/invoiceId/$_invoiceId');
      if (response.statusCode != 200) {
        throw Exception('Ping failed');
      }
      final data = jsonDecode(response.body);
      _failedPingCount = 0; // Reset counter on success

      if (!mounted) return;

      final bool editStatus = data['edit_status'] ?? false;
      final String? holdingId = data['device_holding_id'];
      final String currentDeviceId = _apiService.deviceId ?? '';

      if (!editStatus) {
        _showStatusAlert(
          title: 'Hóa đơn đã được lưu',
          message: 'Hóa đơn này đã được lưu trước đó. Bạn có muốn mở lại để chỉnh sửa không?',
          confirmLabel: 'CHỈNH SỬA',
          onConfirm: _takeTurn,
        );
      } else if (holdingId != null && holdingId != currentDeviceId) {
        _showStatusAlert(
          title: 'Mất quyền chỉnh sửa',
          message: 'Thiết bị khác (${data['device_name'] ?? 'Thiết bị khác'}) đã giành quyền chỉnh sửa hóa đơn này.',
          confirmLabel: 'GIÀNH LẠI QUYỀN',
          onConfirm: _takeTurn,
        );
      }
    } catch (e) {
      _failedPingCount++;
      if (_failedPingCount >= 5) {
        _pingTimer?.cancel();
        _showConnectionAlert();
      }
    }
  }

  void _showStatusAlert({
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) {
    if (_isShowingAlert) return;
    setState(() => _isShowingAlert = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              _pingTimer?.cancel();
              setState(() => _isShowingAlert = true);
              Navigator.pop(dialogContext); // Close dialog
              Navigator.pop(context); // Go back to dashboard (using screen context)
            },
            child: const Text('THOÁT RA'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              setState(() => _isShowingAlert = false);
              onConfirm();
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isShowingAlert = false);
      }
    });
  }

  void _showConnectionAlert() {
    if (_isShowingAlert) return;
    setState(() => _isShowingAlert = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mất kết nối'),
        content: const Text('Không thể kết nối tới máy chủ sau nhiều lần thử. Vui lòng kiểm tra lại mạng.'),
        actions: [
          TextButton(
            onPressed: () {
              _pingTimer?.cancel(); // Dừng ngay lập tức
              setState(() => _isShowingAlert = true); // Giữ trạng thái chặn ping
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            child: const Text('THOÁT RA'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              setState(() => _isShowingAlert = false);
              _startPingTimer(); // Restart and try again
            },
            child: const Text('KIỂM TRA LẠI'),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isShowingAlert = false);
      }
    });
  }

  Future<void> _takeTurn() async {
    try {
      await _apiService.takeTurn(_invoiceId!);
      _fetchInvoiceDetails();
      _startPingTimer();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi giành quyền: $e')));
      }
    }
  }

  Future<void> _finishInvoice() async {
    try {
      await _apiService.post('/invoice/finish/invoiceId/$_invoiceId', {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu hóa đơn thành công!')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isShowingAlert = false); // Re-enable ping if failed
        _startPingTimer();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi lưu: $e')));
      }
    }
  }

  Future<void> _deleteInvoice() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: const Text(
            'Bạn có chắc chắn muốn xóa hóa đơn này không? Bạn có thể khôi phục lại từ Thùng rác.'
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

    _pingTimer?.cancel();
    setState(() {
      _isShowingAlert = true;
      _isLoading = true;
    });

    try {
      await _apiService.deleteInvoice(_invoiceId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xóa hóa đơn thành công')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isShowingAlert = false;
          _isLoading = false;
        });
        _startPingTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xóa hóa đơn: $e')),
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_invoiceId == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) {
        _invoiceId = args;
      } else if (args is Map<String, dynamic>) {
        _invoiceId = args['invoiceId'];
      }
      if (_invoiceId != null) {
        _fetchInvoiceDetails();
      }
    }
  }

  Future<void> _fetchInvoiceDetails() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getInvoice(_invoiceId!);
      setState(() {
        _invoiceData = data;
        _selectedBuyerId = data['buyer_id'];
        _buyerCodeController.text = data['buyer_code']?.toString() ?? '';
        _buyerNameController.text = data['buyer_name_snapshot']?.toString() ?? '';
        _addressController.text = data['address_snapshot']?.toString() ?? '';
        _phoneController.text = data['phone_number_snapshot']?.toString() ?? '';
        _taxIdController.text = data['tax_id_snapshot']?.toString() ?? '';
        _selectedLat = data['lat_snapshot'] != null ? (data['lat_snapshot'] as num).toDouble() : null;
        _selectedLng = data['lng_snapshot'] != null ? (data['lng_snapshot'] as num).toDouble() : null;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải thông tin: $e')),
        );
      }
    }
  }

  Future<void> _lookupBuyer() async {
    final code = _buyerCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isFetchingBuyer = true);
    try {
      final buyer = await _apiService.getBuyerByCode(code);
      setState(() {
        _selectedBuyerId = buyer['buyer_id'];
        _buyerNameController.text = buyer['buyer_name'] ?? '';
        _selectedLat = buyer['lat'] != null ? (buyer['lat'] as num).toDouble() : null;
        _selectedLng = buyer['lng'] != null ? (buyer['lng'] as num).toDouble() : null;
        _addressController.text = buyer['address'] ?? '';
        _phoneController.text = buyer['phone_number'] ?? '';
        _taxIdController.text = buyer['tax_id'] ?? '';
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
        _taxIdController.text = buyer['tax_id'] ?? '';
      });
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
          _buyerNameController.text = business['name'] ?? '';
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

  Future<void> _updateBuyerInfo() async {
    try {
      await _apiService.updateInvoice(_invoiceId!, {
        'buyerId': _selectedBuyerId,
        'buyerNameSnapshot': _buyerNameController.text.trim(),
        'latSnapshot': _selectedLat,
        'lngSnapshot': _selectedLng,
        'addressSnapshot': _addressController.text.trim(),
        'phoneNumberSnapshot': _phoneController.text.trim(),
        'taxIdSnapshot': _taxIdController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật thông tin thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        if (errorMessage.contains('Code mismatch!')) {
          final nextCode = errorMessage.split('is ').last;
          errorMessage = 'Nhảy số! Mã tiếp theo cho khách hàng phải là $nextCode';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cập nhật: $errorMessage')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chỉnh sửa hóa đơn')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final lineItems = (_invoiceData?['line_items'] as List?) ?? [];

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _pingTimer?.cancel();
          setState(() => _isShowingAlert = true);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Sửa ${_invoiceData?['invoice_code'] ?? 'Hóa đơn'}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _pingTimer?.cancel();
              setState(() => _isShowingAlert = true);
              Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchInvoiceDetails,
              tooltip: 'Làm mới',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deleteInvoice,
              tooltip: 'Xóa hóa đơn',
            ),
          ],
        ),
        body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thông tin chung (Readonly)
            Card(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thông tin chung', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _invoiceData?['invoice_code'],
                      decoration: const InputDecoration(labelText: 'Mã hóa đơn', border: OutlineInputBorder()),
                      readOnly: true,
                      enabled: false,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Thông tin khách hàng (Editable)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Thông tin khách hàng',
                            style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                        TextButton.icon(
                          onPressed: _updateBuyerInfo,
                          icon: const Icon(Icons.save),
                          label: const Text('Lưu'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _buyerNameController,
                      decoration: const InputDecoration(labelText: 'Tên khách hàng', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Danh sách Line Items
            LayoutBuilder(
              builder: (headerContext, constraints) {
                final isNarrow = constraints.maxWidth < 450;
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sản phẩm / Dịch vụ',
                        style: Theme.of(headerContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openPriceListSelection,
                              icon: const Icon(Icons.request_quote),
                              label: const Text('Báo giá'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _openCreateLineItem(),
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm dòng'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                } else {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sản phẩm / Dịch vụ',
                        style: Theme.of(headerContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _openPriceListSelection,
                            icon: const Icon(Icons.request_quote),
                            label: const Text('Bảng báo giá'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _openCreateLineItem(),
                            icon: const Icon(Icons.add),
                            label: const Text('Thêm dòng'),
                          ),
                        ],
                      ),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            if (lineItems.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Chưa có sản phẩm nào')))
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: TextFormField(
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm sản phẩm trong danh sách...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _localSearchQuery = val;
                    });
                  },
                ),
              ),
              if (_pickedIndex != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: colorScheme.onPrimaryContainer, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đang chọn sản phẩm để di chuyển. Hãy bấm vào nút "Chèn vào đây" để thay đổi vị trí.',
                            style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _pickedIndex = null;
                            });
                          },
                          child: Text('HỦY', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Builder(
                  builder: (builderContext) {
                  final List<Map<String, dynamic>> itemsWithOrigIndex = [];
                  for (int i = 0; i < lineItems.length; i++) {
                    final itm = Map<String, dynamic>.from(lineItems[i]);
                    itm['orig_index'] = i;
                    itemsWithOrigIndex.add(itm);
                  }

                  final filteredItems = itemsWithOrigIndex.where((itm) {
                    final name = (itm['item_name_snapshot'] ?? '').toString();
                    return StringUtils.containsUnaccented(name, _localSearchQuery);
                  }).toList();

                  if (filteredItems.isEmpty) {
                    return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Không tìm thấy sản phẩm phù hợp')));
                  }

                  if (_pickedIndex == null) {
                    return ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredItems.length,
                      onReorder: (oldIndex, newIndex) {
                        final oldOrigIndex = filteredItems[oldIndex]['orig_index'];
                        var newOrigIndex = newIndex < filteredItems.length
                            ? filteredItems[newIndex]['orig_index']
                            : filteredItems[newIndex - 1]['orig_index'] + 1;
                        
                        _onReorderLineItems(lineItems, oldOrigIndex, newOrigIndex);
                      },
                      itemBuilder: (context, idx) {
                        final item = filteredItems[idx];
                        final origIndex = item['orig_index'];
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(item['line_item_id']),
                          index: idx,
                          child: LineItemCard(
                            item: item,
                            index: origIndex,
                            isPicked: false,
                            onTap: () {
                              setState(() {
                                _pickedIndex = origIndex;
                              });
                            },
                            onEdit: () => _openEditLineItem(item),
                            onDelete: () => _confirmDeleteLineItem(item),
                          ),
                        );
                      },
                    );
                  } else {
                    return Column(
                      children: [
                        _buildInsertSlot(builderContext, filteredItems[0]['orig_index'], _pickedIndex!, lineItems),
                        for (int j = 0; j < filteredItems.length; j++) ...[
                          LineItemCard(
                            item: filteredItems[j],
                            index: filteredItems[j]['orig_index'],
                            isPicked: _pickedIndex == filteredItems[j]['orig_index'],
                            onTap: () {
                              setState(() {
                                if (_pickedIndex == filteredItems[j]['orig_index']) {
                                  _pickedIndex = null;
                                } else {
                                  _pickedIndex = filteredItems[j]['orig_index'];
                                }
                              });
                            },
                            onEdit: () => _openEditLineItem(filteredItems[j]),
                            onDelete: () => _confirmDeleteLineItem(filteredItems[j]),
                          ),
                          _buildInsertSlot(
                            builderContext,
                            j < filteredItems.length - 1 
                                ? filteredItems[j + 1]['orig_index'] 
                                : filteredItems[j]['orig_index'] + 1,
                            _pickedIndex!,
                            lineItems,
                          ),
                        ],
                      ],
                    );
                  }
                },
              ),
            ),
          ],
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tổng cộng:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                      .format((_invoiceData?['total_amount'] as num?)?.toDouble() ?? 0),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Xác nhận lưu'),
                      content: const Text('Bạn có chắc chắn muốn hoàn tất và lưu hóa đơn này không?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('HỦY')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
                          onPressed: () {
                            _pingTimer?.cancel(); // Cancel ping immediately before finishing
                            setState(() => _isShowingAlert = true); // Block further pings
                            Navigator.pop(dialogContext);
                            _finishInvoice();
                          },
                          child: const Text('LƯU NGAY'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('HOÀN TẤT & LƯU HÓA ĐƠN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _onReorderLineItems(List<dynamic> lineItems, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final movedItem = lineItems[oldIndex];
    final String lineItemId = movedItem['line_item_id'];

    setState(() {
      final item = lineItems.removeAt(oldIndex);
      lineItems.insert(newIndex, item);
    });

    String? prevId;
    String? nextId;

    if (newIndex > 0) {
      prevId = lineItems[newIndex - 1]['line_item_id'];
    }
    if (newIndex < lineItems.length - 1) {
      nextId = lineItems[newIndex + 1]['line_item_id'];
    }

    try {
      await _apiService.changeLineItemOrder(_invoiceId!, lineItemId, prevId, nextId);
      // Không cần fetch lại ở đây để tránh chớp màn hình, vì UI đã update qua setState phía trên
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi đổi vị trí: $e')));
        _fetchInvoiceDetails(); // Revert on failure
      }
    }
  }

  Widget _buildInsertSlot(BuildContext context, int targetIndex, int? pickedIndex, List<dynamic> lineItems) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isVisible = pickedIndex != null && 
        targetIndex != pickedIndex && 
        targetIndex != pickedIndex + 1;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      height: isVisible ? 44 : 0,
      margin: EdgeInsets.symmetric(vertical: isVisible ? 4 : 0),
      decoration: BoxDecoration(
        color: isVisible 
            ? colorScheme.primaryContainer.withValues(alpha: 0.12) 
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isVisible 
              ? colorScheme.primary.withValues(alpha: 0.4) 
              : Colors.transparent,
          width: isVisible ? 1.0 : 0.0,
        ),
      ),
      child: ClipRect(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isVisible ? 1.0 : 0.0,
          child: AnimatedSlide(
            offset: isVisible ? Offset.zero : const Offset(0, 1.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: Center(
              child: InkWell(
                onTap: isVisible ? () {
                  _onReorderLineItems(lineItems, pickedIndex, targetIndex);
                  setState(() {
                    _pickedIndex = null;
                  });
                } : null,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Chèn vào đây',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openCreateLineItem() async {
    final result = await Navigator.pushNamed(
      context,
      '/create_line_item',
      arguments: {'invoiceId': _invoiceId!},
    );
    if (result == true) _fetchInvoiceDetails();
  }

  void _openPriceListSelection() async {
    final result = await Navigator.pushNamed(
      context,
      '/pricelist_picker',
      arguments: _selectedBuyerId,
    );

    if (result != null && result is List<Map<String, dynamic>> && result.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        for (final item in result) {
          await _apiService.createLineItem(_invoiceId!, {
            "itemID": item['item_id'],
            "unitID": item['unit_id'],
            "itemNameSnapshot": item['item_name'],
            "unitNameSnapshot": item['unit_name'],
            "quantity": (item['quantity'] as num?)?.toInt() ?? 1, // Quantity chosen in selection screen (must be int)
            "unitPriceCustom": item['price'],
          });
        }
        _fetchInvoiceDetails();
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi khi thêm mặt hàng từ báo giá: $e')),
          );
        }
      }
    }
  }

  void _openEditLineItem(Map<String, dynamic> lineItem) async {
    final result = await Navigator.pushNamed(
      context,
      '/create_line_item',
      arguments: {
        'invoiceId': _invoiceId!,
        'existingLineItem': lineItem,
      },
    );
    if (result == true) _fetchInvoiceDetails();
  }

  void _confirmDeleteLineItem(Map<String, dynamic> lineItem) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa dòng "${lineItem['item_name_snapshot']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('HỦY')),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await _apiService.deleteLineItem(lineItem['line_item_id'].toString());
                if (!mounted) return;
                _fetchInvoiceDetails();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi xóa: $e')));
                }
              }
            },
            child: const Text('XÓA', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _buyerCodeController.dispose();
    _buyerNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _taxIdController.dispose();
    super.dispose();
  }
}

