import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'item_detail_screen.dart';

class ItemTrashScreen extends StatefulWidget {
  const ItemTrashScreen({super.key});

  @override
  State<ItemTrashScreen> createState() => _ItemTrashScreenState();
}

class _ItemTrashScreenState extends State<ItemTrashScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _deletedItems = [];
  List<dynamic> _types = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDeletedItems();
  }

  Future<void> _fetchDeletedItems() async {
    setState(() => _isLoading = true);
    try {
      final items = await _apiService.getDeletedItems();
      final types = await _apiService.getTypes();
      if (mounted) {
        setState(() {
          _deletedItems = items;
          _types = types;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tải danh sách đã xóa: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 920;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thùng rác mặt hàng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDeletedItems,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _deletedItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 64,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Thùng rác trống',
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.outline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : isDesktop
                  ? GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.2,
                      ),
                      itemCount: _deletedItems.length,
                      itemBuilder: (context, index) {
                        return _buildItemCard(_deletedItems[index]);
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _deletedItems.length,
                      itemBuilder: (context, index) {
                        return _buildItemCard(_deletedItems[index]);
                      },
                    ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final colorScheme = Theme.of(context).colorScheme;
    final otherNames = item['itemOtherNames'] as List? ?? [];
    final otherNamesList = otherNames.map((e) {
      if (e is Map) {
        return (e['nameString'] ?? e['nameString'] ?? '').toString();
      }
      return e.toString();
    }).where((s) => s.isNotEmpty).toList();
    final units = item['units'] as List? ?? [];
    final baseUnit = units.firstWhere((u) => u['isBaseUnit'] == true, orElse: () => null);
    final String unitInfo = baseUnit != null ? baseUnit['unitName'] ?? '' : '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (builderContext) => ItemDetailScreen(
                item: item,
                types: _types,
                isDeleted: true,
              ),
            ),
          );
          if (result == true) {
            _fetchDeletedItems();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item['itemDefaultName'] ?? 'Mặt hàng không tên',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unitInfo.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        unitInfo,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
              if (otherNamesList.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Tên khác: ${otherNamesList.join(', ')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (MediaQuery.of(context).size.width > 920) const Spacer() else const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.restore_from_trash_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Xem chi tiết để khôi phục',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
