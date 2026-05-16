import 'package:flutter/material.dart';

class BuyerCard extends StatelessWidget {
  final Map<String, dynamic> buyer;
  final VoidCallback onTap;

  const BuyerCard({
    super.key,
    required this.buyer,
    required this.onTap,
  });

  @override
    Widget build(BuildContext context) {
      final colorScheme = Theme.of(context).colorScheme;
  
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(Icons.person, color: colorScheme.onPrimaryContainer),
          ),
          title: Text(
            (buyer['buyer_name'] != null && buyer['buyer_name'].toString().isNotEmpty) 
              ? buyer['buyer_name'] 
              : 'Không có tên',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text('Mã: ${(buyer['buyer_code'] != null && buyer['buyer_code'].toString().isNotEmpty) ? buyer['buyer_code'] : 'Không có'}', 
                   style: TextStyle(color: colorScheme.onSurfaceVariant)),
              Text('Địa chỉ: ${(buyer['address'] != null && buyer['address'].toString().isNotEmpty) ? buyer['address'] : 'Không có'}', 
                   style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8))),
              const SizedBox(height: 2),
              Text('SĐT: ${(buyer['phone_number'] != null && buyer['phone_number'].toString().isNotEmpty) ? buyer['phone_number'] : 'Không có'}', 
                   style: TextStyle(color: colorScheme.onSurfaceVariant)),
              Text('CCCD: ${(buyer['id_card_number'] != null && buyer['id_card_number'].toString().isNotEmpty) ? buyer['id_card_number'] : 'Không có'}', 
                   style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
    }
}
