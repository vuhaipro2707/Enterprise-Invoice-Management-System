import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';

class EditPriceListScreen extends StatefulWidget {
  const EditPriceListScreen({super.key});

  @override
  State<EditPriceListScreen> createState() => _EditPriceListScreenState();
}

class _EditPriceListScreenState extends State<EditPriceListScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  String? _pricelistId;
  Map<String, dynamic>? _selectedBuyer;
  List<Map<String, dynamic>> _priceItems = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args != null && args is String) {
        _pricelistId = args;
        _fetchPriceListDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy thông tin ID bảng báo giá')),
        );
        Navigator.pop(context);
      }
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _fetchPriceListDetails() async {
    if (_pricelistId == null) return;
    
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getCustomerPriceList(_pricelistId!);
      
      setState(() {
        _descriptionController.text = data['description'] ?? '';
        
        if (data['buyer_id'] != null) {
          _selectedBuyer = {
            'buyer_id': data['buyer_id'],
            'buyer_name': data['buyer_name'],
            'buyer_code': data['buyer_code'],
            'phone_number': data['phone_number'],
            'address': data['address'],
          };
        } else {
          _selectedBuyer = null;
        }

        // Map item_prices array from DB query to local state format
        final List<dynamic> rawItems = data['item_prices'] as List? ?? [];
        _priceItems = rawItems.map((itm) {
          return {
            'item_id': itm['item_id'],
            'item_default_name': itm['item_default_name'] ?? 'Mặt hàng không tên',
            'unit_id': itm['unit_id'],
            'unit_name': itm['unit_name'] ?? 'Cái',
            'unit_price_custom': (itm['unit_price_custom'] as num?)?.toInt() ?? 0,
            'unit_price_default': 0, // Not stored in price lists, we will treat it as 0
            'units': <dynamic>[], // Will load empty unless we search again
          };
        }).toList();
        
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tải chi tiết báo giá: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _selectBuyer() async {
    final buyer = await Navigator.pushNamed(context, '/buyer_search');
    if (buyer != null && buyer is Map<String, dynamic>) {
      setState(() {
        _selectedBuyer = buyer;
      });
    }
  }

  void _clearBuyer() {
    setState(() {
      _selectedBuyer = null;
    });
  }

  void _addItem() async {
    final item = await Navigator.pushNamed(context, '/line_item_search');
    if (item != null && item is Map<String, dynamic>) {
      _showAddOrEditItemDialog(item: item);
    }
  }

  void _editItem(int index) {
    final item = _priceItems[index];
    _showAddOrEditItemDialog(item: item, index: index);
  }

  void _removeItem(int index) {
    setState(() {
      _priceItems.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã xóa mặt hàng khỏi bảng báo giá'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showAddOrEditItemDialog({required Map<String, dynamic> item, int? index}) {
    final colorScheme = Theme.of(context).colorScheme;
    final List<dynamic> units = item['units'] as List? ?? [];
    
    String? currentUnitId = index != null ? item['unit_id'] : (units.isNotEmpty ? units[0]['unit_id'] : null);
    
    int initialPrice = 0;
    if (index != null) {
      initialPrice = item['unit_price_custom'] as int? ?? 0;
    } else if (units.isNotEmpty) {
      initialPrice = (units[0]['unit_price_default'] as num?)?.toInt() ?? 0;
    }

    final priceController = TextEditingController(
      text: NumberFormat.decimalPattern('vi_VN').format(initialPrice),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (statefulContext, setDialogState) {
            Map<String, dynamic>? selectedUnitObj;
            if (currentUnitId != null) {
              for (var u in units) {
                if (u['unit_id'] == currentUnitId) {
                  selectedUnitObj = u as Map<String, dynamic>;
                  break;
                }
              }
            }

            final defaultPrice = selectedUnitObj != null
                ? (selectedUnitObj['unit_price_default'] as num?)?.toInt() ?? 0
                : 0;

            final itemName = item['item_default_name'] ?? item['item_name'] ?? 'Mặt hàng không tên';
            final currentUnitName = item['unit_name'] ?? 'Cái';

            return AlertDialog(
              title: Text(
                index != null ? 'Sửa giá tùy chỉnh' : 'Thêm giá tùy chỉnh',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (units.isNotEmpty) ...[
                      Text(
                        'Đơn vị tính:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: units.map((u) {
                          final isSelected = u['unit_id'] == currentUnitId;
                          final uPrice = (u['unit_price_default'] as num?)?.toInt() ?? 0;
                          final priceFormatted = CurrencyFormatter.formatVND(uPrice);
                          
                          return ChoiceChip(
                            label: Text('${u['unit_name']} ($priceFormatted)'),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setDialogState(() {
                                  currentUnitId = u['unit_id'];
                                  priceController.text = NumberFormat.decimalPattern('vi_VN').format(uPrice);
                                });
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ] else ...[
                      Row(
                        children: [
                          Text(
                            'Đơn vị tính: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              currentUnitName,
                              style: TextStyle(
                                color: colorScheme.onSecondaryContainer,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      'Giá tùy chỉnh (VND):',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Giá mới *',
                        border: const OutlineInputBorder(),
                        suffixIcon: defaultPrice > 0
                            ? IconButton(
                                icon: const Icon(Icons.restore),
                                tooltip: 'Dùng giá gốc',
                                onPressed: () {
                                  setDialogState(() {
                                    priceController.text = NumberFormat.decimalPattern('vi_VN').format(defaultPrice);
                                  });
                                },
                              )
                            : null,
                      ),
                    ),
                    if (defaultPrice > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Giá gốc: ${CurrencyFormatter.formatVND(defaultPrice)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('HỦY'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final priceText = priceController.text.trim();
                    if (priceText.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vui lòng nhập giá tùy chỉnh')),
                      );
                      return;
                    }

                    final price = int.tryParse(priceText.replaceAll('.', '')) ?? 0;
                    if (price <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Giá tùy chỉnh phải lớn hơn 0')),
                      );
                      return;
                    }

                    String unitName = currentUnitName;
                    if (selectedUnitObj != null) {
                      unitName = selectedUnitObj['unit_name'] ?? 'Cái';
                    }

                    setState(() {
                      final itemData = {
                        'item_id': item['item_id'] ?? item['id'],
                        'item_default_name': itemName,
                        'unit_id': currentUnitId,
                        'unit_name': unitName,
                        'unit_price_custom': price,
                        'unit_price_default': defaultPrice,
                        'units': units,
                      };

                      if (index != null) {
                        _priceItems[index] = itemData;
                      } else {
                        final existingIdx = _priceItems.indexWhere((element) =>
                            element['item_id'] == itemData['item_id'] &&
                            element['unit_id'] == itemData['unit_id']);
                        
                        if (existingIdx != -1) {
                          _priceItems[existingIdx] = itemData;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã cập nhật giá mặt hàng trùng lặp')),
                          );
                        } else {
                          _priceItems.add(itemData);
                        }
                      }
                    });

                    Navigator.pop(dialogContext);
                  },
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
      },
    );
  }

  void _savePriceList() async {
    if (!_formKey.currentState!.validate() || _pricelistId == null) return;

    if (_priceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng thêm ít nhất một mặt hàng vào bảng báo giá'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final formattedItems = _priceItems.map((itm) {
        return {
          'itemId': itm['item_id'],
          'unitId': itm['unit_id'],
          'unitPriceCustom': itm['unit_price_custom'],
        };
      }).toList();

      await _apiService.updateCustomerPriceList(
        _pricelistId!,
        description: _descriptionController.text.trim(),
        buyerId: _selectedBuyer?['buyer_id'],
        items: formattedItems,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cập nhật bảng báo giá thành công!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi lưu bảng báo giá: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _deletePriceList() async {
    if (_pricelistId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Xóa bảng báo giá'),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa bảng báo giá này? Hành động này sẽ không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('XÓA'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _apiService.deleteCustomerPriceList(_pricelistId!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa bảng báo giá thành công'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi xóa bảng báo giá: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sửa bảng báo giá'),
        actions: [
          if (!_isLoading && !_isSaving)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
              onPressed: _deletePriceList,
              tooltip: 'Xóa báo giá',
            ),
        ],
      ),
      body: _isLoading || _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // General info block
                    Card(
                      color: colorScheme.surfaceContainer,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thông tin chung',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _descriptionController,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Mô tả / Tên bảng báo giá *',
                                border: OutlineInputBorder(),
                                hintText: 'Ví dụ: Báo giá đại lý tháng 5/2026',
                                alignLabelWithHint: true,
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Vui lòng nhập mô tả bảng báo giá';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Buyer select block
                    Card(
                      color: colorScheme.surfaceContainer,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Người mua áp dụng (Tùy chọn)',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                if (_selectedBuyer != null)
                                  IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: _clearBuyer,
                                    tooltip: 'Hủy chọn',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_selectedBuyer == null)
                              InkWell(
                                onTap: _selectBuyer,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: colorScheme.outline.withValues(alpha: 0.3),
                                      style: BorderStyle.solid,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.person_add_alt_1_rounded,
                                        size: 40,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Mọi người mua (Bảng báo giá chung)',
                                        style: TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Bấm vào để chọn người mua cụ thể',
                                        style: TextStyle(fontSize: 12, color: colorScheme.outline),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: colorScheme.primaryContainer,
                                          child: Icon(Icons.person, color: colorScheme.onPrimaryContainer),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _selectedBuyer?['buyer_name'] ?? 'Không tên',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Mã khách: ${_selectedBuyer?['buyer_code'] ?? 'N/A'}',
                                                style: TextStyle(
                                                  color: colorScheme.primary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: _selectBuyer,
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          ),
                                          icon: const Icon(Icons.swap_horiz, size: 16),
                                          label: const Text('Thay đổi', style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 20),
                                    if (_selectedBuyer?['address'] != null &&
                                        _selectedBuyer?['address'].toString().isNotEmpty == true) ...[
                                      Row(
                                        children: [
                                          Icon(Icons.location_on_outlined, size: 16, color: colorScheme.outline),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _selectedBuyer!['address'],
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    if (_selectedBuyer?['phone_number'] != null &&
                                        _selectedBuyer?['phone_number'].toString().isNotEmpty == true) ...[
                                      Row(
                                        children: [
                                          Icon(Icons.phone_outlined, size: 16, color: colorScheme.outline),
                                          const SizedBox(width: 8),
                                          Text(
                                            _selectedBuyer!['phone_number'],
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Custom item list header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Mặt hàng áp dụng (${_priceItems.length})',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addItem,
                          icon: const Icon(Icons.add),
                          label: const Text('THÊM MẶT HÀNG'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Custom item prices list
                    if (_priceItems.isEmpty)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 48, color: colorScheme.outline),
                              const SizedBox(height: 12),
                              Text(
                                'Chưa có mặt hàng nào được thiết lập giá tùy chỉnh',
                                style: TextStyle(color: colorScheme.outline, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _addItem,
                                icon: const Icon(Icons.add),
                                label: const Text('Thêm mặt hàng đầu tiên'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _priceItems.length,
                        itemBuilder: (context, index) {
                          final itm = _priceItems[index];
                          final customPrice = itm['unit_price_custom'] as int;

                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 8),
                            color: colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              title: Text(
                                itm['item_default_name'] ?? 'Mặt hàng không tên',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme.secondaryContainer,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        itm['unit_name'] ?? 'Cái',
                                        style: TextStyle(
                                          color: colorScheme.onSecondaryContainer,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    CurrencyFormatter.formatVND(customPrice),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                    onPressed: () => _editItem(index),
                                    tooltip: 'Sửa giá',
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline_rounded, size: 20, color: colorScheme.error),
                                    onPressed: () => _removeItem(index),
                                    tooltip: 'Xóa giá',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _isLoading || _isSaving
          ? const SizedBox.shrink()
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(top: BorderSide(color: colorScheme.outline.withValues(alpha: 0.15))),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _savePriceList,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'LƯU THAY ĐỔI',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
