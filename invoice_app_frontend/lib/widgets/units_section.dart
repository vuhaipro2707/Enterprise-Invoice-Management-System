import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/currency_formatter.dart';

class UnitsSection extends StatefulWidget {
  final List<Map<String, dynamic>> units;
  final List<String>? removedUnitIds;
  final bool readOnly;

  const UnitsSection({
    super.key,
    required this.units,
    this.removedUnitIds,
    this.readOnly = false,
  });

  @override
  State<UnitsSection> createState() => _UnitsSectionState();
}

class _UnitsSectionState extends State<UnitsSection> {
  final _formatter = NumberFormat.decimalPattern('vi_VN');

  TextEditingController _getNameController(Map<String, dynamic> unit) {
    if (unit['nameController'] == null) {
      unit['nameController'] = TextEditingController();
    }
    return unit['nameController'] as TextEditingController;
  }

  TextEditingController _getPriceController(Map<String, dynamic> unit) {
    if (unit['priceController'] == null) {
      unit['priceController'] = TextEditingController();
    }
    return unit['priceController'] as TextEditingController;
  }

  TextEditingController _getRatioController(Map<String, dynamic> unit) {
    if (unit['ratioController'] == null) {
      unit['ratioController'] = TextEditingController(text: '1');
    }
    return unit['ratioController'] as TextEditingController;
  }

  @override
  void initState() {
    super.initState();
    // If the units list is empty upon initialization, automatically add a base unit
    if (widget.units.isEmpty) {
      widget.units.add({
        'unitId': null,
        'nameController': TextEditingController(),
        'priceController': TextEditingController(),
        'ratioController': TextEditingController(text: '1'),
        'isBaseUnit': true,
      });
    }
  }

  void _calculatePricesFromBase() {
    final baseIndex = widget.units.indexWhere((u) => u['isBaseUnit'] == true);
    if (baseIndex == -1) return;
    
    final baseUnit = widget.units[baseIndex];
    final rawPrice = _getPriceController(baseUnit).text.replaceAll('.', '').trim();
    
    if (rawPrice.isEmpty) {
      setState(() {
        for (int i = 0; i < widget.units.length; i++) {
          if (i == baseIndex) continue;
          _getPriceController(widget.units[i]).clear();
        }
      });
      return;
    }
    
    final basePrice = int.tryParse(rawPrice) ?? 0;
    
    setState(() {
      for (int i = 0; i < widget.units.length; i++) {
        if (i == baseIndex) continue;
        
        final secondaryUnit = widget.units[i];
        final ratioStr = _getRatioController(secondaryUnit).text.trim();
        final ratio = int.tryParse(ratioStr) ?? 1;
        
        final secondaryPrice = basePrice * ratio;
        _getPriceController(secondaryUnit).text = _formatter.format(secondaryPrice);
      }
    });
  }

  void _calculatePricesFromSecondary(int index) {
    final baseIndex = widget.units.indexWhere((u) => u['isBaseUnit'] == true);
    if (baseIndex == -1 || baseIndex == index) return;
    
    final secondaryUnit = widget.units[index];
    final rawPrice = _getPriceController(secondaryUnit).text.replaceAll('.', '').trim();
    
    if (rawPrice.isEmpty) {
      setState(() {
        _getPriceController(widget.units[baseIndex]).clear();
        for (int i = 0; i < widget.units.length; i++) {
          if (i == baseIndex || i == index) continue;
          _getPriceController(widget.units[i]).clear();
        }
      });
      return;
    }
    
    final secondaryPrice = int.tryParse(rawPrice) ?? 0;
    final ratioStr = _getRatioController(secondaryUnit).text.trim();
    final ratio = int.tryParse(ratioStr) ?? 1;
    
    final basePrice = (secondaryPrice / (ratio > 0 ? ratio : 1)).round();
    
    setState(() {
      _getPriceController(widget.units[baseIndex]).text = _formatter.format(basePrice);
      
      for (int i = 0; i < widget.units.length; i++) {
        if (i == baseIndex || i == index) continue;
        
        final otherUnit = widget.units[i];
        final otherRatioStr = _getRatioController(otherUnit).text.trim();
        final otherRatio = int.tryParse(otherRatioStr) ?? 1;
        
        final otherPrice = basePrice * otherRatio;
        _getPriceController(otherUnit).text = _formatter.format(otherPrice);
      }
    });
  }

