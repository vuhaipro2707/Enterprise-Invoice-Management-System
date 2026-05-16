import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final List<dynamic> types;
  final VoidCallback onTap;

  const ItemCard({
    super.key,
    required this.item,
    required this.types,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // Xử lý danh sách tên khác vì API đã thay đổi cấu trúc sang List<Map>
    final rawOtherNames = item['item_other_names'] as List? ?? [];
    final otherNamesStr = rawOtherNames.map((e) {
      if (e is String) return e;
      if (e is Map) return e['name_string'] ?? '';
      return '';
    }).where((s) => s.isNotEmpty).join(', ');

    final units = (item['units'] as List?) ?? [];
    
    // Tìm tên type từ list types đã fetch ở trên frontend
    String typeName = 'Chưa phân loại';
    if (item['type_id'] != null) {
      final typeMatch = types.firstWhere(
        (t) => t['type_id'] == item['type_id'],
        orElse: () => null,
      );
      if (typeMatch != null) {
        typeName = typeMatch['type_name'];
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['item_default_name'] ?? 'Không tên',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            typeName,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colorScheme.outline),
                ],
              ),
              const SizedBox(height: 12),
              if (otherNamesStr.isNotEmpty) ...[
                Text(
                  'Tên khác: $otherNamesStr',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 8),
              ],
              if (units.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: units.map((u) {
                    final name = u['unit_name'] ?? '';
                    final price = u['unit_price_default'] ?? 0;
                    final formattedPrice = NumberFormat.decimalPattern('vi_VN').format(price);
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onTertiaryContainer,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$formattedPriceđ',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
