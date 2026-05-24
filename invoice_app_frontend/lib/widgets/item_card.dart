import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ItemCard extends StatefulWidget {
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
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // Xử lý danh sách tên khác vì API đã thay đổi cấu trúc sang List<Map>
    final rawOtherNames = widget.item['itemOtherNames'] as List? ?? [];
    final otherNamesStr = rawOtherNames.map((e) {
      if (e is String) return e;
      if (e is Map) return e['nameString'] ?? '';
      return '';
    }).where((s) => s.isNotEmpty).join(', ');

    final units = (widget.item['units'] as List?) ?? [];
    
    // Tìm tên type từ list types đã fetch ở trên frontend
    String typeName = 'Chưa phân loại';
    if (widget.item['typeId'] != null) {
      final typeMatch = widget.types.firstWhere(
        (t) => t['typeId'] == widget.item['typeId'],
        orElse: () => null,
      );
      if (typeMatch != null) {
        typeName = typeMatch['typeName'];
      }
    }

    final isDesktop = MediaQuery.of(context).size.width > 920;

    final topSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          widget.item['itemDefaultName'] ?? 'Không tên',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Sao chép tên mặt hàng',
                        icon: const Icon(Icons.copy_all_rounded, size: 20),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.4),
                          minimumSize: const Size(36, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        color: colorScheme.primary,
                        onPressed: () async {
                          final name = widget.item['itemDefaultName'] ?? '';
                          if (name.isNotEmpty) {
                            final scaffold = ScaffoldMessenger.of(context);
                            final inverseSurf = colorScheme.inverseSurface;
                            final onInverseSurf = colorScheme.onInverseSurface;
                            await Clipboard.setData(ClipboardData(text: name));
                            if (mounted) {
                              scaffold.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Đã sao chép: $name',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: onInverseSurf),
                                  ),
                                  backgroundColor: inverseSurf,
                                  duration: const Duration(milliseconds: 800),
                                  behavior: SnackBarBehavior.floating,
                                  width: 280,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ],
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
          Builder(
            builder: (BuildContext builderContext) {
              final useCarousel = isDesktop && units.length > 2;
              if (useCarousel) {
                final totalPages = (units.length / 2).ceil();
                final visibleUnits = units.sublist(
                  _currentPage * 2,
                  min((_currentPage + 1) * 2, units.length),
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: visibleUnits.map((u) {
                              final name = u['unitName'] ?? '';
                              final price = u['unitPriceDefault'] ?? 0;
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
                        ),
                        const SizedBox(width: 8),
                        // Carousel controls
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _currentPage > 0
                                  ? () {
                                      setState(() {
                                        _currentPage--;
                                      });
                                    }
                                  : null,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_currentPage + 1}/$totalPages',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.chevron_right, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _currentPage < totalPages - 1
                                  ? () {
                                      setState(() {
                                        _currentPage++;
                                      });
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                );
              } else {
                // Standard Wrap layout
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: units.map((u) {
                    final name = u['unitName'] ?? '';
                    final price = u['unitPriceDefault'] ?? 0;
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
                );
              }
            },
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
                arguments: {'item': widget.item},
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
      margin: isDesktop ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: widget.onTap,
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
