import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LineItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const LineItemCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final subTotal = (item['sub_total'] as num?)?.toDouble() ?? 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        title: Text('${item['item_name_snapshot']} (x${item['quantity']})'),
        subtitle: Text(
          '${item['unit_name_snapshot']} - ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(item['unit_price_custom'])}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(subTotal),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            const ReorderableDragStartListener(
              index: 0, // Sẽ được override bởi ReorderableListView
              child: Icon(Icons.drag_handle, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
