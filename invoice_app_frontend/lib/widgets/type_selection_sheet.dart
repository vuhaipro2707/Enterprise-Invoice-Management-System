import 'package:flutter/material.dart';
import '../services/api_service.dart';

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
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _filteredTypes = widget.initialTypes;
  }

  void _filterTypes(String query) {
    setState(() {
      _filteredTypes = widget.initialTypes
          .where((t) => t['type_name']
              .toString()
              .toLowerCase()
              .contains(query.toLowerCase()))
          .toList();
    });
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
                  !_filteredTypes.any((t) => t['type_name'].toString().toLowerCase() == _searchController.text.trim().toLowerCase()))
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
                  itemBuilder: (context, index) {
                    final type = _filteredTypes[index];
                    return ListTile(
                      title: Text(type['type_name']),
                      onTap: () {
                        widget.onTypeSelected(type);
                        Navigator.pop(context);
                      },
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
