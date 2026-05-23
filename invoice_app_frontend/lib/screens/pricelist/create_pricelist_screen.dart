import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';
import '../../services/string_utils.dart';
import '../../widgets/price_item_card.dart';

class CreatePriceListScreen extends StatefulWidget {
  const CreatePriceListScreen({super.key});

  @override
  State<CreatePriceListScreen> createState() => _CreatePriceListScreenState();
}

class _CreatePriceListScreenState extends State<CreatePriceListScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  Map<String, dynamic>? _selectedBuyer;
  final List<Map<String, dynamic>> _priceItems = [];
  bool _isLoading = false;
  bool _isInitialized = false;
  int? _pickedIndex;
  String _localSearchQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args != null && args is List) {
        setState(() {
          _priceItems.clear();
          for (var item in args) {
            if (item is Map) {
              _priceItems.add(Map<String, dynamic>.from(item));
            }
          }
        });
      }
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
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

  Widget _buildInsertSlot(BuildContext context, int targetIndex, int? pickedIndex) {
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
                  var destIndex = targetIndex;
                  if (destIndex > pickedIndex) destIndex -= 1;
                  setState(() {
                    final item = _priceItems.removeAt(pickedIndex);
                    _priceItems.insert(destIndex, item);
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

  void _showAddOrEditItemDialog({required Map<String, dynamic> item, int? index}) {
    final colorScheme = Theme.of(context).colorScheme;

    // Get units array from item. When we edit, it might be nested differently, so look for both structures
    final List<dynamic> units = item['units'] as List? ?? [];
    
    String? currentUnitId = index != null ? item['unit_id'] : (units.isNotEmpty ? units[0]['unit_id'] : null);
    
    // Setup initial price
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
            // Find selected unit object
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
                                  // Update the custom price text field with default price of new unit
                                  priceController.text = NumberFormat.decimalPattern('vi_VN').format(uPrice);
                                });
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
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
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.restore),
                          tooltip: 'Dùng giá gốc',
                          onPressed: () {
                            setDialogState(() {
                              priceController.text = NumberFormat.decimalPattern('vi_VN').format(defaultPrice);
                            });
                          },
                        ),
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

                    // Get selected unit details
                    String unitName = 'Cái';
                    if (selectedUnitObj != null) {
                      unitName = selectedUnitObj['unit_name'] ?? 'Cái';
                    } else if (item['unit_name'] != null) {
                      unitName = item['unit_name'];
                    }

                    setState(() {
                      final itemData = {
                        'item_id': item['item_id'] ?? item['id'],
                        'item_default_name': itemName,
                        'unit_id': currentUnitId,
                        'unit_name': unitName,
                        'unit_price_custom': price,
                        'unit_price_default': defaultPrice,
                        'units': units, // Preserve for subsequent editing
                      };

                      if (index != null) {
                        _priceItems[index] = itemData;
                      } else {
                        // Check if item-unit combination already exists
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
    if (!_formKey.currentState!.validate()) return;

    if (_priceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng thêm ít nhất một mặt hàng vào bảng báo giá'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Map frontend model list to Go API Request format
      final formattedItems = _priceItems.map((itm) {
        return {
          'itemId': itm['item_id'],
          'unitId': itm['unit_id'],
          'unitPriceCustom': itm['unit_price_custom'],
        };
      }).toList();

      await _apiService.createCustomerPriceList(
        description: _descriptionController.text.trim(),
        buyerId: _selectedBuyer?['buyer_id'],
        items: formattedItems,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tạo bảng báo giá thành công!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tạo bảng báo giá: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo bảng báo giá mới'),
      ),
      body: _isLoading
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
                              decoration: InputDecoration(
                                labelText: 'Mô tả / Tên bảng báo giá *',
                                border: const OutlineInputBorder(),
                                hintText: 'Ví dụ: Báo giá đại lý tháng 5/2026',
                                alignLabelWithHint: true,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    Icons.auto_awesome,
                                    color: colorScheme.primary,
                                  ),
                                  tooltip: 'Tạo mô tả mặc định',
                                  onPressed: () {
                                    final buyerName = _selectedBuyer?['buyer_name'] ?? 'lẻ';
                                    final nowStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
                                    _descriptionController.text = 'Báo giá khách hàng $buyerName ngày $nowStr';
                                  },
                                ),
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
                            for (int i = 0; i < _priceItems.length; i++) {
                              final itm = Map<String, dynamic>.from(_priceItems[i]);
                              itm['orig_index'] = i;
                              itemsWithOrigIndex.add(itm);
                            }

                            final filteredItems = itemsWithOrigIndex.where((itm) {
                              final name = (itm['item_default_name'] ?? '').toString();
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
                                  
                                  setState(() {
                                    if (newOrigIndex > oldOrigIndex) newOrigIndex -= 1;
                                    final item = _priceItems.removeAt(oldOrigIndex);
                                    _priceItems.insert(newOrigIndex, item);
                                  });
                                },
                                itemBuilder: (context, idx) {
                                  final item = filteredItems[idx];
                                  final origIndex = item['orig_index'];
                                  return ReorderableDelayedDragStartListener(
                                    key: ValueKey('${item['item_id']}_${item['unit_id']}'),
                                    index: idx,
                                    child: PriceItemCard(
                                      item: item,
                                      index: origIndex,
                                      isPicked: false,
                                      onTap: () {
                                        setState(() {
                                          _pickedIndex = origIndex;
                                        });
                                      },
                                      onEdit: () => _editItem(origIndex),
                                      onDelete: () => _removeItem(origIndex),
                                    ),
                                  );
                                },
                              );
                            } else {
                              return Column(
                                children: [
                                  _buildInsertSlot(builderContext, filteredItems[0]['orig_index'], _pickedIndex!),
                                  for (int j = 0; j < filteredItems.length; j++) ...[
                                    PriceItemCard(
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
                                      onEdit: () => _editItem(filteredItems[j]['orig_index']),
                                      onDelete: () => _removeItem(filteredItems[j]['orig_index']),
                                    ),
                                    _buildInsertSlot(
                                      builderContext,
                                      j < filteredItems.length - 1 
                                          ? filteredItems[j + 1]['orig_index'] 
                                          : filteredItems[j]['orig_index'] + 1,
                                      _pickedIndex!,
                                    ),
                                  ],
                                ],
                              );
                            }
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 80), // Padding to avoid overlap with bottom button
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _isLoading
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
                      'LƯU BẢNG BÁO GIÁ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
