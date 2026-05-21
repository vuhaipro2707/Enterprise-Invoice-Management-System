import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/type_selection_sheet.dart';
import '../../widgets/units_section.dart';

class CreateItemScreen extends StatefulWidget {
  final List<dynamic> types;
  const CreateItemScreen({super.key, required this.types});

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

  @override
  void initState() {
    super.initState();
    _types = widget.types;
    
    _otherNameFocusNode.addListener(() {
      if (!_otherNameFocusNode.hasFocus) {
        _addOtherName(_otherNameInputController.text);
      }
    });
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

  Future<void> _saveItem() async {
    _addOtherName(_otherNameInputController.text);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // 1. Create Item
      final result = await ApiService().createItem(
        _nameController.text.trim(),
        _otherNames,
        _selectedTypeId,
      );

      final itemId = result['data']['item_id'];

      // Sort units so that base unit is created first
      final List<Map<String, dynamic>> sortedUnits = List.from(_units);
      sortedUnits.sort((a, b) {
        final aBase = a['isBaseUnit'] ?? false;
        final bBase = b['isBaseUnit'] ?? false;
        if (aBase && !bBase) return -1;
        if (!aBase && bBase) return 1;
        return 0;
      });

      // 2. Create Units sequentially
      for (var unit in sortedUnits) {
        final controller = unit['nameController'] as TextEditingController?;
        if (controller == null) continue;
        String unitName = controller.text.trim();
        // Viết hoa chữ cái đầu tiên của đơn vị
        if (unitName.isNotEmpty) {
          unitName = unitName[0].toUpperCase() + unitName.substring(1);
        }
        
        // Remove dots for parsing
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
        Navigator.pop(context, true); // Return true to trigger refresh
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo mặt hàng thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tạo mặt hàng: $e')),
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
    );
  }
}
