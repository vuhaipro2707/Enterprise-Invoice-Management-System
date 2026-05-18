import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EditingInvoiceCard extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const EditingInvoiceCard({
    super.key,
    required this.invoice,
    required this.onTap,
    required this.colorScheme,
  });

  String? _getStringValue(dynamic field) {
    if (field == null) return null;
    if (field is Map) return field['Valid'] == true ? field['String'].toString() : null;
    return field.toString();
  }

  String? _getTimestamp(dynamic field) {
    if (field == null) return null;
    if (field is Map) return field['Valid'] == true ? field['Time'].toString() : null;
    return field.toString();
  }

  @override
  Widget build(BuildContext context) {
    final deviceName = _getStringValue(invoice['device_name']) ?? 'Không rõ';
    final buyerName = _getStringValue(invoice['buyer_name_snapshot']) ?? 'K.Hàng vãng lai';
    final address = _getStringValue(invoice['address_snapshot']);
    final phoneNumber = _getStringValue(invoice['phone_number_snapshot']);
    final dateStr = _getTimestamp(invoice['updated_at']);

    String timeStr = '--:--';
    if (dateStr != null) {
      try {
        final date = DateTime.parse(dateStr);
        timeStr = DateFormat('HH:mm dd/MM').format(date.toLocal());
      } catch (_) {}
    }

    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Card(
        elevation: 3,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        invoice['invoice_code'] ?? 'N/A',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: colorScheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        buyerName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (address != null && address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 14, color: colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          address,
                          style: TextStyle(fontSize: 12, color: colorScheme.outline),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (phoneNumber != null && phoneNumber.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.phone, size: 14, color: colorScheme.outline),
                      const SizedBox(width: 8),
                      Text(
                        phoneNumber,
                        style: TextStyle(fontSize: 12, color: colorScheme.outline),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                const Divider(height: 16),
                Row(
                  children: [
                    Icon(Icons.devices, size: 14, color: colorScheme.secondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        deviceName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.secondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
