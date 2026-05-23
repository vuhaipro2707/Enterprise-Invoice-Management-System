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

    final isDesktop = MediaQuery.of(context).size.width > 920;

    final topSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(Icons.person, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (buyer['buyer_name'] != null && buyer['buyer_name'].toString().isNotEmpty) 
                      ? buyer['buyer_name'] 
                      : 'Không có tên',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mã: ${(buyer['buyer_code'] != null && buyer['buyer_code'].toString().isNotEmpty) ? buyer['buyer_code'] : 'Không có'}', 
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.outline, size: 20),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Địa chỉ: ${(buyer['address'] != null && buyer['address'].toString().isNotEmpty) ? buyer['address'] : 'Không có'}', 
          style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          'SĐT: ${(buyer['phone_number'] != null && buyer['phone_number'].toString().isNotEmpty) ? buyer['phone_number'] : 'Không có'}', 
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          'CCCD: ${(buyer['id_card_number'] != null && buyer['id_card_number'].toString().isNotEmpty) ? buyer['id_card_number'] : 'Không có'}', 
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          'MST: ${(buyer['tax_id'] != null && buyer['tax_id'].toString().isNotEmpty) ? buyer['tax_id'] : 'Không có'}', 
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final bottomSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16, thickness: 0.5),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              Navigator.pushNamed(
                context,
                '/invoice_management',
                arguments: {'buyer': buyer},
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.receipt_long, size: 16),
            label: const Text(
              'Xem hóa đơn',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );

    return Card(
      margin: isDesktop ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      elevation: 1,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              topSection,
              bottomSection,
            ],
          ),
        ),
      ),
    );
  }
}