  void _calculatePricesFromRatioChange(int index) {
    final baseIndex = widget.units.indexWhere((u) => u['isBaseUnit'] == true);
    if (baseIndex == -1 || baseIndex == index) return;
    
    final baseUnit = widget.units[baseIndex];
    final rawBasePrice = _getPriceController(baseUnit).text.replaceAll('.', '').trim();
    if (rawBasePrice.isEmpty) return;
    
    final basePrice = int.tryParse(rawBasePrice) ?? 0;
    
    final secondaryUnit = widget.units[index];
    final ratioStr = _getRatioController(secondaryUnit).text.trim();
    final ratio = int.tryParse(ratioStr) ?? 1;
    
    final newPrice = basePrice * ratio;
    setState(() {
      _getPriceController(secondaryUnit).text = _formatter.format(newPrice);
    });
  }

  void _addUnit() {
    setState(() {
      final isFirst = widget.units.isEmpty;
      widget.units.add({
        'unitId': null,
        'nameController': TextEditingController(),
        'priceController': TextEditingController(),
        'ratioController': TextEditingController(text: '1'),
        'isBaseUnit': isFirst,
      });
    });
  }

  void _removeUnit(int index) {
    setState(() {
      final unitId = widget.units[index]['unitId'];
      if (unitId != null && widget.removedUnitIds != null) {
        widget.removedUnitIds!.add(unitId);
      }
      _getNameController(widget.units[index]).dispose();
      _getPriceController(widget.units[index]).dispose();
      _getRatioController(widget.units[index]).dispose();
      widget.units.removeAt(index);

      // Ensure we always have a base unit if units still remain
      if (widget.units.isNotEmpty) {
        widget.units[0]['isBaseUnit'] = true;
        _getRatioController(widget.units[0]).text = '1';
      }
    });
  }

  @override
  void dispose() {
    for (var unit in widget.units) {
      _getNameController(unit).dispose();
      _getPriceController(unit).dispose();
      _getRatioController(unit).dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseUnitName = widget.units.isNotEmpty ? _getNameController(widget.units[0]).text.trim() : '';
    final baseUnitDisplay = baseUnitName.isEmpty ? 'Đơn vị gốc' : baseUnitName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Đơn vị tính & Giá',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (!widget.readOnly)
              TextButton.icon(
                onPressed: _addUnit,
                icon: const Icon(Icons.add),
                label: const Text('Thêm đơn vị'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.units.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Bấm "Thêm đơn vị" để thêm giá bán (VD: Thùng, Lon, Cái)',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ...widget.units.asMap().entries.map((entry) {
          int index = entry.key;
          var unit = entry.value;
          bool isBase = unit['isBaseUnit'] ?? false;
          String unitName = _getNameController(unit).text.trim();

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isBase ? Icons.widgets_outlined : Icons.scale_outlined,
                            size: 20,
                            color: isBase
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isBase ? 'Đơn vị tính gốc' : 'Đơn vị tính quy đổi #$index',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isBase
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      if (isBase)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Đơn vị gốc (Base)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!widget.readOnly && (!isBase || widget.units.length == 1)) ...[
                        if (widget.units.length > 1 || !isBase)
                          IconButton(
                            onPressed: () => _removeUnit(index),
                            icon: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            tooltip: 'Xóa đơn vị',
                          ),
                      ] else if (!widget.readOnly) ...[
                        Tooltip(
                          message: 'Không thể xóa đơn vị gốc khi còn đơn vị khác',
                          child: IconButton(
                            onPressed: null,
                            icon: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Fields Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _getNameController(unit),
                          enabled: !widget.readOnly,
                          decoration: const InputDecoration(
                            labelText: 'Tên đơn vị *',
                            hintText: 'VD: Hộp, Thùng',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (value) => (value == null || value.isEmpty)
                              ? 'Nhập tên'
                              : null,
                          onChanged: (val) {
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (!isBase) ...[
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _getRatioController(unit),
                            enabled: !widget.readOnly,
                            decoration: const InputDecoration(
                              labelText: 'Tỷ lệ *',
                              hintText: 'VD: 24',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Nhập tỷ lệ';
                              final parsed = int.tryParse(value);
                              if (parsed == null || parsed <= 0) return 'Tỷ lệ > 0';
                              return null;
                            },
                            onChanged: (val) {
                              _calculatePricesFromRatioChange(index);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 4,
                        child: TextFormField(
                          controller: _getPriceController(unit),
                          enabled: !widget.readOnly,
                          decoration: const InputDecoration(
                            labelText: 'Giá mặc định (đ)',
                            hintText: 'Tự động tính',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          inputFormatters: [CurrencyInputFormatter()],
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            if (isBase) {
                              _calculatePricesFromBase();
                            } else {
                              _calculatePricesFromSecondary(index);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (!isBase) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        "= ${_getRatioController(unit).text} $baseUnitDisplay / ${unitName.isEmpty ? 'Đơn vị' : unitName}",
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        'Đơn vị cơ sở nhỏ nhất dùng làm mốc quy đổi giá',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
