import 'package:flutter/material.dart';
import '../services/currency_formatter.dart';

class PriceItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final int index;
  final bool isPicked;

  const PriceItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.onEdit,
    this.onDelete,
    required this.index,
    this.isPicked = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final customPrice = (item['unitPriceCustom'] as num?)?.toDouble() ?? 0.0;
    final defaultPrice = (item['unitPriceDefault'] as num?)?.toDouble() ?? 0.0;
    
    // Calculate difference if base price is available
    final diff = customPrice - defaultPrice;
    Color diffColor = Colors.green;
    String diffSign = '+';
    if (diff < 0) {
      diffColor = Colors.red;
      diffSign = '';
    }

    return Card(
      elevation: isPicked ? 4 : 1,
      margin: const EdgeInsets.only(bottom: 8),
      color: isPicked 
          ? colorScheme.primaryContainer.withValues(alpha: 0.15) 
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPicked 
              ? colorScheme.primary 
              : colorScheme.outline.withValues(alpha: 0.1),
          width: isPicked ? 2.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Index CircleAvatar
              CircleAvatar(
                radius: 18,
                backgroundColor: isPicked ? colorScheme.primary : colorScheme.secondaryContainer,
                foregroundColor: isPicked ? colorScheme.onPrimary : colorScheme.onSecondaryContainer,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),
              
              // Title and Subtitle in Expanded
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item['itemDefaultName'] ?? 'Mặt hàng không tên',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item['unitName'] ?? 'Cái',
                            style: TextStyle(
                              color: colorScheme.onSecondaryContainer,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (defaultPrice > 0)
                          Text(
                            'Giá gốc: ${CurrencyFormatter.formatVND(defaultPrice.toInt())}',
                            style: TextStyle(fontSize: 12, color: colorScheme.outline),
                          ),
                      ],
                    ),
                    if (defaultPrice > 0 && diff != 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Chênh lệch: $diffSign${CurrencyFormatter.formatVND(diff.toInt())}',
                        style: TextStyle(
                          fontSize: 11,
                          color: diffColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              
              // Trailing Price and Actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    CurrencyFormatter.formatVND(customPrice.toInt()),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isPicked ? colorScheme.primary : colorScheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
                  if (onDelete != null || onTap != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onDelete != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.delete_outline_rounded, size: 20, color: colorScheme.error),
                            onPressed: onDelete,
                            tooltip: 'Xóa giá',
                          ),
                        if (onDelete != null && onTap != null) const SizedBox(width: 12),
                        if (onTap != null)
                          ReorderableDragStartListener(
                            index: index,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(Icons.drag_handle, color: colorScheme.onSurfaceVariant),
                              onPressed: onTap,
                              tooltip: 'Kéo hoặc bấm để di chuyển',
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
