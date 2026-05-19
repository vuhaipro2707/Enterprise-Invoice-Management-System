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
  bool _isSaving = false;

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
          _itemNameController.text = item['item_name_snapshot'] ?? '';
          _unitNameController.text = item['unit_name_snapshot'] ?? '';
          _quantityController.text = (item['quantity'] ?? 0).toString();
          _priceController.text = NumberFormat.decimalPattern('vi_VN').format(item['unit_price_custom'] ?? 0);
          _selectedUnitId = item['unit_id'];
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
        _itemNameController.text = result['item_default_name'] ?? '';
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
    setState(() {
      _selectedUnitId = unit['unit_id'];
      _unitNameController.text = unit['unit_name'] ?? '';
      final rawPrice = unit['unit_price_default'] ?? 0;
      _priceController.text = NumberFormat.decimalPattern('vi_VN').format(rawPrice);
    });
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
        "invoice_id": _currentInvoiceId,
        "item_id": _selectedItem != null ? (_selectedItem!['item_id'] ?? _selectedItem!['id']) : (_currentExistingLineItem?['item_id']),
        "unit_id": _selectedUnitId,
        "item_name_snapshot": itemName,
        "unit_name_snapshot": unitName,
        "quantity": qty.toInt(),
        "unit_price_custom": price,
      };

      if (_currentExistingLineItem != null) {
        final lineItemId = _currentExistingLineItem!['line_item_id'];
        await _apiService.patchLineItem(lineItemId.toString(), payload);
      } else {
        await _apiService.createLineItem(_currentInvoiceId!, {
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

  @override
  void dispose() {
    _itemNameController.dispose();
    _unitNameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }
}
