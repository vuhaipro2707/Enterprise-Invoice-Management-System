import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PrintJobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final Function(String jobId, String status, {int? retryCount}) onUpdateStatus;
  final Function(String jobId, int priority) onUpdatePriority;
  final Function(Map<String, dynamic> job) onRecreateJob;

  const PrintJobCard({
    super.key,
    required this.job,
    required this.onUpdateStatus,
    required this.onUpdatePriority,
    required this.onRecreateJob,
  });

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String jobId = job['printJobId']?.toString() ?? '';
    final String status = job['printStatus']?.toString() ?? 'Pending';
    final String printType = job['printType']?.toString() ?? 'Original';
    final int priority = (job['priorityNum'] as num?)?.toInt() ?? 0;
    final int retryCount = (job['retryCount'] as num?)?.toInt() ?? 0;

    final String? invoiceCode = job['invoiceCode']?.toString();
    final String? invoiceBuyer = job['invoiceBuyerName']?.toString();
    final String? priceListDesc = job['priceListDescription']?.toString();
    final String? priceListBuyer = job['priceListBuyerName']?.toString();

    final bool isInvoice = job['invoiceId'] != null;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Source & Priority & Retries / Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isInvoice ? colorScheme.error : Colors.teal).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isInvoice ? Icons.description : Icons.request_quote,
                            size: 14,
                            color: isInvoice ? colorScheme.error : Colors.teal,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isInvoice ? 'Hóa đơn' : 'Báo giá',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isInvoice ? colorScheme.error : Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (priority > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.error.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt,
                              size: 11,
                              color: colorScheme.error,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'ƯU TIÊN',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (retryCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.refresh,
                              size: 11,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Thử lại: $retryCount',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status, colorScheme).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getStatusText(status),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(status, colorScheme),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Row 2: left accent color bar & details
            Row(
              children: [
                Container(
                  width: 4,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isInvoice ? colorScheme.error : Colors.teal,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isInvoice
                            ? 'Mã: ${invoiceCode ?? "N/A"}'
                            : 'Nội dung: ${priceListDesc ?? "N/A"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isInvoice
                            ? 'Khách: ${invoiceBuyer ?? "Khách vãng lai"}'
                            : 'Khách: ${priceListBuyer ?? "Không rõ"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 0.5),
            const SizedBox(height: 8),
            // Row 3: Meta info
            Row(
              children: [
                Icon(
                  Icons.print_outlined,
                  size: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '${printType == 'Original' ? "1 bản" : "3 bản"}  •  ${_formatDateTime(job['createdAt'])}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            // Row 4: Actions (Rendered conditionally below metadata)
            if (status == 'Failed' || status == 'Pending' || status == 'Cancelled') ...[
              const SizedBox(height: 8),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status == 'Failed')
                    TextButton.icon(
                      onPressed: () => onUpdateStatus(jobId, 'Pending', retryCount: 0),
                      icon: const Icon(Icons.replay_rounded, size: 14),
                      label: const Text('THỬ LẠI'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  if (status == 'Cancelled')
                    TextButton.icon(
                      onPressed: () => onRecreateJob(job),
                      icon: const Icon(Icons.autorenew_rounded, size: 14),
                      label: const Text('TẠO LẠI'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  if (status == 'Pending') ...[
                    if (priority == 0) ...[
                      TextButton.icon(
                        onPressed: () => onUpdatePriority(jobId, 1),
                        icon: const Icon(Icons.bolt, size: 14),
                        label: const Text('ƯU TIÊN'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    TextButton.icon(
                      onPressed: () => onUpdateStatus(jobId, 'Cancelled'),
                      icon: const Icon(Icons.cancel_outlined, size: 14),
                      label: const Text('HỦY BỎ'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
