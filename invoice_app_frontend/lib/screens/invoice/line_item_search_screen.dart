import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/type_selection_sheet.dart';
import '../../widgets/item_card.dart';
import '../items/create_item_screen.dart';
import '../items/ai_create_item_screen.dart';
import '../items/item_detail_screen.dart';

class LineItemSearchScreen extends StatefulWidget {
  const LineItemSearchScreen({super.key});

  @override
  State<LineItemSearchScreen> createState() => _LineItemSearchScreenState();
}

class _LineItemSearchScreenState extends State<LineItemSearchScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  
  List<dynamic> _items = [];
  List<dynamic> _types = [];
  String? _selectedTypeId;
  bool _isLoading = false;

  // Pagination states
  int _offset = 0;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore && _searchController.text.isEmpty) {
        _fetchMoreItems();
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _offset = 0;
      _hasMore = true;
      _fetchItems();
    });
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final types = await _apiService.getTypes();
      if (!mounted) return;
      setState(() {
        _types = types;
      });
      _offset = 0;
      _hasMore = true;
      await _fetchItems();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchItems() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      List<dynamic> items;
      if (_searchController.text.isNotEmpty) {
        items = await _apiService.searchItems(
          _searchController.text,
          typeId: _selectedTypeId,
        );
        if (!mounted) return;
        _hasMore = false;
      } else {
        items = await _apiService.getItems(
          typeId: _selectedTypeId,
          limit: _limit,
          offset: 0,
        );
        if (!mounted) return;
        _offset = items.length;
        _hasMore = items.length == _limit;
      }
      if (mounted) {
        setState(() {
          _items = items;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải mặt hàng: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMoreItems() async {
    if (!mounted) return;
    setState(() => _isLoadingMore = true);
    try {
      final moreItems = await _apiService.getItems(
        typeId: _selectedTypeId,
        limit: _limit,
        offset: _offset,
      );
      
      if (!mounted) return;
      setState(() {
        if (moreItems.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(moreItems);
          _offset += moreItems.length;
          _hasMore = moreItems.length == _limit;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải thêm: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _showTypeSearchSheet() {
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
            if (mounted) {
              setState(() {
                _selectedTypeId = type['typeId'];
              });
              _fetchItems();
            }
          },
          onTypeCreated: (newType) {
            if (mounted) {
              setState(() {
                _types.add(newType);
                _selectedTypeId = newType['typeId'];
              });
              _fetchItems();
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 920;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn mặt hàng'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadInitialData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới dữ liệu',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (sheetContext) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(sheetContext).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Thêm mặt hàng mới',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(sheetContext).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(sheetContext).colorScheme.primaryContainer,
                        child: Icon(
                          Icons.edit_note_rounded,
                          color: Theme.of(sheetContext).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        'Tạo thủ công',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(sheetContext).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: const Text('Tự nhập tay từng tên hàng, quy cách và đơn vị tính'),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        _searchFocusNode.unfocus();
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (builderContext) => CreateItemScreen(types: _types),
                          ),
                        );
                        if (context.mounted) {
                          _searchFocusNode.unfocus();
                        }
                        if (result == true && mounted) {
                          setState(() {
                            _searchController.clear();
                          });
                          _loadInitialData();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(sheetContext).colorScheme.secondaryContainer,
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: Theme.of(sheetContext).colorScheme.onSecondaryContainer,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            'Tạo nhanh bằng AI',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(sheetContext).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(sheetContext).colorScheme.primary,
                                  Theme.of(sheetContext).colorScheme.secondary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: const Text('Bóc tách biến thể, gợi ý giá thị trường và lưu hàng loạt'),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        _searchFocusNode.unfocus();
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (builderContext) => AICreateItemScreen(types: _types),
                          ),
                        );
                        if (context.mounted) {
                          _searchFocusNode.unfocus();
                        }
                        if (result == true && mounted) {
                          setState(() {
                            _searchController.clear();
                          });
                          _loadInitialData();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        tooltip: 'Thêm mặt hàng mới',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm mặt hàng...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (val) {
                setState(() {});
                _onSearchChanged(val);
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                IconButton(
                  onPressed: _showTypeSearchSheet,
                  icon: Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
                ),
                FilterChip(
                  label: const Text('Tất cả'),
                  selected: _selectedTypeId == null,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedTypeId = null;
                        _offset = 0;
                        _hasMore = true;
                      });
                      _fetchItems();
                    }
                  },
                ),
                const SizedBox(width: 8),
                ..._types.map((type) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(type['typeName']),
                      selected: _selectedTypeId == type['typeId'],
                      onSelected: (selected) {
                        setState(() {
                          _selectedTypeId = selected ? type['typeId'] : null;
                          _offset = 0;
                          _hasMore = true;
                        });
                        _fetchItems();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Không tìm thấy mặt hàng nào',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          if (_searchController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Bạn có muốn tạo mới sản phẩm "${_searchController.text.trim()}" với AI không?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () async {
                                _searchFocusNode.unfocus();
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (builderContext) => AICreateItemScreen(
                                      types: _types,
                                      initialKeyword: _searchController.text.trim(),
                                    ),
                                  ),
                                );
                                if (context.mounted) {
                                  _searchFocusNode.unfocus();
                                }
                                if (result == true && mounted) {
                                  setState(() {
                                    _searchController.clear();
                                  });
                                  _loadInitialData();
                                }
                              },
                              icon: const Icon(Icons.auto_awesome_rounded),
                              label: const Text('Tạo mới với AI'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                 : isDesktop
                    ? ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16.0),
                        itemCount: (_items.length / 3).ceil() + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (builderContext, rowIndex) {
                          if (_isLoadingMore && rowIndex == (_items.length / 3).ceil()) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final startIndex = rowIndex * 3;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (int i = 0; i < 3; i++) ...[
                                  if (i > 0) const SizedBox(width: 16),
                                  Expanded(
                                    child: (startIndex + i < _items.length)
                                        ? ItemCard(
                                            item: _items[startIndex + i],
                                            types: _types,
                                            showInvoiceButton: false,
                                            showEditButton: true,
                                            onEditPressed: () async {
                                              _searchFocusNode.unfocus();
                                              final result = await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (builderContext) => ItemDetailScreen(
                                                    item: _items[startIndex + i],
                                                    types: _types,
                                                  ),
                                                ),
                                              );
                                              if (context.mounted) {
                                                _searchFocusNode.unfocus();
                                              }
                                              if (result == true && mounted) {
                                                _fetchItems();
                                              }
                                            },
                                            onTap: () {
                                              Navigator.pop(context, _items[startIndex + i]);
                                            },
                                            onUnitTap: (unit) {
                                              final resultItem = Map<String, dynamic>.from(_items[startIndex + i]);
                                              resultItem['selectedUnit'] = unit;
                                              resultItem['selectedUnitId'] = unit['unitId'];
                                              Navigator.pop(context, resultItem);
                                            },
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        controller: _scrollController,
                        itemCount: _items.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (builderContext, index) {
                          if (index == _items.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16.0),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return ItemCard(
                            item: _items[index],
                            types: _types,
                            showInvoiceButton: false,
                            showEditButton: true,
                            onEditPressed: () async {
                              _searchFocusNode.unfocus();
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (builderContext) => ItemDetailScreen(
                                    item: _items[index],
                                    types: _types,
                                  ),
                                ),
                              );
                              if (context.mounted) {
                                _searchFocusNode.unfocus();
                              }
                              if (result == true && mounted) {
                                _fetchItems();
                              }
                            },
                            onTap: () {
                              Navigator.pop(context, _items[index]);
                            },
                            onUnitTap: (unit) {
                              final resultItem = Map<String, dynamic>.from(_items[index]);
                              resultItem['selectedUnit'] = unit;
                              resultItem['selectedUnitId'] = unit['unitId'];
                              Navigator.pop(context, resultItem);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
