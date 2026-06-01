import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';
import '../../widgets/unit_autocomplete_field.dart';


class CreateLineItemScreen extends StatefulWidget {
  final String invoiceId;
  final Map<String, dynamic>? existingLineItem;
  const CreateLineItemScreen({super.key, this.invoiceId = '', this.existingLineItem});

  @override
  State<CreateLineItemScreen> createState() => _CreateLineItemScreenState();
}

class _CreateLineItemScreenState extends State<CreateLineItemScreen> {
  final ApiService _apiService = ApiService();
  final _itemNameController = TextEditingController();
  final _unitNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _scrollController = ScrollController();
  final _unitFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();
  bool _isSaving = false;
  // Tracks the pre-filled unit name for Autocomplete's initialValue / key
  String _unitInitialValue = '';
  bool _isManualInputExpanded = false;

  String? _currentInvoiceId;
  Map<String, dynamic>? _currentExistingLineItem;
  bool _isInitialized = false;

  Map<String, dynamic>? _selectedItem;
  List<dynamic> _availableUnits = [];
  String? _selectedUnitId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _currentInvoiceId = args['invoiceId'];
        _currentExistingLineItem = args['existingLineItem'];

        if (_currentExistingLineItem != null) {
          final item = _currentExistingLineItem!;
          _itemNameController.text = item['itemNameSnapshot'] ?? '';
          final unitName = item['unitNameSnapshot'] ?? '';
          _unitNameController.text = unitName;
          _unitInitialValue = unitName;
          _quantityController.text = (item['quantity'] ?? 0).toString();
          _priceController.text = NumberFormat.decimalPattern('vi_VN').format(item['unitPriceCustom'] ?? 0);
          _selectedUnitId = item['unitId'];
          _isManualInputExpanded = true;
        }
      } else {
        _currentInvoiceId = widget.invoiceId;
        _currentExistingLineItem = widget.existingLineItem;
      }
      _isInitialized = true;
    }
  }

  @override
  void initState() {
    super.initState();
    // Logic moved to didChangeDependencies to handle named routes arguments
  }

  void _openSearch() async {
    final result = await Navigator.pushNamed(context, '/line_item_search');

    if (!mounted) return;

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedItem = result;
        _itemNameController.text = result['itemDefaultName'] ?? '';
        _availableUnits = result['units'] as List? ?? [];
        _isManualInputExpanded = true;
        
        if (result['selectedUnit'] != null) {
          _onUnitSelected(Map<String, dynamic>.from(result['selectedUnit']));
        } else if (_availableUnits.isNotEmpty) {
          Map<String, dynamic> largestRatioUnit = Map<String, dynamic>.from(_availableUnits[0]);
          num maxRatio = largestRatioUnit['ratio'] ?? 0;
          for (var u in _availableUnits) {
            final num r = u['ratio'] ?? 0;
            if (r > maxRatio) {
              maxRatio = r;
              largestRatioUnit = Map<String, dynamic>.from(u);
            }
          }
          _onUnitSelected(largestRatioUnit);
        } else {
          _unitNameController.clear();
          _priceController.clear();
          _selectedUnitId = null;
        }
      });
      _scrollToBottom();
    }
  }

  void _onUnitSelected(Map<String, dynamic> unit) {
    final unitName = unit['unitName'] as String? ?? '';
    setState(() {
      _selectedUnitId = unit['unitId'];
      _unitNameController.text = unitName;
      _unitInitialValue = unitName; // triggers Autocomplete key rebuild
      final rawPrice = unit['unitPriceDefault'] ?? 0;
      _priceController.text = NumberFormat.decimalPattern('vi_VN').format(rawPrice);
    });
    
    // Auto focus quantity field after unit selection (waiting for transition animation to complete)
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) {
        _quantityFocusNode.requestFocus();
        // Wait for keyboard to fully pop up and resize the viewport, then scroll to bottom
        _scrollToBottom(delayMs: 500);
      }
    });
  }

  void _scrollToBottom({int delayMs = 700}) {
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_currentExistingLineItem != null ? 'Sửa dòng hàng' : 'Thêm dòng hàng')),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SECTION 1: CHỌN SẢN PHẨM TỪ DANH SÁCH (KHUYẾN KHÍCH)
            InkWell(
              onTap: _openSearch,
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.inventory_2_rounded,
                          color: colorScheme.onPrimary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedItem == null ? 'CHỌN SẢN PHẨM' : 'THAY ĐỔI SẢN PHẨM',
                              style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedItem == null
                                  ? 'Tìm kiếm nhanh theo tên, mã sản phẩm...'
                                  : _itemNameController.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onPrimary.withValues(alpha: 0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: colorScheme.onPrimary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // SECTION 2: NHẬP THỦ CÔNG (COLLAPSED BY DEFAULT)
            InkWell(
              onTap: () {
                setState(() {
                  _isManualInputExpanded = !_isManualInputExpanded;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: _isManualInputExpanded
                      ? colorScheme.primary.withValues(alpha: 0.05)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isManualInputExpanded
                        ? colorScheme.primary.withValues(alpha: 0.2)
                        : colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          color: _isManualInputExpanded ? colorScheme.primary : colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Nhập thông tin sản phẩm thủ công',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _isManualInputExpanded ? colorScheme.primary : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      _isManualInputExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _isManualInputExpanded ? colorScheme.primary : colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
            
            // Expandable manual inputs list
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedItem != null) ...[
                      Text('Chọn đơn vị tính:', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _availableUnits.map((unit) {
                          final isSelected = _selectedUnitId == unit['unitId'];
                          return ChoiceChip(
                            label: Text('${unit['unitName']} (${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(unit['unitPriceDefault'])})'),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) _onUnitSelected(unit);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _itemNameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên sản phẩm *',
                        border: OutlineInputBorder(),
                        hintText: 'Nhập tên hoặc chọn sản phẩm',
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Unit name field with autocomplete suggestions widget
                    UnitAutocompleteField(
                      controller: _unitNameController,
                      initialValue: _unitInitialValue,
                      onSelected: (selection) {
                        setState(() {
                          _unitInitialValue = selection;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _quantityController,
                            focusNode: _quantityFocusNode,
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
                  ],
                ),
              ),
              crossFadeState: _isManualInputExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
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
                    : Text(_currentExistingLineItem != null ? 'LƯU THAY ĐỔI' : 'XÁC NHẬN THÊM'),
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
      setState(() {
        _isManualInputExpanded = true;
      });
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
        "invoiceId": _currentInvoiceId,
        "itemId": _selectedItem != null ? (_selectedItem!['itemId'] ?? _selectedItem!['id']) : (_currentExistingLineItem?['itemId']),
        "unitId": _selectedUnitId,
        "itemNameSnapshot": itemName,
        "unitNameSnapshot": unitName,
        "quantity": qty.toInt(),
        "unitPriceCustom": price,
      };

      if (_currentExistingLineItem != null) {
        final lineItemId = _currentExistingLineItem!['lineItemId'];
        await _apiService.patchLineItem(lineItemId.toString(), payload);
      } else {
        await _apiService.createLineItem(_currentInvoiceId!, {
          "itemId": payload["itemId"],
          "unitId": payload["unitId"],
          "itemNameSnapshot": payload["itemNameSnapshot"],
          "unitNameSnapshot": payload["unitNameSnapshot"],
          "quantity": payload["quantity"],
          "unitPriceCustom": payload["unitPriceCustom"],
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _unitNameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _unitFocusNode.dispose();
    _quantityFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
