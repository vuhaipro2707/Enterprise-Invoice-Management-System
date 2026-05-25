import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final ApiService _apiService = ApiService();
  String? _invoiceId;
  Map<String, dynamic>? _invoiceData;
  bool _isLoading = true;
  bool _isDeleted = false;
  bool _areButtonsExpanded = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_invoiceId == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) {
        _invoiceId = args;
      } else if (args is Map<String, dynamic>) {
        _invoiceId = args['invoiceId']?.toString();
        _isDeleted = args['isDeleted'] == true;
      }
      if (_invoiceId != null) {
        _fetchInvoiceDetails();
      }
    }
  }

  Future<void> _fetchInvoiceDetails() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getInvoice(_invoiceId!);
      if (mounted) {
        setState(() {
          _invoiceData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải thông tin: $e')),
        );
      }
    }
  }

  Future<void> _restoreInvoice() async {
    setState(() => _isLoading = true);
    try {
      await _apiService.restoreInvoice(_invoiceId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Khôi phục hóa đơn thành công')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi khôi phục hóa đơn: $e')),
        );
      }
    }
  }

  Future<void> _deleteInvoice() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: const Text(
            'Bạn có chắc chắn muốn xóa hóa đơn này không? Bạn có thể khôi phục lại từ Thùng rác.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              child: const Text('XÓA'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _apiService.deleteInvoice(_invoiceId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xóa hóa đơn thành công')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xóa hóa đơn: $e')),
        );
      }
    }
  }

  Future<void> _lockInvoice() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Xác nhận chốt & khóa'),
          content: const Text(
            'Hành động này sẽ chốt hóa đơn hoàn chỉnh và KHÓA vĩnh viễn. '
            'Bạn sẽ KHÔNG THỂ chỉnh sửa hay xóa hóa đơn này nữa. Bạn có chắc chắn không?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('KHÓA NGAY'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _apiService.lockInvoice(_invoiceId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã chốt và khóa hóa đơn thành công!')),
        );
        _fetchInvoiceDetails();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi khóa hóa đơn: $e')),
        );
      }
    }
  }

  Future<void> _handleEditPress() async {
    final inv = _invoiceData;
    if (inv == null) return;

    // Helper to get string value safely
    String? getStringValueLocal(dynamic field) {
      if (field == null) return null;
      if (field is Map) return field['Valid'] == true ? field['String'].toString() : null;
      return field.toString();
    }

    final isEditing = inv['editStatus'] == true;
    final currentDeviceHoldingId = getStringValueLocal(inv['deviceHoldingId']);
    final deviceName = getStringValueLocal(inv['deviceName']) ?? 'Thiết bị khác';

    // Show warning if invoice is being edited by another device
    if (isEditing && currentDeviceHoldingId != null && currentDeviceHoldingId != _apiService.deviceId) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Cảnh báo chiếm quyền'),
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
    } else {
      // For finalized invoices or invoices we own, ask for a quick confirmation to unlock editing
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit_note, color: Colors.blue),
              SizedBox(width: 8),
              Text('Mở khóa chỉnh sửa'),
            ],
          ),
          content: const Text(
            'Hóa đơn này đã hoàn thành. Bạn có muốn chuyển sang chế độ chỉnh sửa không?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('QUAY LẠI'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('CHỈNH SỬA'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      // Lock / Take turn on invoice
      await _apiService.takeTurn(_invoiceId!);
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/edit_invoice',
          arguments: _invoiceId,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể chuyển sang chế độ chỉnh sửa: $e')),
        );
      }
    }
  }

  Future<void> _showPrintOptionsDialog() async {
    // Helper to check for existing pending/printing jobs
    Future<Map<String, bool>> checkPrintJobStatus() async {
      if (_invoiceId == null) return {'Pending': false, 'Printing': false, 'Completed': false};
      try {
        final jobs = await _apiService.getPrintJobs(invoiceId: _invoiceId);
        return {
          'Pending': jobs.any((job) => job['printStatus'] == 'Pending'),
          'Printing': jobs.any((job) => job['printStatus'] == 'Printing'),
          'Completed': jobs.any((job) => job['printStatus'] == 'Completed'),
        };
      } catch (_) {
        return {'Pending': false, 'Printing': false, 'Completed': false};
      }
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.print, color: Colors.teal),
              SizedBox(width: 8),
              Text('In hóa đơn'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bạn có chắc chắn muốn đưa hóa đơn này vào hàng chờ in không?',
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
                                color: Theme.of(futureContext).colorScheme.onSurface,
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('HỦY'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false), // false means 1 copy
              child: const Text('IN 1 BẢN (GỐC)'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true), // true means 3 copies
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('IN 3 BẢN (LIÊN BA)'),
            ),
          ],
        );
      },
    );

    if (confirm == null) return;

    final String printType = confirm ? 'Triplicate' : 'Original';

    setState(() => _isLoading = true);
    try {
      await _apiService.createPrintJob(
        invoiceId: _invoiceId!,
        printType: printType,
        priorityNum: 0,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã đưa hóa đơn vào hàng chờ in thành công!')),
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

  void _navigateToPrintQueue() {
    if (_invoiceId != null) {
      Navigator.pushNamed(
        context,
        '/print_management',
        arguments: {'invoiceId': _invoiceId},
      );
    }
  }

  String _formatDateTime(dynamic timestampStr) {
    if (timestampStr == null) return 'N/A';
    try {
      final date = DateTime.parse(timestampStr.toString());
      return DateFormat('HH:mm dd/MM/yyyy').format(date.toLocal());
    } catch (_) {
      return timestampStr.toString();
    }
  }

  String? _getStringValue(dynamic field) {
    if (field == null) return null;
    if (field is Map) return field['Valid'] == true ? field['String'].toString() : null;
    return field.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chi tiết hóa đơn')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_invoiceData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chi tiết hóa đơn')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              const Text('Không tìm thấy dữ liệu hóa đơn'),
            ],
          ),
        ),
      );
    }

    final inv = _invoiceData!;
    final invoiceCode = inv['invoiceCode']?.toString() ?? 'N/A';
    final buyerName = _getStringValue(inv['buyerNameSnapshot']) ?? 'Khách vãng lai';
    final buyerCode = _getStringValue(inv['buyerCode']);
    final address = _getStringValue(inv['addressSnapshot']);
    final phoneNumber = _getStringValue(inv['phoneNumberSnapshot']);
    final taxIdSnapshot = _getStringValue(inv['taxIdSnapshot']);
    final lat = inv['latSnapshot'] != null ? (inv['latSnapshot'] as num).toDouble() : null;
    final lng = inv['lngSnapshot'] != null ? (inv['lngSnapshot'] as num).toDouble() : null;
    final totalAmount = inv['totalAmount'] ?? 0;
    final editStatus = inv['editStatus'] == true;
    final paidLocked = inv['paidLocked'] == true;
    final deviceName = _getStringValue(inv['deviceName']) ?? 'Không rõ';

    final createdAtStr = _formatDateTime(inv['createdAt']);
    final updatedAtStr = _formatDateTime(inv['updatedAt']);

    final lineItems = (inv['lineItems'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isDeleted ? 'Hóa đơn $invoiceCode (Đã xóa)' : 'Hóa đơn $invoiceCode'),
        actions: [
          if (_isDeleted) ...[
            IconButton(
              icon: const Icon(Icons.restore_rounded),
              onPressed: _restoreInvoice,
              tooltip: 'Khôi phục',
            ),
          ] else ...[
            if (!paidLocked)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _deleteInvoice,
                tooltip: 'Xóa hóa đơn',
              ),
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Tạo bản sao hóa đơn'),
                      ],
                    ),
                    content: const Text(
                      'Tất cả các mặt hàng, đơn vị tính, đơn giá và số lượng sẽ được chép nguyên vẹn sang hóa đơn mới. Bạn có muốn chọn khách hàng khác không?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('HỦY'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('TIẾP TỤC'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  final clonedItems = lineItems.map((itm) {
                    return {
                      'itemId': itm['itemId'],
                      'unitId': itm['unitId'],
                      'itemNameSnapshot': itm['itemNameSnapshot'],
                      'unitNameSnapshot': itm['unitNameSnapshot'],
                      'quantity': itm['quantity'],
                      'unitPriceCustom': itm['unitPriceCustom'],
                    };
                  }).toList();

                  navigator.pushReplacementNamed(
                    '/create_invoice',
                    arguments: {
                      'cloned_items': clonedItems,
                    },
                  );
                }
              },
              tooltip: 'Tạo bản sao',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchInvoiceDetails,
              tooltip: 'Làm mới',
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // General Info Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          invoiceCode,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: editStatus
                                ? Colors.orange.withValues(alpha: 0.15)
                                : Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                editStatus ? Icons.edit_document : Icons.check_circle_outline,
                                size: 14,
                                color: editStatus ? Colors.orange : Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                editStatus ? 'Đang sửa' : 'Hoàn thành',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: editStatus ? Colors.orange : Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildMetaRow(Icons.calendar_today_outlined, 'Khởi tạo lúc', createdAtStr, colorScheme),
                    const SizedBox(height: 8),
                    _buildMetaRow(Icons.update_outlined, 'Cập nhật lúc', updatedAtStr, colorScheme),
                    const SizedBox(height: 8),
                    _buildMetaRow(Icons.devices, 'Thiết bị lưu hóa đơn', deviceName, colorScheme),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Customer Info Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thông tin khách hàng',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      Icons.person,
                      'Tên khách hàng',
                      buyerCode != null && buyerCode.isNotEmpty
                          ? '[$buyerCode] $buyerName'
                          : buyerName,
                      colorScheme,
                    ),
                    if (taxIdSnapshot != null && taxIdSnapshot.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.receipt_long, 'Mã số thuế', taxIdSnapshot, colorScheme),
                    ],
                    if (_getStringValue(inv['idCardNumberSnapshot']) != null && _getStringValue(inv['idCardNumberSnapshot'])!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.credit_card, 'Số CMND/CCCD', _getStringValue(inv['idCardNumberSnapshot'])!, colorScheme),
                    ],
                    if (_getStringValue(inv['emailSnapshot']) != null && _getStringValue(inv['emailSnapshot'])!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.email, 'Email', _getStringValue(inv['emailSnapshot'])!, colorScheme),
                    ],
                    if (phoneNumber != null && phoneNumber.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.phone, 'Số điện thoại', phoneNumber, colorScheme),
                    ],
                    if (address != null && address.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.location_on, 'Địa chỉ', address, colorScheme),
                    ],
                    if (lat != null && lng != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        Icons.map,
                        'Tọa độ (Lat / Lng)',
                        '${lat.toStringAsFixed(6)} / ${lng.toStringAsFixed(6)}',
                        colorScheme,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Products Card
            Text(
              'Danh mục sản phẩm / Dịch vụ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            if (lineItems.isEmpty)
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: Center(
                    child: Text('Hóa đơn này chưa có sản phẩm nào.'),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: lineItems.length,
                itemBuilder: (context, index) {
                  final item = lineItems[index];
                  final name = item['itemNameSnapshot']?.toString() ?? 'N/A';
                  final unitName = item['unitNameSnapshot']?.toString() ?? 'cái';
                  final qty = item['quantity'] ?? 0;
                  final price = item['unitPriceCustom'] ?? 0;
                  final subtotal = item['subTotal'] ?? (qty * price);

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.shopping_bag, color: colorScheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  softWrap: true,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '$qty x ${CurrencyFormatter.formatVND(price)} / $unitName',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                CurrencyFormatter.formatVND(subtotal),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: colorScheme.secondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, -3),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Tổng cộng:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _areButtonsExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    color: colorScheme.primary,
                  ),
                  tooltip: _areButtonsExpanded ? 'Ẩn bảng nút' : 'Hiện bảng nút',
                  onPressed: () {
                    setState(() {
                      _areButtonsExpanded = !_areButtonsExpanded;
                    });
                  },
                ),
                const Spacer(),
                Text(
                  CurrencyFormatter.formatVND(totalAmount),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  if (paidLocked) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified_user_rounded, color: Colors.green),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'HÓA ĐƠN ĐÃ ĐƯỢC CHỐT & KHÓA VĨNH VIỄN',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _showPrintOptionsDialog,
                              icon: const Icon(Icons.print),
                              label: const Text(
                                'IN HÓA ĐƠN',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.teal,
                                side: const BorderSide(color: Colors.teal),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _navigateToPrintQueue,
                              icon: const Icon(Icons.playlist_play),
                              label: const Text(
                                'HÀNG CHỜ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_isDeleted) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _restoreInvoice,
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text(
                          'KHÔI PHỤC HÓA ĐƠN',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _lockInvoice,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text(
                          'XÁC NHẬN HOÀN THÀNH & KHÓA HÓA ĐƠN',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                          side: const BorderSide(color: Colors.green),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _handleEditPress,
                        icon: const Icon(Icons.edit),
                        label: const Text(
                          'CHỈNH SỬA HÓA ĐƠN',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.teal,
                                side: const BorderSide(color: Colors.teal),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _showPrintOptionsDialog,
                              icon: const Icon(Icons.print),
                              label: const Text(
                                'IN HÓA ĐƠN',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.teal,
                                side: const BorderSide(color: Colors.teal),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _navigateToPrintQueue,
                              icon: const Icon(Icons.playlist_play),
                              label: const Text(
                                'HÀNG CHỜ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: _areButtonsExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 250),
              sizeCurve: Curves.easeInOut,
              firstCurve: Curves.easeInOut,
              secondCurve: Curves.easeInOut,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(IconData icon, String label, String value, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.outline),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 13, color: colorScheme.outline),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
