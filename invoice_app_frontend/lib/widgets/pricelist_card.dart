import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PriceListCard extends StatelessWidget {
  final Map<String, dynamic> priceList;
  final VoidCallback onTap;
  final VoidCallback? onQuickInvoice;
  final VoidCallback? onExportQuote;

  const PriceListCard({
    super.key,
    required this.priceList,
    required this.onTap,
    this.onQuickInvoice,
    this.onExportQuote,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String description = priceList['description'] ?? '';
    final String? buyerName = priceList['buyerName'];
    final String? buyerCode = priceList['buyerCode'];

    final String createdAtRaw = priceList['createdAt'] ?? '';
    final String updatedAtRaw = priceList['updatedAt'] ?? '';

    String createdText = '';
    String updatedText = '';

    if (createdAtRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAtRaw).toLocal();
        createdText = DateFormat('dd/MM/yyyy HH:mm').format(dt);
      } catch (_) {}
    }

    if (updatedAtRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(updatedAtRaw).toLocal();
        updatedText = DateFormat('dd/MM/yyyy HH:mm').format(dt);
      } catch (_) {}
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      color: colorScheme.surfaceContainer,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    radius: 20,
                    child: Icon(
                      Icons.request_quote,
                      color: colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          buyerName ?? 'Khách lẻ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: buyerName != null
                                ? colorScheme.onSurface
                                : colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        if (buyerCode != null)
                          Text(
                            'Mã khách: $buyerCode',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (onQuickInvoice != null || onExportQuote != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onExportQuote != null)
                      OutlinedButton.icon(
                        onPressed: onExportQuote,
                        icon: Icon(Icons.ios_share_rounded, size: 16, color: colorScheme.secondary),
                        label: Text(
                          'Xuất báo giá',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.secondary,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          side: BorderSide(color: colorScheme.secondary.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    if (onQuickInvoice != null) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: onQuickInvoice,
                        icon: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.onPrimary),
                        label: const Text(
                          'Tạo nhanh',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Tạo: $createdText',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sửa: $updatedText',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                      textAlign: TextAlign.end,
                      maxLines: 1,
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
