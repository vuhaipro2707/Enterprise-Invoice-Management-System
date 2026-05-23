import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/pricelist_card.dart';

class PriceListManagementScreen extends StatefulWidget {
  const PriceListManagementScreen({super.key});

  @override
  State<PriceListManagementScreen> createState() => _PriceListManagementScreenState();
}

enum PriceListSortState { updatedAtDesc, createdAtDesc }

class _PriceListManagementScreenState extends State<PriceListManagementScreen> {
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

  String _sortBy = 'updated_at';
  String _sortOrder = 'desc';
  PriceListSortState _sortState = PriceListSortState.updatedAtDesc;

  // Selected filter details
  Map<String, dynamic>? _selectedBuyer;
  DateTime? _startDate;
  DateTime? _endDate;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
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
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        if (args.containsKey('buyer')) {
          _selectedBuyer = args['buyer'];
        }
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
    _debounce = Timer(const Duration(milliseconds: 500), () {
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
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        buyerName: _searchController.text.trim(),
        buyerId: _selectedBuyer?['buyer_id']?.toString(),
        startDate: _startDate,
        endDate: _endDate,
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
          SnackBar(content: Text('Lỗi tải bảng báo giá: $e')),
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
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        buyerName: _searchController.text.trim(),
        buyerId: _selectedBuyer?['buyer_id']?.toString(),
        startDate: _startDate,
        endDate: _endDate,
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
          SnackBar(content: Text('Lỗi tải thêm bảng báo giá: $e')),
        );
      }
    }
  }

  void _toggleSort() {
    setState(() {
      if (_sortState == PriceListSortState.updatedAtDesc) {
        _sortState = PriceListSortState.createdAtDesc;
        _sortBy = 'created_at';
        _sortOrder = 'desc';
      } else {
        _sortState = PriceListSortState.updatedAtDesc;
        _sortBy = 'updated_at';
        _sortOrder = 'desc';
      }
      _fetchInitialPriceLists();
    });
  }

  void _selectBuyerFilter() async {
    final selected = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => const _BuyerSearchFilterSheet(),
    );

    if (selected != null) {
      setState(() {
        _selectedBuyer = selected;
      });
      _fetchInitialPriceLists();
    }
  }

  void _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (BuildContext pickerContext, Widget? child) {
        return Theme(
          data: Theme.of(pickerContext).copyWith(
            colorScheme: Theme.of(pickerContext).colorScheme,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999);
      });
      _fetchInitialPriceLists();
    }
  }

  Future<void> _handlePriceListTap(Map<String, dynamic> pl) async {
    final pricelistId = pl['customer_price_list_id'].toString();
    if (mounted) {
      Navigator.pushNamed(
        context,
        '/edit_pricelist',
        arguments: pricelistId,
      ).then((_) => _fetchInitialPriceLists());
    }
  }

  Future<void> _handleQuickInvoice(Map<String, dynamic> pl) async {
    final buyerId = pl['buyer_id'];
    final pricelistId = pl['customer_price_list_id'].toString();

    if (buyerId != null) {
      // Case 1: Has Buyer ID
      final pickedItems = await Navigator.pushNamed(
        context,
        '/pricelist_item_picker',
        arguments: pricelistId,
      );

      if (pickedItems != null && pickedItems is List && pickedItems.isNotEmpty) {
        if (!mounted) return;
        final buyerName = pl['buyer_name'] ?? 'Khách lẻ';
        final itemCount = pickedItems.length;

        final bool? confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final colorScheme = Theme.of(context).colorScheme;
            return AlertDialog(
              title: const Text('Xác nhận tạo hóa đơn'),
              content: Text(
                'Bạn có chắc chắn muốn tạo hóa đơn mới cho $buyerName với $itemCount mặt hàng đã chọn không?'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('HỦY'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  child: const Text('TẠO HÓA ĐƠN'),
                ),
              ],
            );
          },
        );

        if (confirm != true) return;
        if (!mounted) return;

        setState(() => _isLoading = true);

        try {
          final code = await _apiService.getNextInvoiceCode();
          final response = await _apiService.createInvoice(
            buyerId: buyerId.toString(),
            invoiceCode: code,
          );

          final invoiceId = response['data']['invoice_id'];

          for (final item in pickedItems) {
            final Map<String, dynamic> itemMap = Map<String, dynamic>.from(item);
            await _apiService.createLineItem(invoiceId, {
              "itemID": itemMap['item_id'],
              "unitID": itemMap['unit_id'],
              "itemNameSnapshot": itemMap['item_name'],
              "unitNameSnapshot": itemMap['unit_name'],
              "quantity": (itemMap['quantity'] as num?)?.toInt() ?? 1,
              "unitPriceCustom": itemMap['price'],
            });
          }

          if (mounted) {
            Navigator.pushReplacementNamed(
              context,
              '/edit_invoice',
              arguments: {'invoiceId': invoiceId},
            );
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi khi tạo hóa đơn nhanh: $e')),
            );
          }
        }
      }
    } else {
      // Case 2: No Buyer ID
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/create_invoice',
          arguments: {'auto_apply_pricelist_id': pricelistId},
        ).then((_) => _fetchInitialPriceLists());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 920;

    String sortIconLabel = 'Mới cập nhật';
    IconData sortIcon = Icons.update;
    if (_sortState == PriceListSortState.updatedAtDesc) {
      sortIcon = Icons.update;
      sortIconLabel = 'Mới cập nhật';
    } else if (_sortState == PriceListSortState.createdAtDesc) {
      sortIcon = Icons.calendar_today;
      sortIconLabel = 'Mới khởi tạo';
    }

    final bool isSearching = _searchController.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bảng báo giá'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () {
              Navigator.pushNamed(context, '/pricelist_trash').then((_) {
                _fetchInitialPriceLists();
              });
            },
            tooltip: 'Thùng rác',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchInitialPriceLists,
            tooltip: 'Làm mới',
          ),
          TextButton.icon(
            onPressed: isSearching ? null : _toggleSort,
            icon: Icon(
              sortIcon,
              size: 20,
              color: isSearching
                  ? colorScheme.outline
                  : colorScheme.onSurface,
            ),
            label: Text(
              sortIconLabel,
              style: TextStyle(
                color: isSearching
                    ? colorScheme.outline
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(context, '/create_pricelist');
          _fetchInitialPriceLists();
        },
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        tooltip: 'Tạo báo giá mới',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm theo tên người mua...',
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
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                InputChip(
                  avatar: Icon(
                    Icons.person,
                    size: 16,
                    color: _selectedBuyer != null ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                  ),
                  label: Text(_selectedBuyer != null
                      ? 'Người mua: ${_selectedBuyer!['buyer_name']}'
                      : 'Lọc theo người mua'),
                  selected: _selectedBuyer != null,
                  selectedColor: colorScheme.primaryContainer,
                  onPressed: _selectBuyerFilter,
                  onDeleted: _selectedBuyer != null
                      ? () {
                          setState(() => _selectedBuyer = null);
                          _fetchInitialPriceLists();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                InputChip(
                  avatar: Icon(
                    Icons.date_range,
                    size: 16,
                    color: _startDate != null ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                  ),
                  label: Text(_startDate != null && _endDate != null
                      ? '${_dateFormat.format(_startDate!)} - ${_dateFormat.format(_endDate!)}'
                      : 'Lọc theo ngày'),
                  selected: _startDate != null,
                  selectedColor: colorScheme.primaryContainer,
                  onPressed: _selectDateRange,
                  onDeleted: _startDate != null
                      ? () {
                          setState(() {
                            _startDate = null;
                            _endDate = null;
                          });
                          _fetchInitialPriceLists();
                        }
                      : null,
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
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16.0),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  mainAxisExtent: 180,
                                ),
                                itemCount: _priceLists.length + (_isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) => _buildPriceListItem(context, index, colorScheme),
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                itemCount: _priceLists.length + (_isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: SizedBox(
                                    height: 180,
                                    child: _buildPriceListItem(context, index, colorScheme),
                                  ),
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceListItem(BuildContext context, int index, ColorScheme colorScheme) {
    if (index == _priceLists.length) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final pl = _priceLists[index];
    return PriceListCard(
      priceList: pl,
      onTap: () => _handlePriceListTap(pl),
      onQuickInvoice: () => _handleQuickInvoice(pl),
    );
  }
}

// Bottom Sheet to search and select Buyer
class _BuyerSearchFilterSheet extends StatefulWidget {
  const _BuyerSearchFilterSheet();

  @override
  State<_BuyerSearchFilterSheet> createState() => _BuyerSearchFilterSheetState();
}

class _BuyerSearchFilterSheetState extends State<_BuyerSearchFilterSheet> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _buyers = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchBuyers('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchBuyers(query);
    });
  }

  Future<void> _fetchBuyers(String keyword) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      List<dynamic> list;
      if (keyword.isEmpty) {
        list = await _apiService.getBuyers(limit: 20, offset: 0);
      } else {
        list = await _apiService.searchBuyers(keyword, limit: 20);
      }

      if (mounted) {
        setState(() {
          _buyers = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16.0,
        16.0,
        16.0,
        MediaQuery.of(context).viewInsets.bottom + 16.0,
      ),
      child: SizedBox(
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lọc theo Người mua',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm người mua...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buyers.isEmpty
                      ? const Center(child: Text('Không tìm thấy người mua nào'))
                      : ListView.builder(
                          itemCount: _buyers.length,
                          itemBuilder: (context, index) {
                            final buyer = _buyers[index];
                            final buyerName = buyer['buyer_name'] ?? '';
                            final buyerCode = buyer['buyer_code'] ?? '';
                            final address = buyer['address'] ?? '';

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primaryContainer,
                                child: Icon(Icons.person, color: colorScheme.onPrimaryContainer),
                              ),
                              title: Text('[$buyerCode] $buyerName'),
                              subtitle: Text(
                                address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(context, buyer);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
