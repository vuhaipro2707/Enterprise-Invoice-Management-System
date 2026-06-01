import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';
import '../../widgets/price_item_card.dart';

class EditPriceListScreen extends StatefulWidget {
  const EditPriceListScreen({super.key});

  @override
  State<EditPriceListScreen> createState() => _EditPriceListScreenState();
}

class _EditPriceListScreenState extends State<EditPriceListScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _pricelistId;
  Map<String, dynamic>? _selectedBuyer;
  List<Map<String, dynamic>> _priceItems = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isInitialized = false;
  bool _isDeleted = false;
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
      if (args != null) {
        if (args is String) {
          _pricelistId = args;
        } else if (args is Map<String, dynamic>) {
          _pricelistId = args['pricelistId']?.toString();
          _isDeleted = args['isDeleted'] == true;
        }
        
        if (_pricelistId != null) {
          _fetchPriceListDetails();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không tìm thấy thông tin ID bảng báo giá')),
          );
          Navigator.pop(context);
        }
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
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPriceListDetails() async {
    if (_pricelistId == null) return;
    
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getCustomerPriceList(_pricelistId!);
      
      setState(() {
        _descriptionController.text = data['description'] ?? '';
        _initialDescription = _descriptionController.text;
        
        if (data['buyerId'] != null) {
          _selectedBuyer = {
            'buyerId': data['buyerId'],
            'buyerName': data['buyerName'],
            'buyerCode': data['buyerCode'],
            'phoneNumber': data['phoneNumber'],
            'address': data['address'],
          };
          _initialBuyerId = data['buyerId']?.toString();
        } else {
          _selectedBuyer = null;
          _initialBuyerId = null;
        }

        // Map item_prices array from DB query to local state format
        final List<dynamic> rawItems = data['itemPrices'] as List? ?? [];
        _priceItems = rawItems.map((itm) {
          return {
            'customerItemPriceId': itm['customerItemPriceId'],
            'itemId': itm['itemId'],
            'itemDefaultName': itm['itemDefaultName'] ?? 'Mặt hàng không tên',
            'unitId': itm['unitId'],
            'unitName': itm['unitName'] ?? 'Cái',
            'unitPriceCustom': (itm['unitPriceCustom'] as num?)?.toInt() ?? 0,
            'unitPriceDefault': 0, // Not stored in price lists, we will treat it as 0
            'units': <dynamic>[], // Will load empty unless we search again
          };
        }).toList();
        
        _initialPriceItems = _priceItems.map((itm) => Map<String, dynamic>.from(itm)).toList();
        
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
      _showAddOrEditItemDialog(item: item, isNewItem: true);
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

  Future<void> _onReorderPriceItems(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final movedItem = _priceItems[oldIndex];
    final String? customerItemPriceId = movedItem['customerItemPriceId'];

    setState(() {
      final item = _priceItems.removeAt(oldIndex);
      _priceItems.insert(newIndex, item);
    });

    if (customerItemPriceId == null || _pricelistId == null) {
      return;
    }

    String? prevId;
    String? nextId;

    if (newIndex > 0) {
      prevId = _priceItems[newIndex - 1]['customerItemPriceId'];
    }
    if (newIndex < _priceItems.length - 1) {
      nextId = _priceItems[newIndex + 1]['customerItemPriceId'];
    }

    try {
      await _apiService.changePriceItemOrder(_pricelistId!, customerItemPriceId, prevId, nextId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi đổi vị trí: $e')));
        _fetchPriceListDetails(); // Revert on failure
      }
    }
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
                  _onReorderPriceItems(pickedIndex, targetIndex);
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

  void _showAddOrEditItemDialog({required Map<String, dynamic> item, int? index, bool isNewItem = false}) {
    final colorScheme = Theme.of(context).colorScheme;
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
            final currentUnitName = item['unitName'] ?? 'Cái';

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
                      unitName = selectedUnitObj['unitName'] ?? 'Cái';
                    }

                    setState(() {
                      final itemData = {
                        'customerItemPriceId': item['customerItemPriceId'],
                        'itemId': item['itemId'] ?? item['id'],
                        'itemDefaultName': itemName,
                        'unitId': currentUnitId,
                        'unitName': unitName,
                        'unitPriceCustom': price,
                        'unitPriceDefault': defaultPrice,
                        'units': units,
                      };

                      if (index != null) {
                        _priceItems[index] = itemData;
                      } else {
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
                          if (isNewItem) {
                            final key = '${itemData['itemId']}_${itemData['unitId']}';
                            _highlightedItemKey = key;
                          }
                        }
                      }
                    });

                    Navigator.pop(dialogContext);

                    // Scroll to bottom and show highlight after dialog closes
                    if (isNewItem) {
                      Future.delayed(const Duration(milliseconds: 300), () async {
                        if (mounted && _scrollController.hasClients) {
                          await _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                          );
                        }
                        await Future.delayed(const Duration(milliseconds: 1300));
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
    if (_isSaving || _isLoading) return false;
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
    if (!_formKey.currentState!.validate() || _pricelistId == null) return false;

    if (_priceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng thêm ít nhất một mặt hàng vào bảng báo giá'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    setState(() => _isSaving = true);

    try {
      final formattedItems = _priceItems.map((itm) {
        return {
          'itemId': itm['itemId'],
          'unitId': itm['unitId'],
          'unitPriceCustom': itm['unitPriceCustom'],
        };
      }).toList();

      await _apiService.updateCustomerPriceList(
        _pricelistId!,
        description: _descriptionController.text.trim(),
        buyerId: _selectedBuyer?['buyerId'],
        items: formattedItems,
      );

      if (mounted) {
        setState(() {
          _isSaving = false;
          _initialDescription = _descriptionController.text.trim();
          _initialBuyerId = _selectedBuyer?['buyerId']?.toString();
          _initialPriceItems = _priceItems.map((itm) => Map<String, dynamic>.from(itm)).toList();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cập nhật bảng báo giá thành công!'),
            backgroundColor: Colors.green,
          ),
        );
        return true;
      }
      return false;
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
            'Bạn chưa lưu các chỉnh sửa của bảng báo giá này. Bạn có chắc chắn muốn thoát không?',
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
          'Bạn có chắc chắn muốn xóa bảng báo giá này không? Bạn có thể khôi phục lại từ Thùng rác.',
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

  Future<void> _restorePriceList() async {
    if (_pricelistId == null) return;
    setState(() => _isLoading = true);
    try {
      await _apiService.restoreCustomerPriceList(_pricelistId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Khôi phục bảng báo giá thành công!'),
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
            content: Text('Lỗi khi khôi phục bảng báo giá: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
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
        title: Text(_isDeleted ? 'Chi tiết bảng báo giá (Đã xóa)' : 'Sửa bảng báo giá'),
        actions: [
          if (_isDeleted) ...[
            IconButton(
              icon: const Icon(Icons.restore_rounded),
              onPressed: _isLoading || _isSaving ? null : _restorePriceList,
              tooltip: 'Khôi phục',
            ),
          ] else if (!_isLoading && !_isSaving) ...[
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Tạo bản sao'),
                      ],
                    ),
                    content: const Text(
                      'Tất cả các mặt hàng và giá tùy chỉnh sẽ được chép nguyên vẹn sang bản sao mới. Bạn có muốn tiếp tục?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('HỦY'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('TIẾP TỤC'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  navigator.pushReplacementNamed(
                    '/create_pricelist',
                    arguments: _priceItems,
                  );
                }
              },
              tooltip: 'Tạo bản sao',
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
              onPressed: _deletePriceList,
              tooltip: 'Xóa báo giá',
            ),
          ],
        ],
      ),
      body: _isLoading || _isSaving
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
                              enabled: !_isDeleted,
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
                                if (_selectedBuyer != null && !_isDeleted)
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
                                onTap: _isDeleted ? null : _selectBuyer,
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
                                        _isDeleted
                                            ? 'Áp dụng cho mọi người mua'
                                            : 'Bấm vào để chọn người mua cụ thể',
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
                                        if (!_isDeleted)
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
                        if (!_isDeleted)
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
                              if (!_isDeleted)
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

                            if (_isDeleted) {
                              return ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filteredItems.length,
                                itemBuilder: (context, idx) {
                                  final item = filteredItems[idx];
                                  final origIndex = item['orig_index'];
                                  return PriceItemCard(
                                    item: item,
                                    index: origIndex,
                                    isPicked: false,
                                    onTap: null,
                                    onEdit: null,
                                    onDelete: null,
                                  );
                                },
                              );
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
                                  
                                  _onReorderPriceItems(oldOrigIndex, newOrigIndex);
                                },
                                itemBuilder: (context, idx) {
                                  final item = filteredItems[idx];
                                  final origIndex = item['orig_index'];
                                  return ReorderableDelayedDragStartListener(
                                    key: ValueKey(item['customerItemPriceId'] ?? '${item['itemId']}_${item['unitId']}'),
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
                                            // Wait for the slot expansion and container resizing animation to complete first
                                            await Future.delayed(const Duration(milliseconds: 310));
                                            if (mounted && _scrollController.hasClients) {
                                              const slotHeight = 44.0 + 8.0;
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
                    if (!_isDeleted) ...[
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
                    ],
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
                  child: ElevatedButton.icon(
                    onPressed: _isDeleted ? _restorePriceList : _savePriceList,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDeleted ? colorScheme.primaryContainer : colorScheme.primary,
                      foregroundColor: _isDeleted ? colorScheme.onPrimaryContainer : colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(_isDeleted ? Icons.restore_rounded : Icons.save_rounded),
                    label: Text(
                      _isDeleted ? 'KHÔI PHỤC BẢNG BÁO GIÁ' : 'LƯU THAY ĐỔI',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}
