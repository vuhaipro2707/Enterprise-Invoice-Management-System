import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/print_job_card.dart';
import '../pricelist/preview_helper.dart';
import 'print_job_detail_screen.dart';

class PrintQueueManagementScreen extends StatefulWidget {
  const PrintQueueManagementScreen({super.key});

  @override
  State<PrintQueueManagementScreen> createState() => _PrintQueueManagementScreenState();
}

class _PrintQueueManagementScreenState extends State<PrintQueueManagementScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _invoiceIdController = TextEditingController();
  final TextEditingController _cplIdController = TextEditingController();

  List<dynamic> _jobs = [];
  bool _isLoading = false;

  // Pagination states
  int _offset = 0;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  // Filter states
  String? _selectedStatus;
  String? _selectedQueueType;
  String? _filterInvoiceId;
  String? _filterCustomerPriceListId;

  Timer? _refreshTimer;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Auto refresh every 5 seconds to show printing queue updates in real-time
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isLoading && !_isLoadingMore) {
        _fetchPrintJobs(isAutoRefresh: true);
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadMorePrintJobs();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        if (args.containsKey('invoiceId')) {
          final invId = args['invoiceId']?.toString();
          if (invId != null && invId.isNotEmpty) {
            _filterInvoiceId = invId;
            _invoiceIdController.text = invId;
            _selectedQueueType = 'Invoice';
          }
        }
        if (args.containsKey('customerPriceListId')) {
          final cplId = args['customerPriceListId']?.toString();
          if (cplId != null && cplId.isNotEmpty) {
            _filterCustomerPriceListId = cplId;
            _cplIdController.text = cplId;
            _selectedQueueType = 'PriceList';
          }
        }
      }
      _fetchPrintJobs();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    _invoiceIdController.dispose();
    _cplIdController.dispose();
    super.dispose();
  }

  Future<void> _fetchPrintJobs({bool isAutoRefresh = false}) async {
    if (!isAutoRefresh) {
      setState(() {
        _isLoading = true;
        _offset = 0;
        _hasMore = true;
      });
    }
    try {
      final jobs = await _apiService.getPrintJobs(
        status: _selectedStatus,
        queueType: _selectedQueueType,
        invoiceId: _filterInvoiceId,
        customerPriceListId: _filterCustomerPriceListId,
        limit: isAutoRefresh ? (_offset > 0 ? _offset : _limit) : _limit,
        offset: 0,
      );
      if (mounted) {
        setState(() {
          _jobs = jobs;
          if (!isAutoRefresh) {
            _offset = jobs.length;
            _hasMore = jobs.length == _limit;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !isAutoRefresh) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lấy danh sách in: $e')),
        );
      }
    }
  }

  Future<void> _loadMorePrintJobs() async {
    setState(() => _isLoadingMore = true);
    try {
      final moreJobs = await _apiService.getPrintJobs(
        status: _selectedStatus,
        queueType: _selectedQueueType,
        invoiceId: _filterInvoiceId,
        customerPriceListId: _filterCustomerPriceListId,
        limit: _limit,
        offset: _offset,
      );
      if (mounted) {
        setState(() {
          if (moreJobs.isEmpty) {
            _hasMore = false;
          } else {
            _jobs.addAll(moreJobs);
            _offset += moreJobs.length;
            _hasMore = moreJobs.length == _limit;
          }
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải thêm danh sách in: $e')),
        );
      }
    }
  }

  Future<void> _updateJobStatus(String jobId, String status, {int? retryCount}) async {
    setState(() => _isLoading = true);
    try {
      await _apiService.updatePrintJobStatus(jobId, status, retryCount: retryCount);
      await _fetchPrintJobs(isAutoRefresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã cập nhật trạng thái thành công sang: $status')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cập nhật trạng thái: $e')),
        );
      }
    }
  }

  Future<void> _updateJobPriority(String jobId, int priorityNum) async {
    setState(() => _isLoading = true);
    try {
      await _apiService.updatePrintJobStatus(jobId, null, priorityNum: priorityNum);
      await _fetchPrintJobs(isAutoRefresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã ưu tiên bản in thành công!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cập nhật mức ưu tiên: $e')),
        );
      }
    }
  }

  Future<void> _recreatePrintJob(Map<String, dynamic> job) async {
    setState(() => _isLoading = true);
    try {
      await _apiService.createPrintJob(
        invoiceId: job['invoiceId']?.toString(),
        customerPriceListId: job['customerPriceListId']?.toString(),
        printType: job['printType']?.toString() ?? 'Original',
        printPart: job['printPart']?.toString(),
        priorityNum: 0,
      );
      if (mounted) {
        await _fetchPrintJobs(isAutoRefresh: true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tạo lại lệnh in thành công!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tạo lại lệnh in: $e')),
        );
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = null;
      _selectedQueueType = null;
      _filterInvoiceId = null;
      _filterCustomerPriceListId = null;
      _invoiceIdController.clear();
      _cplIdController.clear();
    });
    _fetchPrintJobs();
  }

  void _applyAdvancedFilters() {
    setState(() {
      _filterInvoiceId = _invoiceIdController.text.trim().isEmpty ? null : _invoiceIdController.text.trim();
      _filterCustomerPriceListId = _cplIdController.text.trim().isEmpty ? null : _cplIdController.text.trim();
    });
    _fetchPrintJobs();
  }


  void _showAdvancedFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext builderContext, StateSetter setSheetState) {
            final colorScheme = Theme.of(builderContext).colorScheme;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(builderContext).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Lọc nâng cao theo ID',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _invoiceIdController,
                    decoration: InputDecoration(
                      labelText: 'ID Hóa đơn (UUID)',
                      hintText: 'Chọn hóa đơn hoặc nhập UUID',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.description),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_invoiceIdController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setSheetState(() {
                                  _invoiceIdController.clear();
                                });
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.manage_search, color: Colors.blue),
                            tooltip: 'Chọn Hóa đơn',
                            onPressed: () async {
                              final result = await Navigator.pushNamed(
                                builderContext,
                                '/invoice_management',
                                arguments: {'isPicker': true},
                              );
                              if (result != null && result is Map) {
                                final invId = result['invoiceId']?.toString();
                                if (invId != null && builderContext.mounted) {
                                  setSheetState(() {
                                    _invoiceIdController.text = invId;
                                  });
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cplIdController,
                    decoration: InputDecoration(
                      labelText: 'ID Báo giá (UUID)',
                      hintText: 'Chọn báo giá hoặc nhập UUID',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.request_quote),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_cplIdController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setSheetState(() {
                                  _cplIdController.clear();
                                });
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.manage_search, color: Colors.teal),
                            tooltip: 'Chọn Báo giá',
                            onPressed: () async {
                              final result = await Navigator.pushNamed(
                                builderContext,
                                '/pricelist_management',
                                arguments: {'isPicker': true},
                              );
                              if (result != null && result is Map) {
                                final cplId = result['customerPriceListId']?.toString();
                                if (cplId != null && builderContext.mounted) {
                                  setSheetState(() {
                                    _cplIdController.text = cplId;
                                  });
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setSheetState(() {
                              _invoiceIdController.clear();
                              _cplIdController.clear();
                            });
                            Navigator.pop(builderContext);
                            _applyAdvancedFilters();
                          },
                          child: const Text('XÓA TRƯỜNG'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(builderContext);
                            _applyAdvancedFilters();
                          },
                          child: const Text('ÁP DỤNG'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 920;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hàng chờ in'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchPrintJobs(isAutoRefresh: true),
            tooltip: 'Làm mới',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list_off_outlined),
            onPressed: _clearFilters,
            tooltip: 'Xóa toàn bộ bộ lọc',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter section
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Queue Type Selector
                  FilterChip(
                    label: const Text('Tất cả nguồn'),
                    selected: _selectedQueueType == null,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedQueueType = null);
                        _fetchPrintJobs();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Hóa đơn'),
                    selected: _selectedQueueType == 'Invoice',
                    onSelected: (selected) {
                      setState(() => _selectedQueueType = selected ? 'Invoice' : null);
                      _fetchPrintJobs();
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Báo giá'),
                    selected: _selectedQueueType == 'PriceList',
                    onSelected: (selected) {
                      setState(() => _selectedQueueType = selected ? 'PriceList' : null);
                      _fetchPrintJobs();
                    },
                  ),
                  const VerticalDivider(width: 24),
                  // Status Selectors
                  FilterChip(
                    label: const Text('Mọi trạng thái'),
                    selected: _selectedStatus == null,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedStatus = null);
                        _fetchPrintJobs();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Chờ in'),
                    selected: _selectedStatus == 'Pending',
                    onSelected: (selected) {
                      setState(() => _selectedStatus = selected ? 'Pending' : null);
                      _fetchPrintJobs();
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Đang in'),
                    selected: _selectedStatus == 'Printing',
                    onSelected: (selected) {
                      setState(() => _selectedStatus = selected ? 'Printing' : null);
                      _fetchPrintJobs();
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Hoàn thành'),
                    selected: _selectedStatus == 'Completed',
                    onSelected: (selected) {
                      setState(() => _selectedStatus = selected ? 'Completed' : null);
                      _fetchPrintJobs();
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Thất bại'),
                    selected: _selectedStatus == 'Failed',
                    onSelected: (selected) {
                      setState(() => _selectedStatus = selected ? 'Failed' : null);
                      _fetchPrintJobs();
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Đã hủy'),
                    selected: _selectedStatus == 'Cancelled',
                    onSelected: (selected) {
                      setState(() => _selectedStatus = selected ? 'Cancelled' : null);
                      _fetchPrintJobs();
                    },
                  ),
                  const VerticalDivider(width: 24),
                  // Advanced Lọc Button
                  ActionChip(
                    avatar: const Icon(Icons.manage_search, size: 16),
                    label: Text(
                      (_filterInvoiceId != null || _filterCustomerPriceListId != null)
                          ? 'Đang lọc ID (Bật)'
                          : 'Lọc nâng cao ID',
                    ),
                    onPressed: _showAdvancedFilterSheet,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Main list or loading
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _jobs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.print_disabled_outlined, size: 64, color: colorScheme.outlineVariant),
                            const SizedBox(height: 16),
                            const Text('Không tìm thấy lệnh in nào phù hợp'),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _fetchPrintJobs(isAutoRefresh: true),
                        child: isDesktop
                            ? ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount: (_jobs.length / 3).ceil(),
                                itemBuilder: (context, rowIndex) {
                                  final startIdx = rowIndex * 3;
                                  final endIdx = (startIdx + 3 > _jobs.length) ? _jobs.length : startIdx + 3;
                                  final rowJobs = _jobs.sublist(startIdx, endIdx);

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: List.generate(3, (colIndex) {
                                          if (colIndex < rowJobs.length) {
                                            final job = rowJobs[colIndex];
                                            final jobIndex = startIdx + colIndex;
                                            return Expanded(
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: PrintJobCard(
                                                      job: job,
                                                      onUpdateStatus: _updateJobStatus,
                                                      onUpdatePriority: _updateJobPriority,
                                                      onRecreateJob: _recreatePrintJob,
                                                      onTap: () {
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) => PrintJobDetailScreen(
                                                              job: job,
                                                              onUpdateStatus: _updateJobStatus,
                                                              onUpdatePriority: _updateJobPriority,
                                                              onRecreateJob: _recreatePrintJob,
                                                            ),
                                                          ),
                                                        ).then((_) {
                                                          _fetchPrintJobs(isAutoRefresh: true);
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                  if (jobIndex < _jobs.length - 1 && colIndex < 2)
                                                    Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                                      child: Icon(
                                                        Icons.arrow_forward_rounded,
                                                        color: colorScheme.primary.withValues(alpha: 0.6),
                                                        size: 20,
                                                      ),
                                                    )
                                                  else if (jobIndex < _jobs.length - 1 && colIndex == 2)
                                                    const SizedBox(width: 28),
                                                ],
                                              ),
                                            );
                                          } else {
                                            return const Expanded(child: SizedBox());
                                          }
                                        }),
                                      ),
                                      if (endIdx < _jobs.length) ...[
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(left: 45.0),
                                              child: Icon(
                                                Icons.arrow_downward_rounded,
                                                color: colorScheme.primary.withValues(alpha: 0.6),
                                                size: 20,
                                              ),
                                            ),
                                            Expanded(
                                              child: CustomPaint(
                                                painter: DashedLinePainter(
                                                  color: colorScheme.primary.withValues(alpha: 0.4),
                                                ),
                                                child: const SizedBox(height: 20),
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.only(right: 45.0),
                                              child: Icon(
                                                Icons.keyboard_return_rounded,
                                                color: colorScheme.primary.withValues(alpha: 0.6),
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                      ] else ...[
                                        const SizedBox(height: 16),
                                      ],
                                    ],
                                  );
                                },
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount: _jobs.length,
                                itemBuilder: (context, index) {
                                  final job = _jobs[index];
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      PrintJobCard(
                                        job: job,
                                        onUpdateStatus: _updateJobStatus,
                                        onUpdatePriority: _updateJobPriority,
                                        onRecreateJob: _recreatePrintJob,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => PrintJobDetailScreen(
                                                job: job,
                                                onUpdateStatus: _updateJobStatus,
                                                onUpdatePriority: _updateJobPriority,
                                                onRecreateJob: _recreatePrintJob,
                                              ),
                                            ),
                                          ).then((_) {
                                            _fetchPrintJobs(isAutoRefresh: true);
                                          });
                                        },
                                      ),
                                      if (index < _jobs.length - 1) ...[
                                        const SizedBox(height: 8),
                                        Center(
                                          child: Icon(
                                            Icons.keyboard_double_arrow_down_rounded,
                                            color: colorScheme.primary.withValues(alpha: 0.6),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ] else ...[
                                        const SizedBox(height: 12),
                                      ],
                                    ],
                                  );
                                },
                              ),
                      ),
          ),
          if (_isLoadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }


}

