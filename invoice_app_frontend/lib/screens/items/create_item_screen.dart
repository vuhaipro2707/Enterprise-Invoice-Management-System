import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/type_selection_sheet.dart';
import '../../widgets/units_section.dart';

class CreateItemScreen extends StatefulWidget {
  final List<dynamic> types;
  final Map<String, dynamic>? duplicateItem;

  const CreateItemScreen({
    super.key,
    required this.types,
    this.duplicateItem,
  });

  @override
  State<CreateItemScreen> createState() => _CreateItemScreenState();
}

class _CreateItemScreenState extends State<CreateItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _otherNameInputController = TextEditingController();
  final List<String> _otherNames = [];
  final List<Map<String, dynamic>> _units = [];
  
  String? _selectedTypeId;
  String? _selectedTypeName;
  late List<dynamic> _types;
  final bool _isLoadingTypes = false;
  bool _isSaving = false;
  final _otherNameFocusNode = FocusNode();
  bool _didSave = false;

  @override
  void initState() {
    super.initState();
    _types = widget.types;
    
    _otherNameFocusNode.addListener(() {
      if (!_otherNameFocusNode.hasFocus) {
        _addOtherName(_otherNameInputController.text);
      }
    });

    if (widget.duplicateItem != null) {
      final item = widget.duplicateItem!;
      _nameController.text = item['itemDefaultName'] ?? '';
      
      final rawOtherNames = item['itemOtherNames'] as List? ?? [];
      for (var e in rawOtherNames) {
        if (e is String) {
          _otherNames.add(e);
        } else if (e is Map && e['nameString'] != null) {
          _otherNames.add(e['nameString'].toString());
        }
      }

      _selectedTypeId = item['typeId'];
      if (_selectedTypeId != null) {
        final type = _types.firstWhere(
          (t) => t['typeId'] == _selectedTypeId,
          orElse: () => null,
        );
        if (type != null) {
          _selectedTypeName = type['typeName'];
        }
      }

      final existingUnits = item['units'] as List? ?? [];
      final List<dynamic> sortedUnits = List.from(existingUnits);
      sortedUnits.sort((a, b) {
        final aBase = a['isBaseUnit'] ?? false;
        final bBase = b['isBaseUnit'] ?? false;
        if (aBase && !bBase) return -1;
        if (!aBase && bBase) return 1;
        return 0;
      });

      final formatter = NumberFormat.decimalPattern('vi_VN');
      for (var u in sortedUnits) {
        String formattedPrice = '';
        if (u['unitPriceDefault'] != null) {
          formattedPrice = formatter.format(u['unitPriceDefault']);
        }
        _units.add({
          'unitId': null,
          'nameController': TextEditingController(text: u['unitName']),
          'priceController': TextEditingController(text: formattedPrice),
          'ratioController': TextEditingController(text: (u['ratio'] ?? 1).toString()),
          'isBaseUnit': u['isBaseUnit'] ?? false,
        });
      }
    }
  }



  void _addOtherName(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && !_otherNames.contains(trimmed)) {
      setState(() {
        _otherNames.add(trimmed);
        _otherNameInputController.clear();
      });
    }
  }

  void _removeOtherName(String name) {
    setState(() {
      _otherNames.remove(name);
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

  bool _hasUnsavedChanges() {
    if (widget.duplicateItem == null) {
      if (_nameController.text.trim().isNotEmpty) return true;
      if (_otherNames.isNotEmpty) return true;
      if (_selectedTypeId != null) return true;
      if (_units.isNotEmpty) return true;
      return false;
    }

    final item = widget.duplicateItem!;
    if (_nameController.text.trim() != (item['itemDefaultName'] ?? '')) return true;
    if (_selectedTypeId != item['typeId']) return true;

    final rawOtherNames = item['itemOtherNames'] as List? ?? [];
    final List<String> origOtherNames = [];
    for (var e in rawOtherNames) {
      if (e is String) {
        origOtherNames.add(e);
      } else if (e is Map && e['nameString'] != null) {
        origOtherNames.add(e['nameString'].toString());
      }
    }
    if (_otherNames.length != origOtherNames.length) return true;
    for (int i = 0; i < _otherNames.length; i++) {
      if (_otherNames[i] != origOtherNames[i]) return true;
    }

    final existingUnits = item['units'] as List? ?? [];
    if (_units.length != existingUnits.length) return true;
    for (int i = 0; i < _units.length; i++) {
      final u = _units[i];
      final origU = existingUnits[i];
      final unitName = (u['nameController'] as TextEditingController).text.trim();
      final priceStr = (u['priceController'] as TextEditingController).text.replaceAll('.', '').trim();
      final price = int.tryParse(priceStr) ?? 0;
      final ratioStr = (u['ratioController'] as TextEditingController).text.trim();
      final ratio = int.tryParse(ratioStr) ?? 1;
      final isBaseUnit = u['isBaseUnit'] ?? false;

      if (unitName != (origU['unitName'] ?? '')) return true;
      if (ratio != (origU['ratio'] as int? ?? 1)) return true;
      if (isBaseUnit != (origU['isBaseUnit'] as bool? ?? false)) return true;
      if (isBaseUnit) {
        if (price != (origU['unitPriceDefault'] as int? ?? 0)) return true;
      }
    }

    return false;
  }

  Future<bool> _saveItemWithResult() async {
    _addOtherName(_otherNameInputController.text);
    if (!_formKey.currentState!.validate()) return false;

    setState(() => _isSaving = true);

    try {
      // 1. Create Item
      final result = await ApiService().createItem(
        _nameController.text.trim(),
        _otherNames,
        _selectedTypeId,
      );

      final itemId = result['data']['itemId'];

      // Sort units so that base unit is created first
      final List<Map<String, dynamic>> sortedUnits = List.from(_units);
      sortedUnits.sort((a, b) {
        final aBase = a['isBaseUnit'] ?? false;
        final bBase = b['isBaseUnit'] ?? false;
        if (aBase && !bBase) {
          return -1;
        }
        if (!aBase && bBase) {
          return 1;
        }
        return 0;
      });

      // 2. Create Units sequentially
      for (var unit in sortedUnits) {
        final controller = unit['nameController'] as TextEditingController?;
        if (controller == null) continue;
        String unitName = controller.text.trim();
        if (unitName.isNotEmpty) {
          unitName = unitName[0].toUpperCase() + unitName.substring(1);
        }
        
        final priceController = unit['priceController'] as TextEditingController?;
        final rawPrice = priceController?.text.replaceAll('.', '').trim() ?? '';
        final unitPrice = int.tryParse(rawPrice);

        final ratioStr = (unit['ratioController'] as TextEditingController?)?.text.trim() ?? '1';
        final ratio = int.tryParse(ratioStr) ?? 1;
        final isBaseUnit = unit['isBaseUnit'] ?? false;

        if (unitName.isNotEmpty) {
          await ApiService().createUnit(
            itemId,
            unitName,
            unitPrice,
            ratio: ratio,
            isBaseUnit: isBaseUnit,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo mặt hàng thành công')),
        );
      }
      _didSave = true;
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tạo mặt hàng: $e')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveItem() async {
    final success = await _saveItemWithResult();
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
            'Bạn chưa lưu thông tin mặt hàng mới này. Bạn có chắc chắn muốn thoát không?',
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
      final success = await _saveItemWithResult();
      if (success) {
        return true;
      }
    }
    return false;
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (_hasUnsavedChanges()) {
          final shouldPop = await _showBackConfirmationDialog();
          if (shouldPop && mounted) {
            navigator.pop(_didSave);
          }
        } else {
          navigator.pop(_didSave);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tạo mặt hàng mới'),
          actions: [
            if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _saveItem,
              icon: const Icon(Icons.check),
              tooltip: 'Lưu',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Thông tin cơ bản
            const Text(
              'Thông tin cơ bản',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
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
              children: [
                ..._otherNames.map((name) => Chip(
                      label: Text(name),
                      onDeleted: () => _removeOtherName(name),
                    )),
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
            
            UnitsSection(units: _units),
            
            const SizedBox(height: 100), // Khoảng trống cho FAB nếu cần
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveItem,
        label: _isSaving
            ? const Text('Đang lưu...')
            : const Text('Lưu mặt hàng'),
        icon: const Icon(Icons.save),
      ),
      ),
    );
  }
}
