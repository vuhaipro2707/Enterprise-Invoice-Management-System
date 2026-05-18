import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/type_selection_sheet.dart';
import '../../widgets/item_card.dart';

class LineItemSearchScreen extends StatefulWidget {
  const LineItemSearchScreen({super.key});

  @override
  State<LineItemSearchScreen> createState() => _LineItemSearchScreenState();
}

class _LineItemSearchScreenState extends State<LineItemSearchScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
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
      _offset = 0;
      _hasMore = true;
      _fetchItems();
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final types = await _apiService.getTypes();
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
    setState(() => _isLoading = true);
    try {
      List<dynamic> items;
      if (_searchController.text.isNotEmpty) {
        items = await _apiService.searchItems(
          _searchController.text,
          typeId: _selectedTypeId,
        );
        _hasMore = false;
      } else {
        items = await _apiService.getItems(
          typeId: _selectedTypeId,
          limit: _limit,
          offset: 0,
        );
        _offset = items.length;
        _hasMore = items.length == _limit;
      }
      setState(() {
        _items = items;
      });
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
    setState(() => _isLoadingMore = true);
    try {
      final moreItems = await _apiService.getItems(
        typeId: _selectedTypeId,
        limit: _limit,
        offset: _offset,
      );
      
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
      builder: (context) {
        return TypeSelectionSheet(
          initialTypes: _types,
          onTypeSelected: (type) {
            setState(() {
              _selectedTypeId = type['type_id'];
            });
            _fetchItems();
          },
          onTypeCreated: (newType) {
            setState(() {
              _types.add(newType);
              _selectedTypeId = newType['type_id'];
            });
            _fetchItems();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn mặt hàng'),
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
                      label: Text(type['type_name']),
                      selected: _selectedTypeId == type['type_id'],
                      onSelected: (selected) {
                        setState(() {
                          _selectedTypeId = selected ? type['type_id'] : null;
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
                ? const Center(child: Text('Không tìm thấy mặt hàng nào'))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _items.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return ItemCard(
                        item: _items[index],
                        types: _types,
                        onTap: () {
                          Navigator.pop(context, _items[index]);
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
    _debounce?.cancel();
    super.dispose();
  }
}