class PrintJobPreviewWidget extends StatefulWidget {
  final String? invoiceId;
  final String? customerPriceListId;
  final String printType;
  final String? printPart;
  final String titleText;
  final ApiService apiService;
  final bool hidePreview;
  final bool showCloseButton;
  final VoidCallback? onPrintAction;
  final String? pageSize;

  const PrintJobPreviewWidget({
    super.key,
    required this.invoiceId,
    required this.customerPriceListId,
    required this.printType,
    this.printPart,
    required this.titleText,
    required this.apiService,
    this.hidePreview = false,
    this.showCloseButton = true,
    this.onPrintAction,
    this.pageSize,
  });

  @override
  State<PrintJobPreviewWidget> createState() => PrintJobPreviewWidgetState();
}

class PrintJobPreviewWidgetState extends State<PrintJobPreviewWidget> {
  bool _isLoading = true;
  Uint8List? _pdfBytes;
  String? _pdfViewId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Uint8List bytes;
      if (widget.invoiceId != null) {
        final res = await widget.apiService.exportInvoice(
          widget.invoiceId!,
          widget.printType,
          printPart: widget.printPart,
        );
        bytes = res as Uint8List;
      } else if (widget.customerPriceListId != null) {
        final res = await widget.apiService.exportPriceList(
          widget.customerPriceListId!,
          'pdf',
          pageSize: widget.pageSize,
        );
        bytes = res as Uint8List;
      } else {
        throw Exception('Không xác định được nguồn in.');
      }

