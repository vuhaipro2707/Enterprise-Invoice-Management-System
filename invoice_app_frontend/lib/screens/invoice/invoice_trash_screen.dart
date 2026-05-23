import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';

class InvoiceTrashScreen extends StatefulWidget {
  const InvoiceTrashScreen({super.key});

  @override
  State<InvoiceTrashScreen> createState() => _InvoiceTrashScreenState();
}

class _InvoiceTrashScreenState extends State<InvoiceTrashScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _deletedInvoices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDeletedInvoices();
  }

  Future<void> _fetchDeletedInvoices() async {
    setState(() => _isLoading = true);
    try {
      final invoices = await _apiService.getDeletedInvoices();
      if (mounted) {
        setState(() {
          _deletedInvoices = invoices;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tải danh sách đã xóa: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 920;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thùng rác hóa đơn'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDeletedInvoices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _deletedInvoices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 64,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Thùng rác trống',
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.outline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : isDesktop
                  ? GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.0,
                      ),
                      itemCount: _deletedInvoices.length,
                      itemBuilder: (context, index) {
                        return _buildInvoiceCard(_deletedInvoices[index]);
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _deletedInvoices.length,
                      itemBuilder: (context, index) {
                        return _buildInvoiceCard(_deletedInvoices[index]);
                      },
                    ),
    );
  }

  Widget _buildInvoiceCard(Map<String, dynamic> invoice) {
    final colorScheme = Theme.of(context).colorScheme;
    final code = invoice['invoice_code'] ?? 'N/A';
    final buyerName = invoice['buyer_name_snapshot'] ?? 'Khách vãng lai';
    final totalAmount = invoice['total_amount'] ?? 0;
    final createdAt = _formatDateTime(invoice['created_at']);
    final editStatus = invoice['edit_status'] == true;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      color: editStatus
          ? Color.alphaBlend(
              Colors.orange.withValues(alpha: 0.1),
              colorScheme.surfaceContainerLowest,
            )
          : colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: editStatus
              ? Colors.orange.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: editStatus ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final result = await Navigator.pushNamed(
            context,
            '/invoice_detail',
            arguments: {
              'invoiceId': invoice['invoice_id'],
              'isDeleted': true,
            },
          );
          if (result == true) {
            _fetchDeletedInvoices();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    code,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatVND(totalAmount),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      buyerName,
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    'Khởi tạo: $createdAt',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ),
              if (MediaQuery.of(context).size.width > 920) const Spacer() else const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        editStatus ? Icons.edit_document : Icons.lock_outline,
                        size: 14,
                        color: editStatus ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        editStatus ? 'Đang sửa' : 'Hoàn thành',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: editStatus ? Colors.orange : Colors.green,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.restore_from_trash_rounded,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Chi tiết',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
