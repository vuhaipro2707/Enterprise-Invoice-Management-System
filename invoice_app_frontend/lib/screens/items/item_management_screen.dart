import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/type_selection_sheet.dart';
import '../../widgets/item_card.dart';
import 'create_item_screen.dart';
import 'item_detail_screen.dart';
import 'ai_create_item_screen.dart';

class ItemManagementScreen extends StatefulWidget {
  const ItemManagementScreen({super.key});

  @override
  State<ItemManagementScreen> createState() => _ItemManagementScreenState();
}

enum SortState { none, az, za }

class _ItemManagementScreenState extends State<ItemManagementScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  
  List<dynamic> _items = [];
  List<dynamic> _originalItems = []; // Lưu lại list gốc để reset sort
  List<dynamic> _types = [];
  String? _selectedTypeId;
  SortState _sortState = SortState.none;
  bool _isLoading = false;
  bool _isSearching = false;

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
      if (!_isLoading && !_isLoadingMore && _hasMore && !_isSearching) {
        _fetchMoreItems();
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _offset = 0;
      _hasMore = true;
      // Khi tìm kiếm, reset sort về none vì backend search trả về theo độ liên quan
      if (query.isNotEmpty) {
        _sortState = SortState.none;
      }
      _fetchItems();
    });
  }

  void _toggleSort() {
    if (_isSearching) return; // Không cho phép sort khi đang tìm kiếm

    setState(() {
      switch (_sortState) {
        case SortState.none:
          _sortState = SortState.az;
          break;
        case SortState.az:
          _sortState = SortState.za;
          break;
        case SortState.za:
          _sortState = SortState.none;
          break;
      }
      _offset = 0;
      _hasMore = true;
      _fetchItems(); // Luôn fetch lại từ Backend khi đổi sort
    });
  }

  Future<void> _loadInitialData({bool isQuiet = false}) async {
    if (!isQuiet) {
      setState(() => _isLoading = true);
    }
    try {
      final types = await _apiService.getTypes();
      setState(() {
        _types = types;
      });
      if (!isQuiet) {
        _offset = 0;
        _hasMore = true;
      }
      await _fetchItems(isQuiet: isQuiet);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      if (mounted && !isQuiet) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchItems({bool isQuiet = false}) async {
    if (!isQuiet) {
      setState(() => _isLoading = true);
    }
    try {
      List<dynamic> items;
      if (_searchController.text.isNotEmpty) {
        items = await _apiService.searchItems(
          _searchController.text,
          typeId: _selectedTypeId,
        );
        _isSearching = true;
        _hasMore = false;
      } else {
        String? sortBy;
        String? sortOrder;
        
        if (_sortState == SortState.az) {
          sortBy = 'item_default_name';
          sortOrder = 'asc';
        } else if (_sortState == SortState.za) {
          sortBy = 'item_default_name';
          sortOrder = 'desc';
        }

        items = await _apiService.getItems(
          typeId: _selectedTypeId,
          limit: isQuiet ? (_offset > 0 ? _offset : _limit) : _limit,
          offset: 0,
          sortBy: sortBy,
          sortOrder: sortOrder,
        );
        _isSearching = false;
        if (!isQuiet) {
          _offset = items.length;
          _hasMore = items.length == _limit;
        } else {
          _offset = items.length;
        }
      }
      setState(() {
        _items = items;
        _originalItems = List.from(items);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching items: $e')),
        );
      }
    } finally {
      if (mounted && !isQuiet) setState(() => _isLoading = false);
    }
  }

  void _showCreateTypeDialog() {
    final TextEditingController typeController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thêm loại hàng mới'),
        content: TextField(
          controller: typeController,
          decoration: const InputDecoration(hintText: 'Tên loại hàng'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (typeController.text.isNotEmpty) {
                try {
                  await _apiService.createType(typeController.text);
                  if (!mounted || !dialogContext.mounted) return;
                  
                  Navigator.pop(dialogContext);
                  _loadInitialData(); // Load lại list types
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lỗi: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
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
            setState(() {
              _selectedTypeId = type['typeId'];
            });
            _fetchItems();
          },
          onTypeCreated: (newType) {
            setState(() {
              _types.add(newType);
              _selectedTypeId = newType['typeId'];
            });
            _fetchItems();
          },
        );
      },
    );
  }

  Future<void> _fetchMoreItems() async {
    setState(() => _isLoadingMore = true);
    try {
      String? sortBy;
      String? sortOrder;
      
      if (_sortState == SortState.az) {
        sortBy = 'item_default_name';
        sortOrder = 'asc';
      } else if (_sortState == SortState.za) {
        sortBy = 'item_default_name';
        sortOrder = 'desc';
      }

      final moreItems = await _apiService.getItems(
        typeId: _selectedTypeId,
        limit: _limit,
        offset: _offset,
        sortBy: sortBy,
        sortOrder: sortOrder,
      );
      
      setState(() {
        if (moreItems.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(moreItems);
          _originalItems.addAll(moreItems);
          _offset += moreItems.length;
          _hasMore = moreItems.length == _limit;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching more items: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 920;
    String sortIconLabel = 'Sắp xếp';
    IconData sortIcon = Icons.sort;
    if (_sortState == SortState.az) {
      sortIcon = Icons.sort_by_alpha;
      sortIconLabel = 'A-Z';
    } else if (_sortState == SortState.za) {
      sortIcon = Icons.sort_by_alpha;
      sortIconLabel = 'Z-A';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý mặt hàng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () {
              Navigator.pushNamed(context, '/item_trash').then((_) {
                _loadInitialData(isQuiet: true);
              });
            },
            tooltip: 'Thùng rác',
          ),
          IconButton(
            onPressed: _isLoading ? null : () => _loadInitialData(isQuiet: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới dữ liệu',
          ),
          TextButton.icon(
            onPressed: _isSearching ? null : _toggleSort, // Disable khi đang tìm kiếm
            icon: Icon(
              sortIcon, 
              size: 20, 
              color: _isSearching 
                  ? Theme.of(context).colorScheme.outline 
                  : Theme.of(context).colorScheme.onSurface,
            ),
            label: Text(
              sortIconLabel,
              style: TextStyle(
                color: _isSearching 
                    ? Theme.of(context).colorScheme.outline 
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
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
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (builderContext) => CreateItemScreen(types: _types),
                          ),
                        );
                        if (result == true && mounted) {
                          _fetchItems(isQuiet: true);
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
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (builderContext) => AICreateItemScreen(types: _types),
                          ),
                        );
                        if (result == true && mounted) {
                          _loadInitialData(isQuiet: true);
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
              decoration: InputDecoration(
                hintText: 'Tìm kiếm mặt hàng...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                IconButton(
                  onPressed: _showCreateTypeDialog,
                  icon: Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
                  tooltip: 'Thêm loại hàng',
                ),
                IconButton(
                  onPressed: _showTypeSearchSheet,
                  icon: Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
                  tooltip: 'Tìm kiếm loại hàng',
                ),
                const SizedBox(width: 4),
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
                  final typeId = type['typeId'];
                  final typeName = type['typeName'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(typeName),
                      selected: _selectedTypeId == typeId,
                      onSelected: (selected) {
                        setState(() {
                          _selectedTypeId = selected ? typeId : null;
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
          const SizedBox(height: 12), // Khoảng cách giữa bộ lọc và danh sách
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                ? const Center(child: Text('Không tìm thấy mặt hàng nào'))
                : RefreshIndicator(
                    onRefresh: () => _fetchItems(isQuiet: true),
                    child: isDesktop
                        ? ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16.0),
                            itemCount: (_items.length / 3).ceil() + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, rowIndex) {
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
                                                onTap: () async {
                                                  final result = await Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (builderContext) => ItemDetailScreen(
                                                        item: _items[startIndex + i],
                                                        types: _types,
                                                      ),
                                                    ),
                                                  );
                                                  if (result == true) {
                                                    _fetchItems(isQuiet: true);
                                                  }
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
                            controller: _scrollController,
                            itemCount: _items.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _items.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              return ItemCard(
                                item: _items[index],
                                types: _types,
                                onTap: () async {
                                   final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (builderContext) => ItemDetailScreen(
                                        item: _items[index],
                                        types: _types,
                                      ),
                                    ),
                                  );
                                  if (result == true) {
                                    _fetchItems(isQuiet: true);
                                  }
                                },
                              );
                            },
                          ),
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
    _debounce?.cancel();
    super.dispose();
  }
}
