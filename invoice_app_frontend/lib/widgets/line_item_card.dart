import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LineItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final int index;
  final bool isPicked;

  const LineItemCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.index,
    this.isPicked = false,
  });

  @override
  Widget build(BuildContext context) {
    final subTotal = (item['subTotal'] as num?)?.toDouble() ?? 0;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isPicked ? 4 : 1,
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
      child: ListTile(
        onTap: onEdit,
        leading: CircleAvatar(
          backgroundColor: isPicked ? colorScheme.primary : colorScheme.secondaryContainer,
          foregroundColor: isPicked ? colorScheme.onPrimary : colorScheme.onSecondaryContainer,
          child: Text(
            '${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        title: Text(
          '${item['itemNameSnapshot']} (x${item['quantity']})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          '${item['unitNameSnapshot']} - ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(item['unitPriceCustom'])}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(subTotal),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPicked ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, size: 20, color: colorScheme.error),
              onPressed: onDelete,
              tooltip: 'Xóa dòng',
            ),
            const SizedBox(width: 4),
            ReorderableDragStartListener(
              index: index,
              child: IconButton(
                icon: Icon(Icons.drag_handle, color: colorScheme.onSurfaceVariant),
                onPressed: onTap,
                tooltip: 'Kéo hoặc bấm để di chuyển',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
