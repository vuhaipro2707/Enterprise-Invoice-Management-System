import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import 'print_queue_management_screen.dart'; // to reuse PrintJobPreviewWidget

class PrintJobDetailScreen extends StatefulWidget {
  final Map<String, dynamic> job;
  final Function(String jobId, String status, {int? retryCount}) onUpdateStatus;
  final Function(String jobId, int priority) onUpdatePriority;
  final Function(Map<String, dynamic> job) onRecreateJob;

  const PrintJobDetailScreen({
    super.key,
    required this.job,
    required this.onUpdateStatus,
    required this.onUpdatePriority,
    required this.onRecreateJob,
  });

  @override
  State<PrintJobDetailScreen> createState() => _PrintJobDetailScreenState();
}

class _PrintJobDetailScreenState extends State<PrintJobDetailScreen> {
  final ApiService _apiService = ApiService();
  late Map<String, dynamic> _currentJob;
  bool _isLoading = false;
  bool _isDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _currentJob = Map<String, dynamic>.from(widget.job);
  }

  String _formatDateTime(dynamic timestampStr) {
    if (timestampStr == null) return 'N/A';
    try {
      final date = DateTime.parse(timestampStr.toString());
      return DateFormat('HH:mm:ss dd/MM/yyyy').format(date.toLocal());
    } catch (_) {
      return timestampStr.toString();
    }
  }

  Color _getStatusColor(String status, ColorScheme colorScheme) {
    switch (status) {
      case 'Pending':
        return Colors.orange;
      case 'Printing':
        return colorScheme.primary;
      case 'Completed':
        return Colors.green;
      case 'Failed':
        return colorScheme.error;
      case 'Cancelled':
        return Colors.grey;
      default:
        return colorScheme.outline;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'Pending':
        return 'Chờ in';
      case 'Printing':
        return 'Đang in';
      case 'Completed':
        return 'Hoàn thành';
      case 'Failed':
        return 'Thất bại';
      case 'Cancelled':
        return 'Đã hủy';
      default:
        return status;
    }
  }

  Future<void> _updateStatus(String status, {int? retryCount}) async {
    setState(() => _isLoading = true);
    try {
      final String jobId = _currentJob['printJobId']?.toString() ?? '';
      final int currentRetry = (retryCount != null) ? retryCount : ((_currentJob['retryCount'] as num?)?.toInt() ?? 0);
      
      await _apiService.updatePrintJobStatus(jobId, status, retryCount: currentRetry, priorityNum: (_currentJob['priorityNum'] as num?)?.toInt());
      
      // Update local state
      setState(() {
        _currentJob['printStatus'] = status;
        if (retryCount != null) {
          _currentJob['retryCount'] = retryCount;
        }
        _isLoading = false;
      });

      // Trigger parent callback
      widget.onUpdateStatus(jobId, status, retryCount: retryCount);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã cập nhật trạng thái thành công sang: ${_getStatusText(status)}')),
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

  Future<void> _updatePriority(int priorityVal) async {
    setState(() => _isLoading = true);
    try {
      final String jobId = _currentJob['printJobId']?.toString() ?? '';
      await _apiService.updatePrintJobStatus(jobId, null, priorityNum: priorityVal);
      
      setState(() {
        _currentJob['priorityNum'] = priorityVal;
        _isLoading = false;
      });

      widget.onUpdatePriority(jobId, priorityVal);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật mức ưu tiên thành công!')),
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

  Future<void> _recreateJob() async {
    setState(() => _isLoading = true);
    try {
      await _apiService.createPrintJob(
        invoiceId: _currentJob['invoiceId']?.toString(),
        customerPriceListId: _currentJob['customerPriceListId']?.toString(),
        printType: _currentJob['printType']?.toString() ?? 'Original',
        printPart: _currentJob['printPart']?.toString(),
        priorityNum: 0,
      );

      // Trigger parent callback
      widget.onRecreateJob(_currentJob);

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tạo lại lệnh in thành công!')),
        );
        Navigator.pop(context); // Go back to the queue list since a new job is queued
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

  Future<void> _showReprintDialog() async {
    final bool isInvoice = _currentJob['invoiceId'] != null;
    final String? invoiceId = _currentJob['invoiceId']?.toString();
    final String? cplId = _currentJob['customerPriceListId']?.toString();

    setState(() => _isDialogOpen = true);
    try {
      if (!isInvoice) {
        // For price list, simple confirmation
        final bool? confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final colorScheme = Theme.of(dialogContext).colorScheme;
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.print, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Xác nhận in lại'),
                ],
              ),
              content: const Text('Bạn có muốn tạo một lệnh in mới cho báo giá này không?'),
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
                  child: const Text('XÁC NHẬN'),
                ),
              ],
            );
          },
        );

        if (confirm == true) {
          setState(() => _isLoading = true);
          try {
            await _apiService.createPrintJob(
              customerPriceListId: cplId,
              printType: 'Original',
              priorityNum: 0,
            );
            if (mounted) {
              setState(() => _isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã gửi lệnh in báo giá thành công!')),
              );
            }
          } catch (e) {
            if (mounted) {
              setState(() => _isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Lỗi khi gửi lệnh in: $e')),
              );
            }
          }
        }
        return;
      }

    // Helper to check for existing pending/printing jobs
    Future<Map<String, bool>> checkPrintJobStatus() async {
      if (invoiceId == null) return {'Pending': false, 'Printing': false, 'Completed': false};
      try {
        final jobs = await _apiService.getPrintJobs(invoiceId: invoiceId);
        return {
          'Pending': jobs.any((job) => job['printStatus'] == 'Pending'),
          'Printing': jobs.any((job) => job['printStatus'] == 'Printing'),
          'Completed': jobs.any((job) => job['printStatus'] == 'Completed'),
        };
      } catch (_) {
        return {'Pending': false, 'Printing': false, 'Completed': false};
      }
    }

    // For invoices, 4-checkbox multi-selection dialog
    bool checkA = true;
    bool checkB = true;
    bool checkC = true;
    bool checkDefault = false;

    final List<String>? selectedParts = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.print, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Tùy chọn in lại'),
            ],
          ),
          content: StatefulBuilder(
            builder: (builderContext, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chọn các liên cần in lại (sẽ tạo các lệnh in mới tương ứng):',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Liên A (Bản gốc)'),
                    value: checkA,
                    activeColor: colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setDialogState(() {
                        checkA = val ?? false;
                        if (checkA) {
                          checkDefault = false;
                        }
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('Liên B (Giao khách)'),
                    value: checkB,
                    activeColor: colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setDialogState(() {
                        checkB = val ?? false;
                        if (checkB) {
                          checkDefault = false;
                        }
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('Liên C (Lưu nội bộ)'),
                    value: checkC,
                    activeColor: colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setDialogState(() {
                        checkC = val ?? false;
                        if (checkC) {
                          checkDefault = false;
                        }
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('Không liên (Mặc định)'),
                    value: checkDefault,
                    activeColor: colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setDialogState(() {
                        checkDefault = val ?? false;
                        if (checkDefault) {
                          checkA = false;
                          checkB = false;
                          checkC = false;
                        }
                      });
                    },
                  ),
                  FutureBuilder<Map<String, bool>>(
                    future: checkPrintJobStatus(),
                    builder: (futureContext, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.5),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Đang kiểm tra hàng chờ in...',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }
                      
                      final statusMap = snapshot.data;
                      if (statusMap == null) return const SizedBox.shrink();

                      final hasPending = statusMap['Pending'] ?? false;
                      final hasPrinting = statusMap['Printing'] ?? false;
                      final hasCompleted = statusMap['Completed'] ?? false;

                      if (hasPending || hasPrinting || hasCompleted) {
                        String msg = '';
                        Color bannerColor = Colors.amber;
                        IconData bannerIcon = Icons.warning_amber_rounded;

                        if (hasPending) {
                          msg = 'Lưu ý: Có bản in của hóa đơn này đang chờ xử lý.';
                          bannerColor = Colors.orange;
                          bannerIcon = Icons.hourglass_empty;
                        } else if (hasPrinting) {
                          msg = 'Lưu ý: Hóa đơn này đang được tiến hành in.';
                          bannerColor = Colors.blue;
                          bannerIcon = Icons.print;
                        } else if (hasCompleted) {
                          msg = 'Thông báo: Hóa đơn này đã được in thành công trước đó.';
                          bannerColor = Colors.green;
                          bannerIcon = Icons.check_circle_outline;
                        }

                        return Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: bannerColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(bannerIcon, color: bannerColor, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  msg,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('HỦY'),
            ),
            StatefulBuilder(
              builder: (builderContext, setActionState) {
                final bool hasSelection = checkA || checkB || checkC || checkDefault;
                return ElevatedButton(
                  onPressed: hasSelection
                      ? () {
                          final List<String> list = [];
                          if (checkA) list.add('A');
                          if (checkB) list.add('B');
                          if (checkC) list.add('C');
                          if (checkDefault) list.add('Default');
                          Navigator.pop(dialogContext, list);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  child: const Text('XÁC NHẬN IN'),
                );
              },
            ),
          ],
        );
      },
    );

      if (selectedParts == null || selectedParts.isEmpty) return;

      setState(() => _isLoading = true);
      try {
        final bool isTriplicate = selectedParts.contains('A') &&
            selectedParts.contains('B') &&
            selectedParts.contains('C') &&
            selectedParts.length == 3;

        if (isTriplicate) {
          await _apiService.createPrintJob(
            invoiceId: invoiceId,
            printType: 'Triplicate',
            printPart: null,
            priorityNum: 0,
          );
        } else {
          for (final String part in selectedParts) {
            await _apiService.createPrintJob(
              invoiceId: invoiceId,
              printType: 'Original',
              printPart: part == 'Default' ? null : part,
              priorityNum: 0,
            );
          }
        }
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isTriplicate
                    ? 'Đã gửi lệnh in Liên 3 mới thành công!'
                    : 'Đã gửi các lệnh in mới thành công!'
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi khi gửi lệnh in: $e')),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isDialogOpen = false);
      }
    }
  }

  Widget _buildMetadataCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String status = _currentJob['printStatus']?.toString() ?? 'Pending';
    final int priority = (_currentJob['priorityNum'] as num?)?.toInt() ?? 0;
    final int retryCount = (_currentJob['retryCount'] as num?)?.toInt() ?? 0;

    final String? invoiceCode = _currentJob['invoiceCode']?.toString();
    final String? invoiceBuyer = _currentJob['invoiceBuyerName']?.toString();
    final String? priceListDesc = _currentJob['priceListDescription']?.toString();
    final String? priceListBuyer = _currentJob['priceListBuyerName']?.toString();

    final bool isInvoice = _currentJob['invoiceId'] != null;
    final String printType = _currentJob['printType']?.toString() ?? 'Original';
    final String printPart = _currentJob['printPart']?.toString() ?? 'Default';

    final String copyLabel;
    if (isInvoice) {
      if (printType == 'Original') {
        if (printPart == 'A') {
          copyLabel = 'Liên A (Bản gốc)';
        } else if (printPart == 'B') {
          copyLabel = 'Liên B (Giao khách)';
        } else if (printPart == 'C') {
          copyLabel = 'Liên C (Lưu nội bộ)';
        } else {
          copyLabel = 'Bản gốc (Không liên)';
        }
      } else if (printType == 'Triplicate') {
        copyLabel = 'Liên 3';
      } else {
        copyLabel = 'Báo giá';
      }
    } else {
      copyLabel = 'Báo giá';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Chi tiết lệnh in',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status, colorScheme).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getStatusText(status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(status, colorScheme),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              context,
              Icons.tag,
              'ID Lệnh in',
              _currentJob['printJobId']?.toString() ?? 'N/A',
            ),
            _buildDetailRow(
              context,
              isInvoice ? Icons.description : Icons.request_quote,
              isInvoice ? 'Mã hóa đơn' : 'Mô tả báo giá',
              isInvoice ? (invoiceCode ?? 'N/A') : (priceListDesc ?? 'N/A'),
            ),
            _buildDetailRow(
              context,
              Icons.person_outline,
              'Khách hàng',
              isInvoice ? (invoiceBuyer ?? 'Khách vãng lai') : (priceListBuyer ?? 'N/A'),
            ),
            _buildDetailRow(
              context,
              Icons.copy_all_outlined,
              'Phân loại liên',
              copyLabel,
            ),
            _buildDetailRow(
              context,
              Icons.schedule_outlined,
              'Thời gian tạo',
              _formatDateTime(_currentJob['createdAt']),
            ),
            if (_currentJob['updatedAt'] != null)
              _buildDetailRow(
                context,
                Icons.update_outlined,
                'Cập nhật cuối',
                _formatDateTime(_currentJob['updatedAt']),
              ),
            _buildDetailRow(
              context,
              Icons.bolt_outlined,
              'Mức ưu tiên',
              priority > 0 ? 'Ưu tiên cao ($priority)' : 'Thường',
              textColor: priority > 0 ? colorScheme.error : null,
            ),
            _buildDetailRow(
              context,
              Icons.refresh_outlined,
              'Số lần thử lại',
              '$retryCount lần',
            ),
            if (_currentJob['errorMessage'] != null && _currentJob['errorMessage'].toString().isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lỗi: ${_currentJob['errorMessage']}',
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildActionsArea(context, status, priority, retryCount),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    Color? textColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor ?? colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsArea(BuildContext context, String status, int priority, int retryCount) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (status == 'Failed')
          ElevatedButton.icon(
            onPressed: () => _updateStatus('Pending', retryCount: 0),
            icon: const Icon(Icons.replay_rounded, size: 16),
            label: const Text('THỬ LẠI'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        if (status == 'Cancelled' || status == 'Completed')
          ElevatedButton.icon(
            onPressed: _recreateJob,
            icon: const Icon(Icons.autorenew_rounded, size: 16),
            label: const Text('TẠO LẠI'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        if (status == 'Pending') ...[
          if (priority == 0) ...[
            OutlinedButton.icon(
              onPressed: () => _updatePriority(1),
              icon: const Icon(Icons.bolt, size: 16),
              label: const Text('ƯU TIÊN'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton.icon(
            onPressed: () => _updateStatus('Cancelled'),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('HỦY BỎ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 920;

    final isInvoice = _currentJob['invoiceId'] != null;
    final String? invoiceId = _currentJob['invoiceId']?.toString();
    final String? customerPriceListId = _currentJob['customerPriceListId']?.toString();
    final String printType = _currentJob['printType']?.toString() ?? 'Original';
    final String? printPart = _currentJob['printPart']?.toString();

    final String titleText = isInvoice
        ? 'Hoá đơn: ${_currentJob['invoiceCode'] ?? "N/A"}'
        : 'Báo giá';

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          IconButton(
            icon: Icon(isInvoice ? Icons.receipt_long_rounded : Icons.request_quote_rounded),
            onPressed: () {
              if (isInvoice) {
                Navigator.pushNamed(context, '/invoice_detail', arguments: invoiceId);
              } else if (customerPriceListId != null) {
                Navigator.pushNamed(context, '/edit_pricelist', arguments: customerPriceListId);
              }
            },
            tooltip: isInvoice ? 'Mở hóa đơn gốc' : 'Mở bảng báo giá gốc',
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: _showReprintDialog,
            tooltip: 'Gửi lệnh in lại',
          ),
        ],
      ),
      body: Stack(
        children: [
          isDesktop
              ? Row(
                  children: [
                    // Sidebar with metadata & controls
                    Container(
                      width: 380,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: _buildMetadataCard(context),
                      ),
                    ),
                    // PDF Preview occupying remaining space
                    Expanded(
                      child: Container(
                        color: colorScheme.surfaceContainerLowest,
                        padding: const EdgeInsets.all(24.0),
                        child: PrintJobPreviewWidget(
                          invoiceId: invoiceId,
                          customerPriceListId: customerPriceListId,
                          printType: printType,
                          printPart: printPart,
                          titleText: 'Xem trước bản in',
                          apiService: _apiService,
                          hidePreview: _isDialogOpen,
                          showCloseButton: false,
                          onPrintAction: _showReprintDialog,
                          pageSize: customerPriceListId != null ? 'A5' : null,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    // In mobile, PDF preview takes up the top part
                    Expanded(
                      child: Container(
                        color: colorScheme.surfaceContainerLowest,
                        padding: const EdgeInsets.all(12.0),
                        child: PrintJobPreviewWidget(
                          invoiceId: invoiceId,
                          customerPriceListId: customerPriceListId,
                          printType: printType,
                          printPart: printPart,
                          titleText: 'Xem trước bản in',
                          apiService: _apiService,
                          hidePreview: _isDialogOpen,
                          showCloseButton: false,
                          onPrintAction: _showReprintDialog,
                          pageSize: customerPriceListId != null ? 'A5' : null,
                        ),
                      ),
                    ),
                    // Metadata as a sliding panel/drawer at the bottom
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        border: Border(
                          top: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      child: ExpansionTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Thông tin lệnh in',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getStatusColor(_currentJob['printStatus']?.toString() ?? 'Pending', colorScheme).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getStatusText(_currentJob['printStatus']?.toString() ?? 'Pending'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _getStatusColor(_currentJob['printStatus']?.toString() ?? 'Pending', colorScheme),
                                ),
                              ),
                            ),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: _buildMetadataCard(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
      bottomNavigationBar: null,
    );
  }
}
