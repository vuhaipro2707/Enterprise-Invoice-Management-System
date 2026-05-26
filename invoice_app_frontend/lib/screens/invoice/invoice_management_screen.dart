import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/invoice_card.dart';
import '../../main.dart' show routeObserver;

class InvoiceManagementScreen extends StatefulWidget {
  const InvoiceManagementScreen({super.key});

  @override
  State<InvoiceManagementScreen> createState() => _InvoiceManagementScreenState();
}

enum SortState { updatedAtDesc, createdAtDesc }

class _InvoiceManagementScreenState extends State<InvoiceManagementScreen> with RouteAware {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  
  List<dynamic> _invoices = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;

  // Search & Filter state
  bool _showEditing = true;
  bool _showSaved = true;
  bool _showLocked = true;
  String? _sortBy = 'created_at'; // 'updated_at' or 'created_at'
  String? _sortOrder = 'desc';   // 'desc' or 'asc'
  SortState _sortState = SortState.createdAtDesc;
  
  // Selected filter details
  Map<String, dynamic>? _selectedBuyer;
  Map<String, dynamic>? _selectedItem;

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
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
    if (!_isArgumentsParsed) {
      _isArgumentsParsed = true;
      final args = route?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        if (args.containsKey('buyer')) {
          _selectedBuyer = args['buyer'];
        }
        if (args.containsKey('item')) {
          _selectedItem = args['item'];
        }
      }
      _fetchInitialInvoices();
    }
  }

  /// Called when a route above this one is popped (user navigated back here).
  @override
  void didPopNext() {
    _fetchInitialInvoices();
  }

  void _toggleSort() {
    setState(() {
      if (_sortState == SortState.updatedAtDesc) {
        _sortState = SortState.createdAtDesc;
        _sortBy = 'created_at';
        _sortOrder = 'desc';
      } else {
        _sortState = SortState.updatedAtDesc;
        _sortBy = 'updated_at';
        _sortOrder = 'desc';
      }
      _fetchInitialInvoices();
    });
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _fetchMoreInvoices();
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchInitialInvoices();
    });
  }

  Future<void> _fetchInitialInvoices() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _offset = 0;
      _hasMore = true;
      _invoices = [];
    });

    try {
      final invoices = await _apiService.getInvoices(
        limit: _limit,
        offset: 0,
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        showDraft: _showEditing,
        showSaved: _showSaved,
        showLocked: _showLocked,
        buyerId: _selectedBuyer?['buyerId']?.toString(),
        itemId: _selectedItem?['itemId']?.toString(),
        invoiceCode: _searchController.text,
        startDate: _startDate,
        endDate: _endDate,
      );

      if (mounted) {
        setState(() {
          _invoices = invoices;
          _offset = invoices.length;
          _hasMore = invoices.length == _limit;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải hóa đơn: $e')),
        );
      }
    }
  }

  Future<void> _fetchMoreInvoices() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final moreInvoices = await _apiService.getInvoices(
        limit: _limit,
        offset: _offset,
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        showDraft: _showEditing,
        showSaved: _showSaved,
        showLocked: _showLocked,
        buyerId: _selectedBuyer?['buyerId']?.toString(),
        itemId: _selectedItem?['itemId']?.toString(),
        invoiceCode: _searchController.text,
        startDate: _startDate,
        endDate: _endDate,
      );

      if (mounted) {
        setState(() {
          if (moreInvoices.isEmpty) {
            _hasMore = false;
          } else {
            _invoices.addAll(moreInvoices);
            _offset += moreInvoices.length;
            _hasMore = moreInvoices.length == _limit;
          }
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải thêm hóa đơn: $e')),
        );
      }
    }
  }

  Future<void> _handleInvoiceTap(Map<String, dynamic> inv) async {
    final invoiceId = inv['invoiceId'].toString();

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final bool isPicker = args != null && args['isPicker'] == true;
    if (isPicker) {
      Navigator.pop(context, inv);
      return;
    }
    
    // Helper to get string value safely
    String? getStringValueLocal(dynamic field) {
      if (field == null) return null;
      if (field is Map) return field['Valid'] == true ? field['String'].toString() : null;
      return field.toString();
    }

    final isEditing = inv['editStatus'] == true;
    final currentDeviceHoldingId = getStringValueLocal(inv['deviceHoldingId']);
    final deviceName = getStringValueLocal(inv['deviceName']) ?? 'Thiết bị khác';

    // Reroute finalized invoices to the read-only details screen
    if (!isEditing) {
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/invoice_detail',
          arguments: invoiceId,
        ).then((_) => _fetchInitialInvoices());
      }
      return;
    }

    // Show warning if invoice is being edited by another device
    if (isEditing && currentDeviceHoldingId != null && currentDeviceHoldingId != _apiService.deviceId) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Hóa đơn đang bị sửa'),
            ],
          ),
          content: Text(
            'Hóa đơn này đang được chỉnh sửa bởi "$deviceName".\n\n'
            'Nếu tiếp tục, thiết bị kia sẽ mất quyền sửa đổi. Bạn có muốn chiếm quyền không?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('TIẾP TỤC'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      // Lock / Take turn on invoice
      await _apiService.takeTurn(invoiceId);
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/edit_invoice',
          arguments: invoiceId,
        ).then((_) => _fetchInitialInvoices());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể truy cập hóa đơn: $e')),
        );
      }
    }
  }

  void _selectBuyerFilter() async {
    // Show a modal to search and select buyer
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
      _fetchInitialInvoices();
    }
  }

  void _selectItemFilter() async {
    // Show a modal to search and select item
    final selected = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => const _ItemSearchFilterSheet(),
    );

    if (selected != null) {
      setState(() {
        _selectedItem = selected;
      });
      _fetchInitialInvoices();
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
      _fetchInitialInvoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 920;

    String sortIconLabel = 'Mới cập nhật';
    IconData sortIcon = Icons.update;
    if (_sortState == SortState.updatedAtDesc) {
      sortIcon = Icons.update;
      sortIconLabel = 'Mới cập nhật';
    } else if (_sortState == SortState.createdAtDesc) {
      sortIcon = Icons.calendar_today;
      sortIconLabel = 'Mới khởi tạo';
    }

    final bool isSearching = _searchController.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Hóa đơn'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () {
              Navigator.pushNamed(context, '/invoice_trash').then((_) {
                _fetchInitialInvoices();
              });
            },
            tooltip: 'Thùng rác',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchInitialInvoices,
            tooltip: 'Làm mới',
          ),
          TextButton.icon(
            onPressed: isSearching ? null : _toggleSort,
            icon: Icon(
              sortIcon,
              size: 20,
              color: isSearching
                  ? Theme.of(context).colorScheme.outline
                  : Theme.of(context).colorScheme.onSurface,
            ),
            label: Text(
              sortIconLabel,
              style: TextStyle(
                color: isSearching
                    ? Theme.of(context).colorScheme.outline
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(context, '/create_invoice');
          _fetchInitialInvoices();
        },
        tooltip: 'Thêm hóa đơn mới',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Debounced Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm mã hóa đơn...',
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

          // Horizontally Scrollable Filters and Toggles
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                // Show Editing Toggle (FilterChip)
                FilterChip(
                  avatar: Icon(
                    _showEditing ? Icons.edit : Icons.edit_off,
                    size: 16,
                    color: _showEditing ? Colors.orange : colorScheme.outline,
                  ),
                  label: const Text('Đang sửa'),
                  selected: _showEditing,
                  onSelected: (selected) {
                    setState(() {
                      _showEditing = selected;
                    });
                    _fetchInitialInvoices();
                  },
                ),
                const SizedBox(width: 8),

                // Show Saved Toggle (FilterChip)
                FilterChip(
                  avatar: Icon(
                    _showSaved ? Icons.check_circle : Icons.check_circle_outline,
                    size: 16,
                    color: _showSaved ? Colors.blue : colorScheme.outline,
                  ),
                  label: const Text('Đã lưu'),
                  selected: _showSaved,
                  onSelected: (selected) {
                    setState(() {
                      _showSaved = selected;
                    });
                    _fetchInitialInvoices();
                  },
                ),
                const SizedBox(width: 8),

                // Show Locked Toggle (FilterChip)
                FilterChip(
                  avatar: Icon(
                    _showLocked ? Icons.lock : Icons.lock_open,
                    size: 16,
                    color: _showLocked ? Colors.green : colorScheme.outline,
                  ),
                  label: const Text('Đã khóa'),
                  selected: _showLocked,
                  onSelected: (selected) {
                    setState(() {
                      _showLocked = selected;
                    });
                    _fetchInitialInvoices();
                  },
                ),
                const SizedBox(width: 8),

                // Filter by Buyer (InputChip)
                InputChip(
                  avatar: Icon(
                    Icons.person,
                    size: 16,
                    color: _selectedBuyer != null ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                  ),
                  label: Text(_selectedBuyer != null
                      ? 'Người mua: ${_selectedBuyer!['buyerName']}'
                      : 'Lọc theo người mua'),
                  selected: _selectedBuyer != null,
                  selectedColor: colorScheme.primaryContainer,
                  onPressed: _selectBuyerFilter,
                  onDeleted: _selectedBuyer != null
                      ? () {
                          setState(() => _selectedBuyer = null);
                          _fetchInitialInvoices();
                        }
                      : null,
                ),
                const SizedBox(width: 8),

                // Filter by Item (InputChip)
                InputChip(
                  avatar: Icon(
                    Icons.inventory,
                    size: 16,
                    color: _selectedItem != null ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                  ),
                  label: Text(_selectedItem != null
                      ? 'Mặt hàng: ${_selectedItem!['itemDefaultName']}'
                      : 'Lọc theo mặt hàng'),
                  selected: _selectedItem != null,
                  selectedColor: colorScheme.primaryContainer,
                  onPressed: _selectItemFilter,
                  onDeleted: _selectedItem != null
                      ? () {
                          setState(() => _selectedItem = null);
                          _fetchInitialInvoices();
                        }
                      : null,
                ),
                const SizedBox(width: 8),

                // Filter by Date Range (InputChip)
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
                          _fetchInitialInvoices();
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Main list or loading indicator
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _invoices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.description_outlined, size: 64, color: colorScheme.outline),
                            const SizedBox(height: 16),
                            const Text(
                              'Không tìm thấy hóa đơn nào',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchInitialInvoices,
                        child: isDesktop
                            ? GridView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16.0),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  mainAxisExtent: 215,
                                ),
                                itemCount: _invoices.length + (_isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) => _buildInvoiceItem(context, index, colorScheme),
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16.0),
                                itemCount: _invoices.length + (_isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: _buildInvoiceItem(context, index, colorScheme),
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceItem(BuildContext context, int index, ColorScheme colorScheme) {
    if (index == _invoices.length) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final inv = _invoices[index];
    return InvoiceCard(
      invoice: inv,
      onTap: () => _handleInvoiceTap(inv),
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
                            final buyerName = buyer['buyerName'] ?? '';
                            final buyerCode = buyer['buyerCode'] ?? '';
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

// Bottom Sheet to search and select Item
class _ItemSearchFilterSheet extends StatefulWidget {
  const _ItemSearchFilterSheet();

  @override
  State<_ItemSearchFilterSheet> createState() => _ItemSearchFilterSheetState();
}

class _ItemSearchFilterSheetState extends State<_ItemSearchFilterSheet> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _items = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchItems('');
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
      _fetchItems(query);
    });
  }

  Future<void> _fetchItems(String keyword) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      List<dynamic> list;
      if (keyword.isEmpty) {
        list = await _apiService.getItems(limit: 20, offset: 0);
      } else {
        list = await _apiService.searchItems(keyword, limit: 20);
      }

      if (mounted) {
        setState(() {
          _items = list;
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
              'Lọc theo Mặt hàng',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
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
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(child: Text('Không tìm thấy mặt hàng nào'))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final defaultName = item['itemDefaultName'] ?? '';

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.secondaryContainer,
                                child: Icon(Icons.inventory, color: colorScheme.onSecondaryContainer),
                              ),
                              title: Text(defaultName),
                              onTap: () {
                                Navigator.pop(context, item);
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
