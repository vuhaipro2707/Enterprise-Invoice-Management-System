import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PriceListCard extends StatelessWidget {
  final Map<String, dynamic> priceList;
  final VoidCallback onTap;
  final VoidCallback? onQuickInvoice;

  const PriceListCard({
    super.key,
    required this.priceList,
    required this.onTap,
    this.onQuickInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String description = priceList['description'] ?? '';
    final String? buyerName = priceList['buyer_name'];
    final String? buyerCode = priceList['buyer_code'];

    final String createdAtRaw = priceList['created_at'] ?? '';
    final String updatedAtRaw = priceList['updated_at'] ?? '';

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
                  if (onQuickInvoice != null) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Tạo hóa đơn nhanh',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onQuickInvoice,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.primary.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.bolt_rounded,
                                  size: 14,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Tạo nhanh',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
