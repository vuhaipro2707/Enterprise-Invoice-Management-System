import 'package:flutter/material.dart';
import '../services/currency_formatter.dart';

class PriceItemCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final int index;
  final bool isPicked;
  final bool isHighlighted;

  const PriceItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.onEdit,
    this.onDelete,
    required this.index,
    this.isPicked = false,
    this.isHighlighted = false,
  });

  @override
  State<PriceItemCard> createState() => _PriceItemCardState();
}

class _PriceItemCardState extends State<PriceItemCard>
    with TickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _glowAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutBack,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutCubic,
      ),
    );

    if (widget.isHighlighted) {
      _entranceController.forward();
      _runGlowAnimation();
    } else {
      _entranceController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant PriceItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHighlighted && !oldWidget.isHighlighted) {
      _entranceController.forward(from: 0.0);
      _runGlowAnimation();
    }
  }

  void _runGlowAnimation() {
    _glowController.forward(from: 0).then((_) {
      if (mounted) _glowController.reverse();
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final customPrice = (widget.item['unitPriceCustom'] as num?)?.toDouble() ?? 0.0;
    final defaultPrice = (widget.item['unitPriceDefault'] as num?)?.toDouble() ?? 0.0;
    
    // Calculate difference if base price is available
    final diff = customPrice - defaultPrice;
    Color diffColor = Colors.green;
    String diffSign = '+';
    if (diff < 0) {
      diffColor = Colors.red;
      diffSign = '';
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              final glowOpacity = _glowAnimation.value;
              return Card(
                elevation: widget.isPicked ? 4 : (glowOpacity > 0 ? 4 : 1),
                margin: const EdgeInsets.only(bottom: 8),
                color: widget.isPicked
                    ? colorScheme.primaryContainer.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: widget.isPicked
                        ? colorScheme.primary
                        : glowOpacity > 0
                            ? colorScheme.primary.withValues(alpha: glowOpacity)
                            : colorScheme.outline.withValues(alpha: 0.1),
                    width: widget.isPicked
                        ? 2.5
                        : glowOpacity > 0
                            ? 2.0 * glowOpacity + 0.5
                            : 1.0,
                  ),
                ),
                child: child,
              );
            },
            child: InkWell(
              onTap: widget.onEdit,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Index CircleAvatar
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: widget.isPicked ? colorScheme.primary : colorScheme.secondaryContainer,
                      foregroundColor: widget.isPicked ? colorScheme.onPrimary : colorScheme.onSecondaryContainer,
                      child: Text(
                        '${widget.index + 1}',
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
                            widget.item['itemDefaultName'] ?? 'Mặt hàng không tên',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                                  widget.item['unitName'] ?? 'Cái',
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
                    
                    // Trailing: price on top, buttons below
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          CurrencyFormatter.formatVND(customPrice.toInt()),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: widget.isPicked ? colorScheme.primary : colorScheme.onSurface,
                            fontSize: 18,
                          ),
                        ),
                        if (widget.onDelete != null || widget.onTap != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.onDelete != null)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: colorScheme.error),
                                  onPressed: widget.onDelete,
                                  tooltip: 'Xóa giá',
                                ),
                              if (widget.onDelete != null && widget.onTap != null) const SizedBox(width: 12),
                              if (widget.onTap != null)
                                ReorderableDragStartListener(
                                  index: widget.index,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: Icon(Icons.drag_handle, color: colorScheme.onSurfaceVariant),
                                    onPressed: widget.onTap,
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
          ),
        ),
      ),
    );
  }
}
