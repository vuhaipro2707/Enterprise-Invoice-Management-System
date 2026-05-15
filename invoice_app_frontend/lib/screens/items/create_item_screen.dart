import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';
import '../../widgets/type_selection_sheet.dart';

class CreateItemScreen extends StatefulWidget {
  const CreateItemScreen({super.key});

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
  List<dynamic> _types = [];
  bool _isLoadingTypes = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchTypes();
  }

  Future<void> _fetchTypes() async {
    try {
      final types = await ApiService().getTypes();
      if (mounted) {
        setState(() {
          _types = types;
          _isLoadingTypes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingTypes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể tải loại hàng: $e')),
        );
      }
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
      _units[index]['nameController'].dispose();
      _units[index]['priceController'].dispose();
      _units.removeAt(index);
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

  Future<void> _saveItem() async {
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

      // 2. Create Units sequentially
      for (var unit in _units) {
        String unitName = unit['nameController'].text.trim();
        // Viết hoa chữ cái đầu tiên của đơn vị
        if (unitName.isNotEmpty) {
          unitName = unitName[0].toUpperCase() + unitName.substring(1);
        }
        
        // Remove dots for parsing
        final rawPrice = unit['priceController'].text.replaceAll('.', '').trim();
        final unitPrice = int.tryParse(rawPrice);
        if (unitName.isNotEmpty) {
          await ApiService().createUnit(itemId, unitName, unitPrice);
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
                hintText: 'VD: Bia Tiger',
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
                              ? Colors.grey.shade600
                              : Colors.black,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            
            // Phần Đơn vị tính & Giá
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
            if (_units.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Bấm "Thêm đơn vị" để thêm giá bán (VD: Thùng, Lon, Cái)',
                  style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                ),
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
                          decoration: const InputDecoration(
                            labelText: 'Đơn vị',
                            hintText: 'Thùng',
                          ),
                          validator: (value) => (value == null || value.isEmpty)
                              ? 'Nhập tên đơn vị'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: unit['priceController'],
                          decoration: const InputDecoration(
                            labelText: 'Giá mặc định',
                            hintText: '300.000',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [CurrencyInputFormatter()],
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
        backgroundColor: Colors.blue,
      ),
    );
  }
}
