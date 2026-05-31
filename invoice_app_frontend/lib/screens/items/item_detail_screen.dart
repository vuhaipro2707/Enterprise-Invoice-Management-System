import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'create_item_screen.dart';
import '../../services/api_service.dart';
import '../../widgets/type_selection_sheet.dart';
import '../../widgets/units_section.dart';

class ItemDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final List<dynamic> types;
  final bool isDeleted;

  const ItemDetailScreen({
    super.key,
    required this.item,
    required this.types,
    this.isDeleted = false,
  });

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
    _nameController = TextEditingController(text: widget.item['itemDefaultName']);
    
    _otherNameFocusNode.addListener(() {
      if (!_otherNameFocusNode.hasFocus) {
        _addOtherName(_otherNameInputController.text);
      }
    });

    // Khởi tạo tên gọi khác kèm ID
    final rawOtherNames = widget.item['itemOtherNames'] as List? ?? [];
    _otherNames = rawOtherNames.map((e) {
      if (e is String) return {'itemOtherNameId': null, 'nameString': e};
      return Map<String, dynamic>.from(e);
    }).toList();

    _selectedTypeId = widget.item['typeId'];
    _types = widget.types;

    // Tìm tên loại từ list types truyền vào
    if (_selectedTypeId != null) {
      final type = _types.firstWhere(
        (t) => t['typeId'] == _selectedTypeId,
        orElse: () => null,
      );
      if (type != null) {
        _selectedTypeName = type['typeName'];
      }
    }
    
    // Khởi tạo các đơn vị từ dữ liệu có sẵn
    final existingUnits = widget.item['units'] as List? ?? [];
    
    // Sắp xếp sao cho đơn vị gốc luôn đứng đầu tiên
    final List<dynamic> sortedUnits = List.from(existingUnits);
    sortedUnits.sort((a, b) {
      final aBase = a['isBaseUnit'] ?? false;
      final bBase = b['isBaseUnit'] ?? false;
      if (aBase && !bBase) return -1;
      if (!aBase && bBase) return 1;
      return 0;
    });

    for (var u in sortedUnits) {
      String formattedPrice = '';
      if (u['unitPriceDefault'] != null) {
        formattedPrice = _formatter.format(u['unitPriceDefault']);
      }
      _units.add({
        'unitId': u['unitId'],
        'nameController': TextEditingController(text: u['unitName']),
        'priceController': TextEditingController(text: formattedPrice),
        'ratioController': TextEditingController(text: (u['ratio'] ?? 1).toString()),
        'isBaseUnit': u['isBaseUnit'] ?? false,
      });
    }
  }



  void _addOtherName(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && !_otherNames.any((e) => e['nameString'] == trimmed)) {
      setState(() {
        _otherNames.add({'itemOtherNameId': null, 'nameString': trimmed});
        _otherNameInputController.clear();
      });
    }
  }

  void _removeOtherName(Map<String, dynamic> otherName) {
    setState(() {
      if (otherName['itemOtherNameId'] != null) {
        _removedOtherNameIds.add(otherName['itemOtherNameId']);
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
              _selectedTypeId = type['typeId'];
              _selectedTypeName = type['typeName'];
            });
          },
          onTypeCreated: (newType) {
            setState(() {
              _types.add(newType);
              _selectedTypeId = newType['typeId'];
              _selectedTypeName = newType['typeName'];
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
      final itemId = widget.item['itemId'];
      
      // 1. Cập nhật thông tin cơ bản mặt hàng
      final Map<String, dynamic> itemUpdate = {};
      if (_nameController.text.trim() != widget.item['itemDefaultName']) {
        itemUpdate['itemDefaultName'] = _nameController.text.trim();
      }
      if (_selectedTypeId != widget.item['typeId']) {
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
        if (on['itemOtherNameId'] == null) {
          await ApiService().addItemOtherName(itemId, on['nameString']);
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
        
        if (unit['unitId'] == null) {
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
          final String unitId = unit['unitId'];
          final originalUnit = originalUnits.firstWhere((u) => u['unitId'] == unitId, orElse: () => null);
          
          if (originalUnit != null) {
            final Map<String, dynamic> unitUpdate = {};
            if (unitName != originalUnit['unitName']) unitUpdate['unitName'] = unitName;
            if (ratio != (originalUnit['ratio'] as int?)) unitUpdate['ratio'] = ratio;
            if (isBaseUnit != (originalUnit['isBaseUnit'] as bool?)) unitUpdate['isBaseUnit'] = isBaseUnit;
            
            // Only update unitPriceDefault for the Base Unit.
            // Secondary units' prices are automatically recalculated and propagated by the DB trigger.
            if (isBaseUnit) {
              if (unitPrice != (originalUnit['unitPriceDefault'] as int?)) {
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

  Future<void> _restoreItem() async {
    setState(() => _isSaving = true);
    try {
      final itemId = widget.item['itemId'];
      await ApiService().restoreItem(itemId);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Khôi phục mặt hàng thành công')),
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

  Future<void> _deleteItem() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: const Text(
            'Bạn có chắc chắn muốn xóa mặt hàng này không? Bạn có thể khôi phục lại từ Thùng rác.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              child: const Text('XÓA'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final itemId = widget.item['itemId'];
      await ApiService().deleteItem(itemId);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xóa mặt hàng thành công')),
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

  void _duplicateItem() {
    final Map<String, dynamic> itemToDuplicate = {
      'itemDefaultName': _nameController.text.trim(),
      'typeId': _selectedTypeId,
      'itemOtherNames': _otherNames.map((on) => on['nameString'] as String).toList(),
      'units': _units.map((u) {
        final ratioStr = _getRatioController(u).text.trim();
        final ratio = int.tryParse(ratioStr) ?? 1;
        final rawPrice = _getPriceController(u).text.replaceAll('.', '').trim();
        final price = int.tryParse(rawPrice);
        return {
          'unitName': _getNameController(u).text.trim(),
          'ratio': ratio,
          'isBaseUnit': u['isBaseUnit'] ?? false,
          'unitPriceDefault': price,
        };
      }).toList(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (builderContext) => CreateItemScreen(
          types: _types,
          duplicateItem: itemToDuplicate,
        ),
      ),
    ).then((didCreate) {
      if (mounted && didCreate == true) {
        Navigator.pop(context, true);
      }
    });
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDeleted ? 'Chi tiết mặt hàng (Đã xóa)' : 'Chi tiết mặt hàng'),
        actions: [
          if (widget.isDeleted)
            IconButton(
              onPressed: _isSaving ? null : _restoreItem,
              icon: const Icon(Icons.restore_rounded),
              tooltip: 'Khôi phục',
            )
          else ...[
            IconButton(
              onPressed: _isSaving ? null : _duplicateItem,
              icon: const Icon(Icons.copy_all_rounded),
              tooltip: 'Tạo bản sao',
            ),
            IconButton(
              onPressed: _isSaving ? null : _deleteItem,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Xóa mặt hàng',
            ),
            IconButton(
              onPressed: _isSaving ? null : _saveChanges,
              icon: const Icon(Icons.check),
              tooltip: 'Lưu thay đổi',
            ),
          ]
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
              enabled: !widget.isDeleted,
              textCapitalization: TextCapitalization.words,
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
              runSpacing: 8.0,
              children: [
                ..._otherNames.map((on) => Chip(
                      label: Text(on['nameString']),
                      onDeleted: widget.isDeleted ? null : () => _removeOtherName(on),
                    )),
                if (!widget.isDeleted)
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _otherNameInputController,
                      focusNode: _otherNameFocusNode,
                      textCapitalization: TextCapitalization.words,
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
            const Divider(height: 32),
            const SizedBox(height: 8),
            InkWell(
              onTap: widget.isDeleted ? null : (_isLoadingTypes ? null : _showTypeSelectionSheet),
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
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurface,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            UnitsSection(
              units: _units,
              removedUnitIds: _removedUnitIds,
              readOnly: widget.isDeleted,
            ),
            const SizedBox(height: 32),
            if (widget.isDeleted)
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _restoreItem,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                ),
                icon: _isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.restore_rounded),
                label: const Text('Khôi phục mặt hàng'),
              )
            else
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
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
