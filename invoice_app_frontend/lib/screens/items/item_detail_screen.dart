import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/type_selection_sheet.dart';
import '../../widgets/units_section.dart';

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
  final _formatter = NumberFormat.decimalPattern('vi_VN');

  TextEditingController _getNameController(Map<String, dynamic> unit) {
    if (unit['nameController'] == null) {
      unit['nameController'] = TextEditingController();
    }
    return unit['nameController'] as TextEditingController;
  }

  TextEditingController _getPriceController(Map<String, dynamic> unit) {
    if (unit['priceController'] == null) {
      unit['priceController'] = TextEditingController();
    }
    return unit['priceController'] as TextEditingController;
  }

  TextEditingController _getRatioController(Map<String, dynamic> unit) {
    if (unit['ratioController'] == null) {
      unit['ratioController'] = TextEditingController(text: '1');
    }
    return unit['ratioController'] as TextEditingController;
  }

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
    
    // Sắp xếp sao cho đơn vị gốc luôn đứng đầu tiên
    final List<dynamic> sortedUnits = List.from(existingUnits);
    sortedUnits.sort((a, b) {
      final aBase = a['is_base_unit'] ?? false;
      final bBase = b['is_base_unit'] ?? false;
      if (aBase && !bBase) return -1;
      if (!aBase && bBase) return 1;
      return 0;
    });

    for (var u in sortedUnits) {
      String formattedPrice = '';
      if (u['unit_price_default'] != null) {
        formattedPrice = _formatter.format(u['unit_price_default']);
      }
      _units.add({
        'unit_id': u['unit_id'],
        'nameController': TextEditingController(text: u['unit_name']),
        'priceController': TextEditingController(text: formattedPrice),
        'ratioController': TextEditingController(text: (u['ratio'] ?? 1).toString()),
        'isBaseUnit': u['is_base_unit'] ?? false,
      });
    }
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
      builder: (sheetContext) {
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
        String unitName = _getNameController(unit).text.trim();
        // Viết hoa chữ cái đầu tiên của đơn vị
        if (unitName.isNotEmpty) {
          unitName = unitName[0].toUpperCase() + unitName.substring(1);
        }

        final rawPriceValue = _getPriceController(unit).text.replaceAll('.', '').trim();
        final unitPrice = int.tryParse(rawPriceValue);
        
        final ratioStr = _getRatioController(unit).text.trim();
        final ratio = int.tryParse(ratioStr) ?? 1;
        final isBaseUnit = unit['isBaseUnit'] ?? false;
        
        if (unit['unit_id'] == null) {
          // Tạo mới đơn vị nếu chưa có ID
          if (unitName.isNotEmpty) {
            await ApiService().createUnit(
              itemId, 
              unitName, 
              unitPrice,
              ratio: ratio,
              isBaseUnit: isBaseUnit,
            );
          }
        } else {
          // Cập nhật đơn vị cũ nếu có thay đổi
          final String unitId = unit['unit_id'];
          final originalUnit = originalUnits.firstWhere((u) => u['unit_id'] == unitId, orElse: () => null);
          
          if (originalUnit != null) {
            final Map<String, dynamic> unitUpdate = {};
            if (unitName != originalUnit['unit_name']) unitUpdate['unitName'] = unitName;
            if (ratio != (originalUnit['ratio'] as int?)) unitUpdate['ratio'] = ratio;
            if (isBaseUnit != (originalUnit['is_base_unit'] as bool?)) unitUpdate['isBaseUnit'] = isBaseUnit;
            
            // Only update unitPriceDefault for the Base Unit.
            // Secondary units' prices are automatically recalculated and propagated by the DB trigger.
            if (isBaseUnit) {
              if (unitPrice != (originalUnit['unit_price_default'] as int?)) {
                unitUpdate['unitPriceDefault'] = unitPrice;
              }
            }
            
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
            UnitsSection(units: _units, removedUnitIds: _removedUnitIds),
            const SizedBox(height: 32),
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
