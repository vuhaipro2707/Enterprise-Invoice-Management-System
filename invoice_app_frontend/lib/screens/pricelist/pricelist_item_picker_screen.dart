import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/string_utils.dart';

class PriceListItemPickerScreen extends StatefulWidget {
  const PriceListItemPickerScreen({super.key});

  @override
  State<PriceListItemPickerScreen> createState() => _PriceListItemPickerScreenState();
}

class _PriceListItemPickerScreenState extends State<PriceListItemPickerScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  String? _pricelistId;
  Map<String, dynamic>? _priceListData;
  List<dynamic> _priceItems = [];
  bool _isLoading = true;
  bool _isInitialized = false;

  // Set of selected item indexes
  final Set<int> _selectedIndexes = {};

  // Controllers to track quantity for selected items
  final Map<int, TextEditingController> _quantityControllers = {};

  @override
  void dispose() {
    _searchController.dispose();
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        _pricelistId = args;
        _fetchPriceListDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy ID bảng báo giá')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _fetchPriceListDetails() async {
    if (_pricelistId == null) return;
    setState(() => _isLoading = true);

    try {
      final data = await _apiService.getCustomerPriceList(_pricelistId!);
      final List<dynamic> items = data['itemPrices'] as List? ?? [];
      
      if (mounted) {
        setState(() {
          _priceListData = data;
          _priceItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải chi tiết bảng báo giá: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  void _toggleItem(int index) {
    setState(() {
      if (_selectedIndexes.contains(index)) {
        _selectedIndexes.remove(index);
        _quantityControllers[index]?.dispose();
        _quantityControllers.remove(index);
      } else {
        _selectedIndexes.add(index);
        _quantityControllers[index] = TextEditingController(text: '1');
      }
    });
  }

  void _selectAllFiltered(List<int> filteredIndices) {
    setState(() {
      final allFilteredSelected = filteredIndices.every((idx) => _selectedIndexes.contains(idx));
      if (allFilteredSelected) {
        for (final idx in filteredIndices) {
          _selectedIndexes.remove(idx);
          _quantityControllers[idx]?.dispose();
          _quantityControllers.remove(idx);
        }
      } else {
        for (final idx in filteredIndices) {
          _selectedIndexes.add(idx);
          if (!_quantityControllers.containsKey(idx)) {
            _quantityControllers[idx] = TextEditingController(text: '1');
          }
        }
      }
    });
  }

  void _confirmSelection() {
    if (_selectedIndexes.isEmpty) return;

    final List<int> invalidIndexes = [];
    for (var idx in _selectedIndexes) {
      final controller = _quantityControllers[idx];
      if (controller == null) {
        invalidIndexes.add(idx);
        continue;
      }
      final text = controller.text.trim();
      if (text.isEmpty) {
        invalidIndexes.add(idx);
        continue;
      }
      final val = double.tryParse(text);
      if (val == null || val <= 0) {
        invalidIndexes.add(idx);
      }
    }

    if (invalidIndexes.isNotEmpty) {
      showDialog(
        context: context,
        builder: (dialogContext) {
          final colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Thiếu số lượng'),
              ],
            ),
            content: Text(
              'Có ${invalidIndexes.length} mặt hàng được chọn nhưng chưa điền số lượng hoặc số lượng không hợp lệ.\n\n'
              'Bạn muốn tự điền lại hay tự động bỏ chọn các mặt hàng này để tiếp tục?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  'TỰ ĐIỀN LẠI',
                  style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  setState(() {
                    for (final idx in invalidIndexes) {
                      _selectedIndexes.remove(idx);
                      _quantityControllers[idx]?.dispose();
                      _quantityControllers.remove(idx);
                    }
                  });
                  // After unchecking, if we still have items, proceed with confirmation
                  if (_selectedIndexes.isNotEmpty) {
                    _confirmSelection();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã bỏ chọn tất cả các mặt hàng không hợp lệ')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                ),
                child: const Text('BỎ CHỌN & THÊM'),
              ),
            ],
          );
        },
      );
      return;
    }

    // Proceed with valid list
    final List<Map<String, dynamic>> results = [];
    for (var idx in _selectedIndexes) {
      final itm = _priceItems[idx];
      final qty = double.tryParse(_quantityControllers[idx]?.text.trim() ?? '') ?? 1.0;
      results.add({
        'itemId': itm['itemId'],
        'unitId': itm['unitId'],
        'itemName': itm['itemDefaultName'] ?? 'Sản phẩm không tên',
        'unitName': itm['unitName'] ?? 'Cái',
        'price': (itm['unitPriceCustom'] as num?)?.toInt() ?? 0,
        'quantity': qty.toInt(),
      });
    }

    Navigator.pop(context, results);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chọn mặt hàng')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final String title = _priceListData?['description'] ?? 'Bảng báo giá';
    final String? buyerName = _priceListData?['buyerName'];
    final String? buyerCode = _priceListData?['buyerCode'];

    final String query = _searchController.text.trim();
    final List<MapEntry<int, dynamic>> filteredItems = [];
    for (int i = 0; i < _priceItems.length; i++) {
      final itm = _priceItems[i];
      final String itemName = (itm['itemDefaultName'] ?? '').toString();
      if (query.isEmpty || StringUtils.containsUnaccented(itemName, query)) {
        filteredItems.add(MapEntry(i, itm));
      }
    }

    final filteredIndices = filteredItems.map((e) => e.key).toList();
    final allSelected = filteredIndices.isNotEmpty && filteredIndices.every((idx) => _selectedIndexes.contains(idx));

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Price list header overview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bảng báo giá: $title',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: colorScheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        buyerName != null
                            ? '$buyerName ${buyerCode != null ? "($buyerCode)" : ""}'
                            : 'Báo giá chung (Mọi khách hàng)',
                        style: TextStyle(color: colorScheme.outline, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search Input Field
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm mặt hàng...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              onChanged: (val) {
                setState(() {});
              },
            ),
          ),

          // Control bar for selection
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  query.isEmpty
                      ? 'Danh sách mặt hàng (${_priceItems.length})'
                      : 'Kết quả tìm kiếm (${filteredItems.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                    fontSize: 14,
                  ),
                ),
                if (filteredItems.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _selectAllFiltered(filteredIndices),
                    icon: Icon(
                      allSelected ? Icons.deselect : Icons.select_all,
                      size: 20,
                    ),
                    label: Text(allSelected ? 'Bỏ chọn tất cả' : 'Chọn tất cả'),
                  ),
              ],
            ),
          ),

          Expanded(
            child: filteredItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          _priceItems.isEmpty
                              ? 'Bảng báo giá này chưa có mặt hàng nào'
                              : 'Không tìm thấy mặt hàng phù hợp',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final entry = filteredItems[index];
                      final int originalIndex = entry.key;
                      final itm = entry.value;

                      final isSelected = _selectedIndexes.contains(originalIndex);
                      final String itemName = itm['itemDefaultName'] ?? 'Mặt hàng không tên';
                      final String unitName = itm['unitName'] ?? 'Cái';
                      final int customPrice = (itm['unitPriceCustom'] as num?)?.toInt() ?? 0;

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8.0),
                        color: isSelected
                            ? colorScheme.primaryContainer.withValues(alpha: 0.15)
                            : colorScheme.surfaceContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected
                                ? colorScheme.primary.withValues(alpha: 0.5)
                                : colorScheme.outline.withValues(alpha: 0.1),
                          ),
                        ),
                        child: InkWell(
                          onTap: () => _toggleItem(originalIndex),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (_) => _toggleItem(originalIndex),
                                      activeColor: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            itemName,
                                            style: TextStyle(
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.secondaryContainer,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  unitName,
                                                  style: TextStyle(
                                                    color: colorScheme.onSecondaryContainer,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                                                    .format(customPrice),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: colorScheme.primary,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (isSelected) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    child: Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: colorScheme.outline.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {}, // Prevent unselecting when clicking around input area
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const SizedBox(width: 48), // align with checkbox + spacing
                                            Text(
                                              'Số lượng:',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            IconButton(
                                              onPressed: () {
                                                final controller = _quantityControllers[originalIndex];
                                                if (controller != null) {
                                                  double val = double.tryParse(controller.text) ?? 1.0;
                                                  if (val > 1.0) {
                                                    val--;
                                                    controller.text = val % 1 == 0
                                                        ? val.toInt().toString()
                                                        : val.toString();
                                                  }
                                                }
                                              },
                                              icon: const Icon(Icons.remove_circle_outline),
                                              color: colorScheme.primary,
                                            ),
                                            SizedBox(
                                              width: 60,
                                              child: TextField(
                                                controller: _quantityControllers[originalIndex],
                                                keyboardType: const TextInputType.numberWithOptions(
                                                    decimal: true),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    fontSize: 14, fontWeight: FontWeight.bold),
                                                decoration: InputDecoration(
                                                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                                  isDense: true,
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: BorderSide(
                                                      color: colorScheme.outline.withValues(alpha: 0.5),
                                                    ),
                                                  ),
                                                  enabledBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: BorderSide(
                                                      color: colorScheme.outline.withValues(alpha: 0.3),
                                                    ),
                                                  ),
                                                  focusedBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: BorderSide(
                                                      color: colorScheme.primary,
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () {
                                                final controller = _quantityControllers[originalIndex];
                                                if (controller != null) {
                                                  double val = double.tryParse(controller.text) ?? 1.0;
                                                  val++;
                                                  controller.text = val % 1 == 0
                                                      ? val.toInt().toString()
                                                      : val.toString();
                                                }
                                              },
                                              icon: const Icon(Icons.add_circle_outline),
                                              color: colorScheme.primary,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _selectedIndexes.isEmpty ? null : _confirmSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(
                _selectedIndexes.isEmpty
                    ? 'CHƯA CHỌN MẶT HÀNG'
                    : 'THÊM VÀO HÓA ĐƠN (${_selectedIndexes.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
