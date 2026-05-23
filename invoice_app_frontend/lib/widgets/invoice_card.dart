import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/currency_formatter.dart';

class InvoiceCard extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final VoidCallback onTap;

  const InvoiceCard({
    super.key,
    required this.invoice,
    required this.onTap,
  });

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

    final invoiceCode = invoice['invoice_code']?.toString() ?? 'N/A';
    final buyerName = invoice['buyer_name_snapshot']?.toString() ?? 'Khách vãng lai';
    final buyerCode = invoice['buyer_code']?.toString();
    final editStatus = invoice['edit_status'] == true;
    final paidLocked = invoice['paid_locked'] == true;
    final amount = invoice['total_amount'] ?? 0;
    final deviceName = invoice['device_name']?.toString() ?? '';
    
    final createdAtStr = _formatDateTime(invoice['created_at']);
    final updatedAtStr = _formatDateTime(invoice['updated_at']);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: editStatus
              ? Colors.orange.withValues(alpha: 0.5)
              : (paidLocked
                  ? colorScheme.outlineVariant.withValues(alpha: 0.3)
                  : Colors.blue.withValues(alpha: 0.5)),
          width: (editStatus || !paidLocked) ? 1.5 : 1,
        ),
      ),
      color: editStatus
          ? Color.alphaBlend(
              Colors.orange.withValues(alpha: 0.1),
              colorScheme.surfaceContainerLowest,
            )
          : (paidLocked
              ? colorScheme.surfaceContainer
              : Color.alphaBlend(
                  Colors.blue.withValues(alpha: 0.05),
                  colorScheme.surfaceContainer,
                )),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Code & Amount Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      invoiceCode,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatVND(amount),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Buyer Row
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      buyerCode != null && buyerCode.isNotEmpty
                          ? '[$buyerCode] $buyerName'
                          : buyerName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Created date
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 8),
                  Text(
                    'Khởi tạo lúc: $createdAtStr',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Updated date
              Row(
                children: [
                  Icon(Icons.update_outlined, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 8),
                  Text(
                    'Cập nhật lúc: $updatedAtStr',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Bottom Edit Status & Device info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        editStatus
                            ? Icons.edit_document
                            : (paidLocked
                                ? Icons.lock_outline
                                : Icons.check_circle_outline_rounded),
                        size: 14,
                        color: editStatus
                            ? Colors.orange
                            : (paidLocked ? Colors.green : Colors.blue),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        editStatus
                            ? 'Đang sửa'
                            : (paidLocked ? 'Hoàn thành' : 'Đã lưu'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: editStatus
                              ? Colors.orange
                              : (paidLocked ? Colors.green : Colors.blue),
                        ),
                      ),
                    ],
                  ),
                  if (editStatus && deviceName.isNotEmpty)
                    Flexible(
                      child: Text(
                        'Bởi: $deviceName',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.secondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
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
