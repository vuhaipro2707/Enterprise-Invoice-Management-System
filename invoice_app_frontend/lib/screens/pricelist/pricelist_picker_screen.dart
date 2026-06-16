import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/pricelist_card.dart';

class PriceListPickerScreen extends StatefulWidget {
  const PriceListPickerScreen({super.key});

  @override
  State<PriceListPickerScreen> createState() => _PriceListPickerScreenState();
}

class _PriceListPickerScreenState extends State<PriceListPickerScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  List<dynamic> _priceLists = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;

  String? _preloadedBuyerId;
  bool _isBuyerFiltered = false;
  bool _isArgumentsParsed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isArgumentsParsed) {
      _isArgumentsParsed = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        _preloadedBuyerId = args;
        _isBuyerFiltered = true;
      }
      _fetchInitialPriceLists();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _fetchMorePriceLists();
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      _fetchInitialPriceLists();
    });
  }

  Future<void> _fetchInitialPriceLists() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _offset = 0;
      _hasMore = true;
      _priceLists = [];
    });

    try {
      final lists = await _apiService.getCustomerPriceLists(
        limit: _limit,
        offset: 0,
        sortBy: 'updated_at',
        sortOrder: 'desc',
        buyerName: _searchController.text.trim(),
        buyerId: _isBuyerFiltered ? _preloadedBuyerId : null,
      );

      if (mounted) {
        setState(() {
          _priceLists = lists;
          _offset = lists.length;
          _hasMore = lists.length == _limit;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải danh sách báo giá: $e')),
        );
      }
    }
  }

  Future<void> _fetchMorePriceLists() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final moreLists = await _apiService.getCustomerPriceLists(
        limit: _limit,
        offset: _offset,
        sortBy: 'updated_at',
        sortOrder: 'desc',
        buyerName: _searchController.text.trim(),
        buyerId: _isBuyerFiltered ? _preloadedBuyerId : null,
      );

      if (mounted) {
        setState(() {
          if (moreLists.isEmpty) {
            _hasMore = false;
          } else {
            _priceLists.addAll(moreLists);
            _offset += moreLists.length;
            _hasMore = moreLists.length == _limit;
          }
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải thêm danh sách báo giá: $e')),
        );
      }
    }
  }

  void _clearBuyerFilter() {
    setState(() {
      _isBuyerFiltered = false;
    });
    _fetchInitialPriceLists();
  }

  void _handlePriceListTap(Map<String, dynamic> pl) async {
    final pricelistId = pl['customerPriceListId'].toString();
    if (!mounted) return;

    final selectedItems = await Navigator.pushNamed(
      context,
      '/pricelist_item_picker',
      arguments: pricelistId,
    );

    if (selectedItems != null && mounted) {
      Navigator.pop(context, selectedItems);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 920;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tìm kiếm bảng báo giá'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc mọi thông tin khác...',
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
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              onChanged: (val) {
                setState(() {});
                _onSearchChanged(val);
              },
            ),
          ),
          if (_isBuyerFiltered && _preloadedBuyerId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  InputChip(
                    avatar: Icon(Icons.person, size: 16, color: colorScheme.onPrimaryContainer),
                    label: const Text('Lọc theo khách hàng hiện tại'),
                    selected: true,
                    selectedColor: colorScheme.primaryContainer,
                    onDeleted: _clearBuyerFilter,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _priceLists.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.request_quote_outlined, size: 64, color: colorScheme.outline),
                            const SizedBox(height: 16),
                            const Text(
                              'Không tìm thấy bảng báo giá nào',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchInitialPriceLists,
                        child: isDesktop
                            ? GridView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16.0),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  mainAxisExtent: 180,
                                ),
                                itemCount: _priceLists.length + (_isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _priceLists.length) {
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                  final pl = _priceLists[index];
                                  return PriceListCard(
                                    priceList: pl,
                                    onTap: () => _handlePriceListTap(pl),
                                  );
                                },
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                itemCount: _priceLists.length + (_isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _priceLists.length) {
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                  final pl = _priceLists[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12.0),
                                    child: SizedBox(
                                      height: 180,
                                      child: PriceListCard(
                                        priceList: pl,
                                        onTap: () => _handlePriceListTap(pl),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
