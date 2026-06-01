import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';
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
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _selectedBuyer;
  final List<Map<String, dynamic>> _priceItems = [];
  bool _isLoading = false;
  bool _isInitialized = false;
  int? _pickedIndex;
  String? _highlightedItemKey; // 'itemId_unitId' of the newly added item

  String _initialDescription = '';
  String? _initialBuyerId;
  List<Map<String, dynamic>> _initialPriceItems = [];

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
          _initialPriceItems = _priceItems.map((itm) => Map<String, dynamic>.from(itm)).toList();
        });
      }
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _scrollController.dispose();
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
    
    Map<String, dynamic>? largestRatioUnit;
    if (units.isNotEmpty) {
      largestRatioUnit = Map<String, dynamic>.from(units[0]);
      num maxRatio = largestRatioUnit['ratio'] ?? 0;
      for (var u in units) {
        final num r = u['ratio'] ?? 0;
        if (r > maxRatio) {
          maxRatio = r;
          largestRatioUnit = Map<String, dynamic>.from(u);
        }
      }
    }

    String? currentUnitId = index != null 
        ? item['unitId'] 
        : (item['selectedUnitId'] ?? (largestRatioUnit != null ? largestRatioUnit['unitId'] : null));
    
    // Setup initial price
    int initialPrice = 0;
    if (index != null) {
      initialPrice = item['unitPriceCustom'] as int? ?? 0;
    } else if (item['selectedUnit'] != null) {
      initialPrice = (item['selectedUnit']['unitPriceDefault'] as num?)?.toInt() ?? 0;
    } else if (largestRatioUnit != null) {
      initialPrice = (largestRatioUnit['unitPriceDefault'] as num?)?.toInt() ?? 0;
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
                if (u['unitId'] == currentUnitId) {
                  selectedUnitObj = u as Map<String, dynamic>;
                  break;
                }
              }
            }

            final defaultPrice = selectedUnitObj != null
                ? (selectedUnitObj['unitPriceDefault'] as num?)?.toInt() ?? 0
                : 0;

            final itemName = item['itemDefaultName'] ?? 'Mặt hàng không tên';

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
                          final isSelected = u['unitId'] == currentUnitId;
                          final uPrice = (u['unitPriceDefault'] as num?)?.toInt() ?? 0;
                          final priceFormatted = CurrencyFormatter.formatVND(uPrice);
                          
                          return ChoiceChip(
                            label: Text('${u['unitName']} ($priceFormatted)'),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setDialogState(() {
                                  currentUnitId = u['unitId'];
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
                      unitName = selectedUnitObj['unitName'] ?? 'Cái';
                    } else if (item['unitName'] != null) {
                      unitName = item['unitName'];
                    }

                    setState(() {
                      final itemData = {
                        'itemId': item['itemId'] ?? item['id'],
                        'itemDefaultName': itemName,
                        'unitId': currentUnitId,
                        'unitName': unitName,
                        'unitPriceCustom': price,
                        'unitPriceDefault': defaultPrice,
                        'units': units, // Preserve for subsequent editing
                      };

                      if (index != null) {
                        _priceItems[index] = itemData;
                      } else {
                        // Check if item-unit combination already exists
                        final existingIdx = _priceItems.indexWhere((element) =>
                            element['itemId'] == itemData['itemId'] &&
                            element['unitId'] == itemData['unitId']);
                        
                        if (existingIdx != -1) {
                          _priceItems[existingIdx] = itemData;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã cập nhật giá mặt hàng trùng lặp')),
                          );
                        } else {
                          _priceItems.add(itemData);
                          // Set highlight key for new items
                          _highlightedItemKey = '${itemData['itemId']}_${itemData['unitId']}';
                        }
                      }
                    });

                    Navigator.pop(dialogContext);

                    // Scroll to bottom and show highlight after dialog closes
                    if (index == null) {
                      Future.delayed(const Duration(milliseconds: 200), () async {
                        if (mounted && _scrollController.hasClients) {
                          await _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOut,
                          );
                        }
                        await Future.delayed(const Duration(milliseconds: 1400));
                        if (mounted) setState(() => _highlightedItemKey = null);
                      });
                    }
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

  bool _hasUnsavedChanges() {
    if (_isLoading) return false;
    if (_descriptionController.text.trim() != _initialDescription.trim()) return true;
    
    final currentBuyerId = _selectedBuyer?['buyerId']?.toString();
    if (currentBuyerId != _initialBuyerId) return true;
    
    if (_priceItems.length != _initialPriceItems.length) return true;
    
    for (int i = 0; i < _priceItems.length; i++) {
      final cur = _priceItems[i];
      final init = _initialPriceItems[i];
      if (cur['itemId'] != init['itemId'] ||
          cur['unitId'] != init['unitId'] ||
          cur['unitPriceCustom'] != init['unitPriceCustom']) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _savePriceListWithResult() async {
    if (!_formKey.currentState!.validate()) return false;

    if (_priceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng thêm ít nhất một mặt hàng vào bảng báo giá'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    setState(() => _isLoading = true);

    try {
      // Map frontend model list to Go API Request format
      final formattedItems = _priceItems.map((itm) {
        return {
          'itemId': itm['itemId'],
          'unitId': itm['unitId'],
          'unitPriceCustom': itm['unitPriceCustom'],
        };
      }).toList();

      await _apiService.createCustomerPriceList(
        description: _descriptionController.text.trim(),
        buyerId: _selectedBuyer?['buyerId'],
        items: formattedItems,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _initialDescription = _descriptionController.text.trim();
          _initialBuyerId = _selectedBuyer?['buyerId']?.toString();
          _initialPriceItems = _priceItems.map((itm) => Map<String, dynamic>.from(itm)).toList();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tạo bảng báo giá thành công!'),
            backgroundColor: Colors.green,
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tạo bảng báo giá: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return false;
    }
  }

  void _savePriceList() async {
    final success = await _savePriceListWithResult();
    if (success && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<bool> _showBackConfirmationDialog() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colorScheme.error),
              const SizedBox(width: 8),
              const Text('Chưa lưu thay đổi'),
            ],
          ),
          content: const Text(
            'Bạn chưa lưu bảng báo giá mới này. Bạn có chắc chắn muốn thoát không?',
          ),
          actionsAlignment: MainAxisAlignment.end,
          actionsOverflowButtonSpacing: 8,
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('HỦY'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
              ),
              child: const Text('THOÁT KHÔNG LƯU'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: const Text('LƯU VÀ THOÁT'),
            ),
          ],
        );
      },
    );

    if (result == 'discard') {
      return true;
    } else if (result == 'save') {
      final success = await _savePriceListWithResult();
      return success;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_hasUnsavedChanges(),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _showBackConfirmationDialog();
        if (shouldPop && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tạo bảng báo giá mới'),
        ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                controller: _scrollController,
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
                                    final buyerName = _selectedBuyer?['buyerName'] ?? 'lẻ';
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
                                                _selectedBuyer?['buyerName'] ?? 'Không tên',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Mã khách: ${_selectedBuyer?['buyerCode'] ?? 'N/A'}',
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
                                    if (_selectedBuyer?['phoneNumber'] != null &&
                                        _selectedBuyer?['phoneNumber'].toString().isNotEmpty == true) ...[
                                      Row(
                                        children: [
                                          Icon(Icons.phone_outlined, size: 16, color: colorScheme.outline),
                                          const SizedBox(width: 8),
                                          Text(
                                            _selectedBuyer!['phoneNumber'],
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

                            final filteredItems = itemsWithOrigIndex;

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
                                    key: ValueKey('${item['itemId']}_${item['unitId']}'),
                                    index: idx,
                                    child: PriceItemCard(
                                      item: item,
                                      index: origIndex,
                                      isPicked: false,
                                      isHighlighted: _highlightedItemKey != null &&
                                          _highlightedItemKey == '${item['itemId']}_${item['unitId']}',
                                      onTap: () {
                                        final tappedFilteredIdx = idx;
                                        setState(() {
                                          _pickedIndex = origIndex;
                                        });

                                        // Compensate scroll for insert slots appearing above
                                        WidgetsBinding.instance.addPostFrameCallback((_) async {
                                          if (mounted) {
                                            // Wait for the slot expansion animation to complete first
                                            await Future.delayed(const Duration(milliseconds: 310));
                                            if (mounted && _scrollController.hasClients) {
                                              const slotHeight = 44.0 + 8.0; // height + vertical margin
                                              final extraOffset = tappedFilteredIdx * slotHeight;
                                              final target = (_scrollController.offset + extraOffset)
                                                  .clamp(0.0, _scrollController.position.maxScrollExtent);
                                              
                                              _scrollController.animateTo(
                                                target,
                                                duration: const Duration(milliseconds: 250),
                                                curve: Curves.easeOut,
                                              );
                                            }
                                          }
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
                                      isHighlighted: _highlightedItemKey != null &&
                                          _highlightedItemKey == '${filteredItems[j]['itemId']}_${filteredItems[j]['unitId']}',
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
                    // Quick-add button at the bottom of the list
                    const SizedBox(height: 12),
                    Center(
                      child: IconButton.filled(
                        onPressed: _addItem,
                        icon: const Icon(Icons.add),
                        tooltip: 'Thêm mặt hàng',
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                    ),
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
      ),
    );
  }
}
