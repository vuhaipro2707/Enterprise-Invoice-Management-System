import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';
import '../../widgets/line_item_card.dart';
import 'line_item_search_screen.dart';

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

  final _buyerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

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
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              _pingTimer?.cancel();
              setState(() => _isShowingAlert = true);
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to dashboard
            },
            child: const Text('THOÁT RA'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
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
      builder: (context) => AlertDialog(
        title: const Text('Mất kết nối'),
        content: const Text('Không thể kết nối tới máy chủ sau nhiều lần thử. Vui lòng kiểm tra lại mạng.'),
        actions: [
          TextButton(
            onPressed: () {
              _pingTimer?.cancel(); // Dừng ngay lập tức
              setState(() => _isShowingAlert = true); // Giữ trạng thái chặn ping
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('THOÁT RA'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
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
        _buyerNameController.text = _getStringValue(data['buyer_name_snapshot']) ?? '';
        _addressController.text = _getStringValue(data['address_snapshot']) ?? '';
        _phoneController.text = _getStringValue(data['phone_number_snapshot']) ?? '';
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

  String? _getStringValue(dynamic field) {
    if (field == null) return null;
    if (field is Map) return field['Valid'] == true ? field['String'].toString() : null;
    return field.toString();
  }

  Future<void> _updateBuyerInfo() async {
    try {
      await _apiService.updateInvoice(_invoiceId!, {
        'buyerNameSnapshot': _buyerNameController.text.trim(),
        'addressSnapshot': _addressController.text.trim(),
        'phoneNumberSnapshot': _phoneController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật thông tin thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cập nhật: $e')),
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
                    TextFormField(
                      controller: _buyerNameController,
                      decoration: const InputDecoration(labelText: 'Tên khách hàng', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'Địa chỉ', border: OutlineInputBorder()),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sản phẩm / Dịch vụ', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  onPressed: () => _openCreateLineItem(),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm dòng'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (lineItems.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Chưa có sản phẩm nào')))
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: lineItems.length,
                onReorder: (oldIndex, newIndex) {
                  _onReorderLineItems(lineItems, oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final item = lineItems[index];
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(item['line_item_id']),
                    index: index,
                    child: LineItemCard(
                      item: item,
                      onTap: () => _openEditLineItem(item),
                      onLongPress: () => _confirmDeleteLineItem(item),
                    ),
                  );
                },
              ),
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
                    builder: (context) => AlertDialog(
                      title: const Text('Xác nhận lưu'),
                      content: const Text('Bạn có chắc chắn muốn hoàn tất và lưu hóa đơn này không?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('HỦY')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
                          onPressed: () {
                            _pingTimer?.cancel(); // Cancel ping immediately before finishing
                            setState(() => _isShowingAlert = true); // Block further pings
                            Navigator.pop(context);
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

  void _openCreateLineItem() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreateLineItemScreen(invoiceId: _invoiceId!)),
    );
    if (result == true) _fetchInvoiceDetails();
  }

  void _openEditLineItem(Map<String, dynamic> lineItem) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateLineItemScreen(
          invoiceId: _invoiceId!,
          existingLineItem: lineItem,
        ),
      ),
    );
    if (result == true) _fetchInvoiceDetails();
  }

  void _confirmDeleteLineItem(Map<String, dynamic> lineItem) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa dòng "${lineItem['item_name_snapshot']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('HỦY')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _apiService.deleteLineItem(lineItem['line_item_id'].toString());
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
    _buyerNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}

class CreateLineItemScreen extends StatefulWidget {
  final String invoiceId;
  final Map<String, dynamic>? existingLineItem;
  const CreateLineItemScreen({super.key, required this.invoiceId, this.existingLineItem});

  @override
  State<CreateLineItemScreen> createState() => _CreateLineItemScreenState();
}

class _CreateLineItemScreenState extends State<CreateLineItemScreen> {
  final ApiService _apiService = ApiService();
  final _itemNameController = TextEditingController();
  final _unitNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  bool _isSaving = false;

  Map<String, dynamic>? _selectedItem;
  List<dynamic> _availableUnits = [];
  String? _selectedUnitId;

  @override
  void initState() {
    super.initState();
    if (widget.existingLineItem != null) {
      final item = widget.existingLineItem!;
      _itemNameController.text = item['item_name_snapshot'] ?? '';
      _unitNameController.text = item['unit_name_snapshot'] ?? '';
      _quantityController.text = (item['quantity'] ?? 0).toString();
      _priceController.text = NumberFormat.decimalPattern('vi_VN').format(item['unit_price_custom'] ?? 0);
      _selectedUnitId = item['unit_id'];
      // if it has item_id, we might want to fetch available units for it, 
      // but for simplicity we'll just allow editing the snapshots
    }
  }

  void _openSearch() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LineItemSearchScreen()),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedItem = result;
        _itemNameController.text = result['item_default_name'] ?? '';
        _availableUnits = result['units'] as List? ?? [];
        if (_availableUnits.isNotEmpty) {
          // Mặc định chọn đơn vị đầu tiên
          _onUnitSelected(_availableUnits[0]);
        } else {
          _unitNameController.clear();
          _priceController.clear();
          _selectedUnitId = null;
        }
      });
    }
  }

  void _onUnitSelected(Map<String, dynamic> unit) {
    setState(() {
      _selectedUnitId = unit['unit_id'];
      _unitNameController.text = unit['unit_name'] ?? '';
      
      // Sử dụng formatter để hiển thị đơn giá ngay khi chọn unit
      final rawPrice = unit['unit_price_default'] ?? 0;
      _priceController.text = NumberFormat.decimalPattern('vi_VN').format(rawPrice);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Thêm dòng hàng')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tìm kiếm item
            InkWell(
              onTap: _openSearch,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedItem == null ? 'Bấm để tìm kiếm sản phẩm...' : _itemNameController.text,
                        style: TextStyle(
                          color: _selectedItem == null ? colorScheme.outline : colorScheme.onSurface,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (_selectedItem != null) const Icon(Icons.edit, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (_selectedItem != null) ...[
              Text('Chọn đơn vị tính:', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _availableUnits.map((unit) {
                  final isSelected = _selectedUnitId == unit['unit_id'];
                  return ChoiceChip(
                    label: Text('${unit['unit_name']} (${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(unit['unit_price_default'])})'),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) _onUnitSelected(unit);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],

            // Các trường nhập tay (có thể chỉnh sửa sau khi chọn item)
            Text('Thông tin chi tiết (Tùy chỉnh nếu cần)',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
            const SizedBox(height: 12),
            TextField(
              controller: _itemNameController,
              decoration: const InputDecoration(
                labelText: 'Tên sản phẩm *',
                border: OutlineInputBorder(),
                hintText: 'Nhập tên hoặc chọn sản phẩm',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitNameController,
              decoration: const InputDecoration(
                labelText: 'Đơn vị tính *',
                border: OutlineInputBorder(),
                hintText: 'Cái, Thùng, Lon...',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Số lượng *',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Đơn giá *',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [CurrencyInputFormatter()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(widget.existingLineItem != null ? 'LƯU THAY ĐỔI' : 'XÁC NHẬN THÊM'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() async {
    final itemName = _itemNameController.text.trim();
    final unitName = _unitNameController.text.trim();
    final quantityText = _quantityController.text.trim();
    final priceText = _priceController.text.trim();

    if (itemName.isEmpty || unitName.isEmpty || quantityText.isEmpty || priceText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng điền đầy đủ các thông tin bắt buộc (*)')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final qty = double.tryParse(quantityText.replaceAll(',', '.')) ?? 0;
      final price = int.tryParse(priceText.replaceAll('.', '')) ?? 0;

      if (qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số lượng phải lớn hơn 0')));
        setState(() => _isSaving = false);
        return;
      }

      final payload = {
        "invoice_id": widget.invoiceId,
        "item_id": _selectedItem != null ? (_selectedItem!['item_id'] ?? _selectedItem!['id']) : (widget.existingLineItem?['item_id']),
        "unit_id": _selectedUnitId,
        "item_name_snapshot": itemName,
        "unit_name_snapshot": unitName,
        "quantity": qty.toInt(),
        "unit_price_custom": price,
      };

      if (widget.existingLineItem != null) {
        final lineItemId = widget.existingLineItem!['line_item_id'];
        await _apiService.patchLineItem(lineItemId.toString(), payload);
      } else {
        await _apiService.createLineItem(widget.invoiceId, {
          "itemID": payload["item_id"],
          "unitID": payload["unit_id"],
          "itemNameSnapshot": payload["item_name_snapshot"],
          "unitNameSnapshot": payload["unit_name_snapshot"],
          "quantity": payload["quantity"],
          "unitPriceCustom": payload["unit_price_custom"],
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
