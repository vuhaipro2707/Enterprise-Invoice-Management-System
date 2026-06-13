import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/string_utils.dart';

class TypeSelectionSheet extends StatefulWidget {
  final List<dynamic> initialTypes;
  final Function(dynamic) onTypeSelected;
  final Function(dynamic) onTypeCreated;

  const TypeSelectionSheet({
    super.key,
    required this.initialTypes,
    required this.onTypeSelected,
    required this.onTypeCreated,
  });

  @override
  State<TypeSelectionSheet> createState() => _TypeSelectionSheetState();
}

class _TypeSelectionSheetState extends State<TypeSelectionSheet> {
  late List<dynamic> _filteredTypes;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _editNameController = TextEditingController();
  
  bool _isCreating = false;
  String? _editingTypeId;
  bool _isSavingEdit = false;
  String? _deletingTypeId;

  @override
  void initState() {
    super.initState();
    _filteredTypes = widget.initialTypes;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _editNameController.dispose();
    super.dispose();
  }

  void _filterTypes(String query) {
    setState(() {
      _filteredTypes = widget.initialTypes
          .where((t) => StringUtils.containsUnaccented(
                t['typeName'].toString(),
                query,
              ))
          .toList();
    });
  }

  void _startEditing(dynamic type) {
    setState(() {
      _editingTypeId = type['typeId'];
      _editNameController.text = type['typeName'] ?? '';
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingTypeId = null;
      _editNameController.clear();
    });
  }

  Future<void> _saveEditType(dynamic type) async {
    final newName = _editNameController.text.trim();
    if (newName.isEmpty) return;
    if (newName == type['typeName']) {
      _cancelEditing();
      return;
    }

    setState(() => _isSavingEdit = true);
    try {
      await ApiService().updateType(type['typeId'], newName);
      
      setState(() {
        type['typeName'] = newName;
        final index = widget.initialTypes.indexWhere((t) => t['typeId'] == type['typeId']);
        if (index != -1) {
          widget.initialTypes[index]['typeName'] = newName;
        }
        _editingTypeId = null;
        _editNameController.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chỉnh sửa: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingEdit = false);
      }
    }
  }

  Future<void> _deleteType(dynamic type) async {
    setState(() => _deletingTypeId = type['typeId']);
    
    try {
      // 1. Kiểm tra sản phẩm phụ thuộc
      final dependentItems = await ApiService().getItems(typeId: type['typeId']);
      
      if (!mounted) return;
      setState(() => _deletingTypeId = null);

      final hasDependencies = dependentItems.isNotEmpty;
      final confirmMessage = hasDependencies
          ? 'Loại hàng "${type['typeName']}" đang có ${dependentItems.length} sản phẩm phụ thuộc. Nếu xóa, các sản phẩm này sẽ bị bỏ phân loại. Bạn vẫn muốn tiếp tục xóa chứ?'
          : 'Bạn có chắc chắn muốn xóa loại hàng "${type['typeName']}"? Hành động này không thể hoàn tác.';

      // 2. Xác nhận xóa
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: Text(confirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Xóa'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // 3. Thực hiện xóa cứng
      setState(() => _deletingTypeId = type['typeId']);
      await ApiService().deleteType(type['typeId']);

      setState(() {
        widget.initialTypes.removeWhere((t) => t['typeId'] == type['typeId']);
        _filteredTypes.removeWhere((t) => t['typeId'] == type['typeId']);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa loại hàng thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xóa loại hàng: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deletingTypeId = null);
      }
    }
  }

  Future<void> _createNewType() async {
    final name = _searchController.text.trim();
    if (name.isEmpty) return;

    // Hiển thị popup xác nhận trước khi tạo
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận tạo mới'),
        content: Text('Bạn có chắc chắn muốn tạo loại hàng mới: "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Tạo mới'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isCreating = true);
    try {
      final result = await ApiService().createType(name);
      final newType = result['data'];
      widget.onTypeCreated(newType);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (sheetContext, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              TextField(
                controller: _searchController,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm hoặc tên loại mới...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _filterTypes('');
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _filterTypes,
              ),
              const SizedBox(height: 16),
              if (_searchController.text.isNotEmpty && 
                  !_filteredTypes.any((t) => t['typeName'].toString().toLowerCase() == _searchController.text.trim().toLowerCase()))
                ListTile(
                  leading: Icon(Icons.add_circle_outline, color: colorScheme.primary),
                  title: Text('Tạo mới loại: "${_searchController.text}"'),
                  onTap: _isCreating ? null : _createNewType,
                  trailing: _isCreating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _filteredTypes.length,
                  itemBuilder: (itemBuilderContext, index) {
                    final type = _filteredTypes[index];
                    final isEditing = type['typeId'] == _editingTypeId;

                    if (isEditing) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _editNameController,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  hintText: 'Nhập tên loại hàng mới...',
                                  isDense: true,
                                  border: UnderlineInputBorder(),
                                ),
                                onSubmitted: (_) => _isSavingEdit ? null : _saveEditType(type),
                              ),
                            ),
                            if (_isSavingEdit)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            else ...[
                              IconButton(
                                icon: Icon(Icons.check, color: colorScheme.primary),
                                onPressed: () => _saveEditType(type),
                                tooltip: 'Lưu',
                              ),
                              IconButton(
                                icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
                                onPressed: _cancelEditing,
                                tooltip: 'Hủy',
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    return ListTile(
                      title: Text(type['typeName'] ?? ''),
                      onTap: () {
                        widget.onTypeSelected(type);
                        Navigator.pop(itemBuilderContext);
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, size: 20, color: colorScheme.onSurfaceVariant),
                            onPressed: _deletingTypeId != null ? null : () => _startEditing(type),
                            tooltip: 'Sửa',
                          ),
                          if (_deletingTypeId == type['typeId'])
                            const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          else
                            IconButton(
                              icon: Icon(Icons.delete, size: 20, color: colorScheme.error),
                              onPressed: _deletingTypeId != null ? null : () => _deleteType(type),
                              tooltip: 'Xóa',
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
