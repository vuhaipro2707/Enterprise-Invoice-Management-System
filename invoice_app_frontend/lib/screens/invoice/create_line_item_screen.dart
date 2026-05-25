import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';


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
  final _unitFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();
  bool _isSaving = false;
  // Tracks the pre-filled unit name for Autocomplete's initialValue / key
  String _unitInitialValue = '';

  // Common Vietnamese unit suggestions
  static const List<String> _unitSuggestions = [
    'Thùng', 'Túi', 'Hộp', 'Chai', 'Két',
    'Cái', 'Lon', 'Gói', 'Bao', 'Bình',
    'Lít', 'Kg', 'Gram', 'Mét', 'Cuộn',
    'Tấm', 'Đôi', 'Bộ', 'Chiếc', 'Viên',
  ];

  /// Normalize a string: lowercase + strip Vietnamese diacritics.
  static String _unaccent(String s) {
    const map = {
      // Latin basic
      'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y',
      // Vietnamese ă-family
      'ă': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
      // Vietnamese â-family
      'ấ': 'a', 'ầ': 'a', 'ẫ': 'a', 'ậ': 'a',
      // Vietnamese đ
      'đ': 'd',
      // Vietnamese e-family
      'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
      'ế': 'e', 'ề': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
      // Vietnamese i-family
      'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
      // Vietnamese o-family
      'ọ': 'o', 'ỏ': 'o',
      'ố': 'o', 'ồ': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ớ': 'o', 'ờ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      // Vietnamese u-family
      'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
      'ứ': 'u', 'ừ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
      // Vietnamese y-family
      'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
    };
    return s.toLowerCase().split('').map((c) => map[c] ?? c).join();
  }

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

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedItem = result;
        _itemNameController.text = result['itemDefaultName'] ?? '';
        _availableUnits = result['units'] as List? ?? [];
        if (_availableUnits.isNotEmpty) {
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
    final unitName = unit['unitName'] as String? ?? '';
    setState(() {
      _selectedUnitId = unit['unitId'];
      _unitNameController.text = unitName;
      _unitInitialValue = unitName; // triggers Autocomplete key rebuild
      final rawPrice = unit['unitPriceDefault'] ?? 0;
      _priceController.text = NumberFormat.decimalPattern('vi_VN').format(rawPrice);
    });
    
    // Auto focus quantity field after unit selection
    _quantityFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_currentExistingLineItem != null ? 'Sửa dòng hàng' : 'Thêm dòng hàng')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              const SizedBox(height: 20),
            ],
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
            // Unit name field with autocomplete suggestions
            Autocomplete<String>(
              // Key forces a rebuild (with new initialValue) when a unit chip is selected
              key: ValueKey(_unitInitialValue),
              initialValue: TextEditingValue(text: _unitInitialValue),
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) return const Iterable.empty();
                final query = _unaccent(textEditingValue.text);
                return _unitSuggestions.where(
                  (unit) => _unaccent(unit).contains(query),
                );
              },
              onSelected: (String selection) {
                setState(() {
                  _unitNameController.text = selection;
                  _unitInitialValue = selection;
                });
              },
              fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: textController,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Đơn vị tính *',
                    border: OutlineInputBorder(),
                    hintText: 'Cái, Thùng, Lon...',
                    suffixIcon: Icon(Icons.expand_more),
                  ),
                  // Keep external controller in sync so _save() reads correctly
                  onChanged: (value) => _unitNameController.text = value,
                  onSubmitted: (_) => onFieldSubmitted(),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.straighten_rounded, size: 18),
                            title: Text(option),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
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
    super.dispose();
  }
}
