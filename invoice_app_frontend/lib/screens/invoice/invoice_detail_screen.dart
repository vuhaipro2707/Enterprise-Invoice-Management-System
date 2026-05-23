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

  Future<void> _handleEditPress() async {
    final inv = _invoiceData;
    if (inv == null) return;

    // Helper to get string value safely
    String? getStringValueLocal(dynamic field) {
      if (field == null) return null;
      if (field is Map) return field['Valid'] == true ? field['String'].toString() : null;
      return field.toString();
    }

    final isEditing = inv['edit_status'] == true;
    final currentDeviceHoldingId = getStringValueLocal(inv['device_holding_id']);
    final deviceName = getStringValueLocal(inv['device_name']) ?? 'Thiết bị khác';

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
        Navigator.pushNamed(
          context,
          '/edit_invoice',
          arguments: _invoiceId,
        ).then((_) => _fetchInvoiceDetails());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể chuyển sang chế độ chỉnh sửa: $e')),
        );
      }
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
    final invoiceCode = inv['invoice_code']?.toString() ?? 'N/A';
    final buyerName = _getStringValue(inv['buyer_name_snapshot']) ?? 'Khách vãng lai';
    final buyerCode = _getStringValue(inv['buyer_code']);
    final address = _getStringValue(inv['address_snapshot']);
    final phoneNumber = _getStringValue(inv['phone_number_snapshot']);
    final taxIdSnapshot = _getStringValue(inv['tax_id_snapshot']);
    final lat = inv['lat_snapshot'] != null ? (inv['lat_snapshot'] as num).toDouble() : null;
    final lng = inv['lng_snapshot'] != null ? (inv['lng_snapshot'] as num).toDouble() : null;
    final totalAmount = inv['total_amount'] ?? 0;
    final editStatus = inv['edit_status'] == true;
    final deviceName = _getStringValue(inv['device_name']) ?? 'Không rõ';

    final createdAtStr = _formatDateTime(inv['created_at']);
    final updatedAtStr = _formatDateTime(inv['updated_at']);

    final lineItems = (inv['line_items'] as List?) ?? [];

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
                      'Tất cả các mặt hàng, đơn vị tính, đơn giá và số lượng sẽ được chép nguyên vẹn sang hóa đơn mới. Bạn có muốn tiếp tục?',
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
                      'item_id': itm['item_id'],
                      'unit_id': itm['unit_id'],
                      'item_name': itm['item_name_snapshot'],
                      'unit_name': itm['unit_name_snapshot'],
                      'quantity': itm['quantity'],
                      'price': itm['unit_price_custom'],
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
                    if (_getStringValue(inv['id_card_number_snapshot']) != null && _getStringValue(inv['id_card_number_snapshot'])!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.credit_card, 'Số CMND/CCCD', _getStringValue(inv['id_card_number_snapshot'])!, colorScheme),
                    ],
                    if (_getStringValue(inv['email_snapshot']) != null && _getStringValue(inv['email_snapshot'])!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.email, 'Email', _getStringValue(inv['email_snapshot'])!, colorScheme),
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
                  final name = item['item_name_snapshot']?.toString() ?? 'N/A';
                  final typeName = item['item_type_name_snapshot']?.toString() ?? '';
                  final unitName = item['unit_name_snapshot']?.toString() ?? 'cái';
                  final qty = item['quantity'] ?? 0;
                  final price = item['unit_price_custom'] ?? 0;
                  final subtotal = item['sub_total'] ?? (qty * price);

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
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                ),
                                if (typeName.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    typeName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$qty x ${CurrencyFormatter.formatVND(price)} / $unitName',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                    Text(
                                      CurrencyFormatter.formatVND(subtotal),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: colorScheme.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tổng cộng:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isDeleted ? colorScheme.primaryContainer : Colors.green,
                  foregroundColor: _isDeleted ? colorScheme.onPrimaryContainer : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isDeleted ? _restoreInvoice : _handleEditPress,
                icon: Icon(_isDeleted ? Icons.restore_rounded : Icons.edit),
                label: Text(
                  _isDeleted ? 'KHÔI PHỤC HÓA ĐƠN' : 'CHỈNH SỬA HÓA ĐƠN',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
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
