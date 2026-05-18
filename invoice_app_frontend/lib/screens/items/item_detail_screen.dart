import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';
import '../../widgets/type_selection_sheet.dart';

class ItemDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final List<dynamic> types;

  const ItemDetailScreen({super.key, required this.item, required this.types});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  final _otherNameInputController = TextEditingController();
  late List<Map<String, dynamic>> _otherNames;
  final List<Map<String, dynamic>> _units = [];
  final List<String> _removedOtherNameIds = [];
  final List<String> _removedUnitIds = [];
  
  String? _selectedTypeId;
  String? _selectedTypeName;
  late List<dynamic> _types;
  final _isLoadingTypes = false;
  bool _isSaving = false;
  final _otherNameFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item['item_default_name']);
    
    _otherNameFocusNode.addListener(() {
      if (!_otherNameFocusNode.hasFocus) {
        _addOtherName(_otherNameInputController.text);
      }
    });

    // Khởi tạo tên gọi khác kèm ID
    final rawOtherNames = widget.item['item_other_names'] as List? ?? [];
    _otherNames = rawOtherNames.map((e) {
      if (e is String) return {'item_other_name_id': null, 'name_string': e};
      return Map<String, dynamic>.from(e);
    }).toList();

    _selectedTypeId = widget.item['type_id'];
    _types = widget.types;

    // Tìm tên loại từ list types truyền vào
    if (_selectedTypeId != null) {
      final type = _types.firstWhere(
        (t) => t['type_id'] == _selectedTypeId,
        orElse: () => null,
      );
      if (type != null) {
        _selectedTypeName = type['type_name'];
      }
    }
    
    // Khởi tạo các đơn vị từ dữ liệu có sẵn
    final existingUnits = widget.item['units'] as List? ?? [];
    final formatter = NumberFormat.decimalPattern('vi_VN');
    for (var u in existingUnits) {
      String formattedPrice = '';
      if (u['unit_price_default'] != null) {
        formattedPrice = formatter.format(u['unit_price_default']);
      }
      _units.add({
        'unit_id': u['unit_id'],
        'nameController': TextEditingController(text: u['unit_name']),
        'priceController': TextEditingController(text: formattedPrice),
      });
    }
  }

  void _addUnit() {
    setState(() {
      _units.add({
        'nameController': TextEditingController(),
        'priceController': TextEditingController(),
      });
    });
  }

  void _removeUnit(int index) {
    setState(() {
      final unitId = _units[index]['unit_id'];
      if (unitId != null) {
        _removedUnitIds.add(unitId);
      }
      _units[index]['nameController'].dispose();
      _units[index]['priceController'].dispose();
      _units.removeAt(index);
    });
  }

  void _addOtherName(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && !_otherNames.any((e) => e['name_string'] == trimmed)) {
      setState(() {
        _otherNames.add({'item_other_name_id': null, 'name_string': trimmed});
        _otherNameInputController.clear();
      });
    }
  }

  void _removeOtherName(Map<String, dynamic> otherName) {
    setState(() {
      if (otherName['item_other_name_id'] != null) {
        _removedOtherNameIds.add(otherName['item_other_name_id']);
      }
      _otherNames.remove(otherName);
    });
  }

  void _showTypeSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return TypeSelectionSheet(
          initialTypes: _types,
          onTypeSelected: (type) {
            setState(() {
              _selectedTypeId = type['type_id'];
              _selectedTypeName = type['type_name'];
            });
          },
          onTypeCreated: (newType) {
            setState(() {
              _types.add(newType);
              _selectedTypeId = newType['type_id'];
              _selectedTypeName = newType['type_name'];
            });
          },
        );
      },
    );
  }

  Future<void> _saveChanges() async {
    _addOtherName(_otherNameInputController.text);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final itemId = widget.item['item_id'];
      
      // 1. Cập nhật thông tin cơ bản mặt hàng
      final Map<String, dynamic> itemUpdate = {};
      if (_nameController.text.trim() != widget.item['item_default_name']) {
        itemUpdate['itemDefaultName'] = _nameController.text.trim();
      }
      if (_selectedTypeId != widget.item['type_id']) {
        itemUpdate['typeId'] = _selectedTypeId;
      }
      
      if (itemUpdate.isNotEmpty) {
        await ApiService().patchItem(itemId, itemUpdate);
      }

      // 2. Cập nhật "Tên gọi khác"
      // Xóa các tên đã đánh dấu xóa
      for (var id in _removedOtherNameIds) {
        await ApiService().removeItemOtherName(id);
      }
      // Thêm những cái mới (không có ID)
      for (var on in _otherNames) {
        if (on['item_other_name_id'] == null) {
          await ApiService().addItemOtherName(itemId, on['name_string']);
        }
      }

      // 3. Cập nhật các đơn vị tính
      // Xóa các đơn vị đã đánh dấu xóa
      for (var id in _removedUnitIds) {
        await ApiService().deleteUnit(id);
      }

      final List<dynamic> originalUnits = widget.item['units'] as List? ?? [];

      for (var unit in _units) {
        String unitName = unit['nameController'].text.trim();
        // Viết hoa chữ cái đầu tiên của đơn vị
        if (unitName.isNotEmpty) {
          unitName = unitName[0].toUpperCase() + unitName.substring(1);
        }

        final rawPriceValue = unit['priceController'].text.replaceAll('.', '').trim();
        final unitPrice = int.tryParse(rawPriceValue);
        
        if (unit['unit_id'] == null) {
          // Tạo mới đơn vị nếu chưa có ID
          if (unitName.isNotEmpty) {
            await ApiService().createUnit(itemId, unitName, unitPrice);
          }
        } else {
          // Cập nhật đơn vị cũ nếu có thay đổi
          final String unitId = unit['unit_id'];
          final originalUnit = originalUnits.firstWhere((u) => u['unit_id'] == unitId, orElse: () => null);
          
          if (originalUnit != null) {
            final Map<String, dynamic> unitUpdate = {};
            if (unitName != originalUnit['unit_name']) unitUpdate['unitName'] = unitName;
            if (unitPrice != (originalUnit['unit_price_default'] as int?)) unitUpdate['unitPriceDefault'] = unitPrice;
            
            if (unitUpdate.isNotEmpty) {
              await ApiService().patchUnit(unitId, unitUpdate);
            }
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật mặt hàng thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _otherNameInputController.dispose();
    _otherNameFocusNode.dispose();
    for (var unit in _units) {
      unit['nameController'].dispose();
      unit['priceController'].dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết mặt hàng'),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _saveChanges,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            const Text(
              'Thông tin cơ bản',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên mặt hàng *',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Vui lòng nhập tên' : null,
            ),
            const SizedBox(height: 16),
            const Text('Tên gọi khác', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8.0,
              children: [
                ..._otherNames.map((on) => Chip(
                      label: Text(on['name_string']),
                      onDeleted: () => _removeOtherName(on),
                    )),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _otherNameInputController,
                    focusNode: _otherNameFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Thêm tên...',
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    onSubmitted: (value) => _addOtherName(value),
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            InkWell(
              onTap: _isLoadingTypes ? null : _showTypeSelectionSheet,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Loại hàng',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                child: _isLoadingTypes
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _selectedTypeName ?? 'Chọn loại hàng',
                        style: TextStyle(
                          color: _selectedTypeName == null
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Đơn vị tính & Giá',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _addUnit,
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm đơn vị'),
                ),
              ],
            ),
            ..._units.asMap().entries.map((entry) {
              int index = entry.key;
              var unit = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: unit['nameController'],
                          decoration: const InputDecoration(labelText: 'Đơn vị'),
                          validator: (value) => (value == null || value.isEmpty)
                              ? 'Nhập tên'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: unit['priceController'],
                          decoration: const InputDecoration(labelText: 'Giá'),
                          inputFormatters: [CurrencyInputFormatter()],
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _removeUnit(index),
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveChanges,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
              label: const Text('Cập nhật thay đổi'),
            ),
          ],
        ),
      ),
    );
  }
}