      if (mounted) {
        setState(() {
          _pdfBytes = bytes;
          _pdfViewId = registerPdfPreview(bytes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                widget.titleText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const Divider(),
        const SizedBox(height: 12),
        Expanded(
          child: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Đang tải bản xem trước PDF từ máy chủ...',
                        style: TextStyle(color: colorScheme.outline, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _loadPdf,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    )
                  : widget.hidePreview
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.hourglass_bottom_rounded,
                                size: 48,
                                color: colorScheme.primary.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Đang mở tùy chọn in...',
                                style: TextStyle(color: colorScheme.outline, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : buildPreviewWidget(
                          context,
                          _pdfBytes!,
                          'pdf',
                          viewId: _pdfViewId,
                        ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_pdfBytes != null) ...[
              if (widget.invoiceId != null || widget.customerPriceListId != null)
                ElevatedButton.icon(
                  onPressed: () {
                    if (widget.invoiceId != null) {
                      Navigator.pushNamed(context, '/invoice_detail', arguments: widget.invoiceId);
                    } else if (widget.customerPriceListId != null) {
                      Navigator.pushNamed(context, '/edit_pricelist', arguments: widget.customerPriceListId);
                    }
                  },
                  icon: Icon(
                    widget.invoiceId != null ? Icons.receipt_long_rounded : Icons.request_quote_rounded,
                    size: 16,
                  ),
                  label: Text(
                    widget.invoiceId != null ? 'MỞ HÓA ĐƠN' : 'MỞ BÁO GIÁ',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              if (widget.onPrintAction != null)
                ElevatedButton.icon(
                  onPressed: widget.onPrintAction,
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: const Text(
                    'IN LẠI',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: () {
                  final fileName = widget.invoiceId != null ? 'Hoa_don.pdf' : 'Bao_gia.pdf';
                  downloadFile(_pdfBytes!, fileName, 'application/pdf', '');
                },
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text(
                  'LƯU VỀ MÁY',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
            if (widget.showCloseButton)
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text(
                  'ĐÓNG',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class DashedLinePainter extends CustomPainter {
  final Color color;
  DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double startX = size.width - 10;
    const endX = 10.0;
    final y = size.height / 2;

    while (startX > endX) {
      canvas.drawLine(Offset(startX, y), Offset(startX - dashWidth, y), paint);
      startX -= dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
