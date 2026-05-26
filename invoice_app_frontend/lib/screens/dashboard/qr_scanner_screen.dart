import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isScanned = false;

  // Zoom controls
  double _zoomScale = 0.0;
  double _baseZoomScale = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.startsWith('ivid:')) {
        setState(() {
          _isScanned = true;
        });
        final String invoiceId = rawValue.replaceFirst('ivid:', '').trim();
        if (mounted) {
          Navigator.pop(context, invoiceId);
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final scanAreaSize = size.width * 0.7 < 280.0 ? size.width * 0.7 : 280.0;

    return Scaffold(
      backgroundColor: colorScheme.scrim,
      body: Stack(
        children: [
          // 1. Camera View (Pinch-to-zoom enabled on mobile)
          GestureDetector(
            onScaleStart: (details) {
              if (kIsWeb) return;
              _baseZoomScale = _zoomScale;
            },
            onScaleUpdate: (details) {
              if (kIsWeb) return;
              double newZoom = _baseZoomScale + (details.scale - 1.0) * 0.5;
              newZoom = newZoom.clamp(0.0, 1.0);
              try {
                _controller.setZoomScale(newZoom);
              } catch (e) {
                debugPrint('Camera zoom not supported: $e');
              }
              setState(() {
                _zoomScale = newZoom;
              });
            },
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),

          // 2. Translucent overlay with cutout
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              colorScheme.scrim.withValues(alpha: 0.8),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black, // Color for SrcOut masking
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: scanAreaSize,
                    height: scanAreaSize,
                    decoration: BoxDecoration(
                      color: Colors.red, // Any color to punch hole
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Custom Scanner Frame & Animated Laser Line
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: scanAreaSize,
              height: scanAreaSize,
              child: Stack(
                children: [
                  // Scanner Border Corners
                  CustomPaint(
                    size: Size(scanAreaSize, scanAreaSize),
                    painter: ScannerBorderPainter(color: colorScheme.primary),
                  ),

                  // Animated Laser Line
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (builderContext, child) {
                      final topOffset = _animation.value * (scanAreaSize - 4);
                      return Positioned(
                        top: topOffset,
                        left: 12,
                        right: 12,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary,
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                            color: colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 4. Instructions & Controls
          Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glassmorphic Zoom Slider (Mobile Only)
                if (!kIsWeb)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.zoom_out, color: Colors.white70, size: 18),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: colorScheme.primary,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: colorScheme.primary,
                              overlayColor: colorScheme.primary.withValues(alpha: 0.2),
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                            ),
                            child: Slider(
                              value: _zoomScale,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (value) {
                                try {
                                  _controller.setZoomScale(value);
                                } catch (e) {
                                  debugPrint('Camera zoom not supported: $e');
                                }
                                setState(() {
                                  _zoomScale = value;
                                });
                              },
                            ),
                          ),
                        ),
                        const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    'Đưa mã QR của hóa đơn vào khung để quét',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Flash Toggle
                    IconButton(
                      iconSize: 28,
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
                        foregroundColor: colorScheme.onSurface,
                        elevation: 4,
                      ),
                      icon: ValueListenableBuilder(
                        valueListenable: _controller,
                        builder: (builderContext, state, child) {
                          switch (state.torchState) {
                            case TorchState.on:
                              return const Icon(Icons.flash_on);
                            case TorchState.off:
                            default:
                              return const Icon(Icons.flash_off);
                          }
                        },
                      ),
                      onPressed: () => _controller.toggleTorch(),
                    ),
                    // Camera Switch
                    IconButton(
                      iconSize: 28,
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
                        foregroundColor: colorScheme.onSurface,
                        elevation: 4,
                      ),
                      icon: const Icon(Icons.flip_camera_android),
                      onPressed: () => _controller.switchCamera(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 5. Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: CircleAvatar(
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
              child: IconButton(
                icon: const Icon(Icons.close),
                color: colorScheme.onSurface,
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScannerBorderPainter extends CustomPainter {
  final Color color;

  ScannerBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 24.0;
    const radius = 16.0;

    final path = Path();

    // Top Left Corner
    path.moveTo(0, cornerLength);
    path.lineTo(0, radius);
    path.arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius));
    path.lineTo(cornerLength, 0);

    // Top Right Corner
    path.moveTo(size.width - cornerLength, 0);
    path.lineTo(size.width - radius, 0);
    path.arcToPoint(Offset(size.width, radius), radius: const Radius.circular(radius));
    path.lineTo(size.width, cornerLength);

    // Bottom Right Corner
    path.moveTo(size.width, size.height - cornerLength);
    path.lineTo(size.width, size.height - radius);
    path.arcToPoint(Offset(size.width - radius, size.height), radius: const Radius.circular(radius));
    path.lineTo(size.width - cornerLength, size.height);

    // Bottom Left Corner
    path.moveTo(cornerLength, size.height);
    path.lineTo(radius, size.height);
    path.arcToPoint(Offset(0, size.height - radius), radius: const Radius.circular(radius));
    path.lineTo(0, size.height - cornerLength);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
