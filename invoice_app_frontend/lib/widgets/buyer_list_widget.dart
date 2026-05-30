import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/buyer_card.dart';
import '../screens/buyer/buyer_detail_screen.dart';
import '../screens/buyer/create_buyer_screen.dart';

class BuyerListWidget extends StatefulWidget {
  final Function(Map<String, dynamic> buyer)? onBuyerSelected;
  final VoidCallback? onRefresh;
  final bool showInvoiceButton;
  final bool showEditButton;

  const BuyerListWidget({
    super.key,
    this.onBuyerSelected,
    this.onRefresh,
    this.showInvoiceButton = true,
    this.showEditButton = false,
  });

  @override
  State<BuyerListWidget> createState() => BuyerListWidgetState();
}

class BuyerListWidgetState extends State<BuyerListWidget> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;

  List<dynamic> _buyers = [];
  bool _isLoading = false;
  bool _isSearching = false;

  int _offset = 0;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _fetchBuyers();
    _scrollController.addListener(_onScroll);
  }

  // Thêm phương thức để bên ngoài có thể gọi làm mới
  Future<void> refresh({bool isQuiet = false}) async {
    if (!isQuiet) {
      _offset = 0;
      _hasMore = true;
    }
    await _fetchBuyers(isQuiet: isQuiet);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore && !_isSearching) {
        _fetchMoreBuyers();
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _offset = 0;
      _hasMore = true;
      _fetchBuyers();
    });
  }

  Future<void> _fetchBuyers({bool isQuiet = false}) async {
    if (!mounted) return;
    if (!isQuiet) {
      setState(() => _isLoading = true);
    }
    try {
      List<dynamic> buyers;
      if (_searchController.text.isNotEmpty) {
        buyers = await _apiService.searchBuyers(_searchController.text);
        _isSearching = true;
        _hasMore = false;
      } else {
        buyers = await _apiService.getBuyers(
          limit: isQuiet ? (_offset > 0 ? _offset : _limit) : _limit,
          offset: 0,
        );
        _isSearching = false;
        if (!isQuiet) {
          _offset = buyers.length;
          _hasMore = buyers.length == _limit;
        } else {
          _offset = buyers.length;
        }
      }
      if (mounted) {
        setState(() {
          _buyers = buyers;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted && !isQuiet) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMoreBuyers() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final moreBuyers = await _apiService.getBuyers(
        limit: _limit,
        offset: _offset,
      );

      if (mounted) {
        setState(() {
          if (moreBuyers.isEmpty) {
            _hasMore = false;
          } else {
            _buyers.addAll(moreBuyers);
            _offset += moreBuyers.length;
            _hasMore = moreBuyers.length == _limit;
          }
        });
      }
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 920;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: (val) {
              setState(() {});
              _onSearchChanged(val);
            },
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
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buyers.isEmpty
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
                              'Không tìm thấy người mua nào',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (_searchController.text.trim().isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Bạn có muốn tạo mới người mua "${_searchController.text.trim()}" không?',
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
                                      builder: (builderContext) => CreateBuyerScreen(
                                        initialName: _searchController.text.trim(),
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
                                    refresh(isQuiet: true);
                                    if (widget.onRefresh != null) {
                                      widget.onRefresh!();
                                    }
                                  }
                                },
                                icon: const Icon(Icons.person_add_alt_1_rounded),
                                label: const Text('Tạo người mua mới'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _fetchBuyers(isQuiet: true),
                      child: isDesktop
                          ? ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16.0),
                              itemCount: (_buyers.length / 3).ceil() + (_hasMore ? 1 : 0),
                              itemBuilder: (context, rowIndex) {
                                if (_hasMore && rowIndex == (_buyers.length / 3).ceil()) {
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
                                          child: (startIndex + i < _buyers.length)
                                              ? BuyerCard(
                                                  buyer: _buyers[startIndex + i],
                                                  showInvoiceButton: widget.showInvoiceButton,
                                                  showEditButton: widget.showEditButton,
                                                   onEditPressed: () async {
                                                    _searchFocusNode.unfocus();
                                                    final result = await Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (builderContext) => BuyerDetailScreen(
                                                          buyer: _buyers[startIndex + i],
                                                        ),
                                                      ),
                                                    );
                                                    if (context.mounted) {
                                                      _searchFocusNode.unfocus();
                                                    }
                                                    if (result == true && mounted) {
                                                      refresh(isQuiet: true);
                                                    }
                                                  },
                                                  onTap: () {
                                                    if (widget.onBuyerSelected != null) {
                                                      widget.onBuyerSelected!(_buyers[startIndex + i]);
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
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _buyers.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _buyers.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }

                                final buyer = _buyers[index];
                                return BuyerCard(
                                  buyer: buyer,
                                  showInvoiceButton: widget.showInvoiceButton,
                                  showEditButton: widget.showEditButton,
                                   onEditPressed: () async {
                                    _searchFocusNode.unfocus();
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (builderContext) => BuyerDetailScreen(
                                          buyer: buyer,
                                        ),
                                      ),
                                    );
                                    if (context.mounted) {
                                      _searchFocusNode.unfocus();
                                    }
                                    if (result == true && mounted) {
                                      refresh(isQuiet: true);
                                    }
                                  },
                                  onTap: () {
                                    if (widget.onBuyerSelected != null) {
                                      widget.onBuyerSelected!(buyer);
                                    }
                                  },
                                );
                              },
                            ),
                    ),
        ),
      ],
    );
  }

  void unfocusSearch() {
    _searchFocusNode.unfocus();
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
