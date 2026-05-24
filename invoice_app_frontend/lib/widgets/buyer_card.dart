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

    final details = <Widget>[];

    if (buyer['address'] != null && buyer['address'].toString().trim().isNotEmpty) {
      details.add(Text(
        'Địa chỉ: ${buyer['address']}', 
        style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13),
      ));
    }

    if (buyer['phoneNumber'] != null && buyer['phoneNumber'].toString().trim().isNotEmpty) {
      if (details.isNotEmpty) details.add(const SizedBox(height: 4));
      details.add(Text(
        'SĐT: ${buyer['phoneNumber']}', 
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    }

    if (buyer['email'] != null && buyer['email'].toString().trim().isNotEmpty) {
      if (details.isNotEmpty) details.add(const SizedBox(height: 2));
      details.add(Text(
        'Email: ${buyer['email']}', 
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    }

    if (buyer['idCardNumber'] != null && buyer['idCardNumber'].toString().trim().isNotEmpty) {
      if (details.isNotEmpty) details.add(const SizedBox(height: 2));
      details.add(Text(
        'CCCD: ${buyer['idCardNumber']}', 
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    }

    if (buyer['taxId'] != null && buyer['taxId'].toString().trim().isNotEmpty) {
      if (details.isNotEmpty) details.add(const SizedBox(height: 2));
      details.add(Text(
        'Mã số thuế: ${buyer['taxId']}', 
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    }

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
                    (buyer['buyerName'] != null && buyer['buyerName'].toString().isNotEmpty) 
                      ? buyer['buyerName'] 
                      : 'Không có tên',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mã: ${(buyer['buyerCode'] != null && buyer['buyerCode'].toString().isNotEmpty) ? buyer['buyerCode'] : 'Không có'}', 
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
        if (details.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...details,
        ],
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
