import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/buyer_card.dart';
import 'create_buyer_screen.dart';
import 'buyer_detail_screen.dart';
class BuyerManagementScreen extends StatefulWidget {
  const BuyerManagementScreen({super.key});

  @override
  State<BuyerManagementScreen> createState() => _BuyerManagementScreenState();
}

class _BuyerManagementScreenState extends State<BuyerManagementScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  List<dynamic> _buyers = [];
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
    _fetchBuyers();
    _scrollController.addListener(_onScroll);
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

  Future<void> _fetchBuyers() async {
    setState(() => _isLoading = true);
    try {
      List<dynamic> buyers;
      if (_searchController.text.isNotEmpty) {
        buyers = await _apiService.searchBuyers(_searchController.text);
        _isSearching = true;
        _hasMore = false;
      } else {
        buyers = await _apiService.getBuyers(
          limit: _limit,
          offset: 0,
        );
        _isSearching = false;
        _offset = buyers.length;
        _hasMore = buyers.length == _limit;
      }
      setState(() {
        _buyers = buyers;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải danh sách người mua: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMoreBuyers() async {
    setState(() => _isLoadingMore = true);
    try {
      final moreBuyers = await _apiService.getBuyers(
        limit: _limit,
        offset: _offset,
      );

      setState(() {
        if (moreBuyers.isEmpty) {
          _hasMore = false;
        } else {
          _buyers.addAll(moreBuyers);
          _offset += moreBuyers.length;
          _hasMore = moreBuyers.length == _limit;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải thêm danh sách: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý người mua'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _fetchBuyers,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới dữ liệu',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateBuyerScreen()),
          );
          if (result == true) {
            _fetchBuyers();
          }
        },
        tooltip: 'Thêm người mua mới',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc mã người mua...',
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
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buyers.isEmpty
                    ? const Center(child: Text('Không tìm thấy người mua nào'))
                    : RefreshIndicator(
                        onRefresh: () async {
                          _offset = 0;
                          _hasMore = true;
                          await _fetchBuyers();
                        },
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          controller: _scrollController,
                          itemCount: _buyers.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _buyers.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            return BuyerCard(
                              buyer: _buyers[index],
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => BuyerDetailScreen(buyer: _buyers[index]),
                                  ),
                                );
                                if (result == true) {
                                  _fetchBuyers();
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
