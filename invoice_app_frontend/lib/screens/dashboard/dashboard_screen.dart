import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../services/api_service.dart';
import '../../services/theme_provider.dart';
import '../../widgets/editing_invoice_card.dart';
import '../../main.dart' show routeObserver;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with RouteAware {
  final ApiService _apiService = ApiService();
  List<dynamic> _editingInvoices = [];
  bool _isLoadingInvoices = false;
  bool _isOnline = true;
  final ScrollController _scrollController = ScrollController();
  Timer? _refreshTimer;
  bool _hasCheckedUpdate = false;

  @override
  void initState() {
    super.initState();
    _fetchEditingInvoices();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didPush() {
    super.didPush();
    _fetchEditingInvoices();
    _startRefreshTimer();
  }

  @override
  void didPushNext() {
    super.didPushNext();
    _refreshTimer?.cancel();
  }

  @override
  void didPopNext() {
    super.didPopNext();
    _fetchEditingInvoices();
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    final duration = _isOnline ? const Duration(seconds: 15) : const Duration(seconds: 2);
    _refreshTimer = Timer.periodic(duration, (timer) {
      _fetchEditingInvoices();
    });
  }

  Future<void> _handleLogout() async {
    _refreshTimer?.cancel();
    await _apiService.clearAuth();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  bool _isUpdateAvailable(String localStr, String serverStr) {
    try {
      final localParts = localStr.split('+');
      final serverParts = serverStr.split('+');

      final localName = localParts[0];
      final serverName = serverParts[0];

      if (localParts.length > 1 && serverParts.length > 1) {
        final localBuild = int.tryParse(localParts[1]);
        final serverBuild = int.tryParse(serverParts[1]);
        if (localBuild != null && serverBuild != null) {
          return serverBuild > localBuild;
        }
      }

      final localSubparts = localName.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final serverSubparts = serverName.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (var i = 0; i < 3; i++) {
        final l = i < localSubparts.length ? localSubparts[i] : 0;
        final s = i < serverSubparts.length ? serverSubparts[i] : 0;
        if (s > l) return true;
        if (l > s) return false;
      }
    } catch (e) {
      debugPrint('Error comparing versions: $e');
    }
    return false;
  }

  Future<void> _checkAppUpdate() async {
    if (kIsWeb) return;
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String localVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      final result = await _apiService.getLatestVersion();
      final String serverVersion = result['version'] ?? '';

      final hasUpdate = _isUpdateAvailable(localVersion, serverVersion);
      if (hasUpdate && mounted) {
        _showForcedUpdateDialog(localVersion, serverVersion);
      }
    } catch (e) {
      debugPrint('Error checking forced update: $e');
    }
  }

  void _showForcedUpdateDialog(String currentVer, String newVer) {
    double downloadProgress = 0.0;
    bool isDownloading = false;
    String downloadStatus = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false, // Prevent back button pop
          child: StatefulBuilder(
            builder: (BuildContext builderContext, StateSetter setDialogState) {
              final colorScheme = Theme.of(builderContext).colorScheme;
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  children: [
                    Icon(
                      Icons.system_update_alt,
                      color: colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Text('Yêu Cầu Cập Nhật!'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isDownloading) ...[
                      Text(
                        'Ứng dụng đã có phiên bản mới bắt buộc. Vui lòng cập nhật để tiếp tục sử dụng.',
                        style: Theme.of(builderContext).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Phiên bản hiện tại:', style: TextStyle(color: Colors.grey[600])),
                          Text(currentVer, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Phiên bản bắt buộc:', style: TextStyle(color: Colors.grey[600])),
                          Text(
                            newVer,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        downloadStatus,
                        style: Theme.of(builderContext).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      if (downloadProgress >= 0) ...[
                        LinearProgressIndicator(
                          value: downloadProgress,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(downloadProgress * 100).toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ] else ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text('Đang tải...', textAlign: TextAlign.center),
                      ],
                    ],
                  ],
                ),
                actions: [
                  if (!isDownloading)
                    ElevatedButton(
                      onPressed: () async {
                        setDialogState(() {
                          isDownloading = true;
                          downloadStatus = 'Đang chuẩn bị tải về...';
                          downloadProgress = 0.0;
                        });

                        try {
                          final tempDir = await getTemporaryDirectory();
                          final String savePath = '${tempDir.path}/app-release.apk';

                          await _apiService.downloadApk(savePath, (progress) {
                            setDialogState(() {
                              downloadProgress = progress;
                              downloadStatus = 'Đang tải bản cập nhật...';
                            });
                          });

                          setDialogState(() {
                            downloadStatus = 'Cài đặt bản cập nhật...';
                          });

                          final openResult = await OpenFilex.open(savePath);
                          
                          if (openResult.type != ResultType.done) {
                            setDialogState(() {
                              isDownloading = false;
                              downloadStatus = '';
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Không thể cài đặt APK: ${openResult.message}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          setDialogState(() {
                            isDownloading = false;
                            downloadStatus = '';
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Lỗi tải xuống: ${e.toString()}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('CẬP NHẬT NGAY', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _fetchEditingInvoices() async {
    if (!mounted) return;
    // Don't show loading indicator on auto-refresh to avoid flickering
    final bool isAutoRefresh = _refreshTimer?.isActive ?? false;
    if (!isAutoRefresh) {
      setState(() => _isLoadingInvoices = true);
    }

    final bool wasOnline = _isOnline;

    try {
      final invoices = await _apiService.getInvoices(
        showDraft: true,
        showSaved: false,
        showLocked: false,
      );
      if (mounted) {
        setState(() {
          _editingInvoices = invoices;
          _isLoadingInvoices = false;
          _isOnline = true;
        });
        if (!wasOnline) {
          _startRefreshTimer();
        }

        // Check update after first successful backend call
        if (!_hasCheckedUpdate && !kIsWeb) {
          _hasCheckedUpdate = true;
          _checkAppUpdate();
        }
      }
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('Missing Authorization') ||
          errStr.contains('Invalid Authorization') ||
          errStr.contains('Invalid token') ||
          errStr.contains('Unexpected signing method')) {
        _handleLogout();
        return;
      }

      if (mounted) {
        setState(() {
          _isLoadingInvoices = false;
          _isOnline = false;
        });
        if (wasOnline) {
          _startRefreshTimer();
        }

        // If first-load or focus fetch fails, schedule a fast retry in 2 seconds to recover quickly
        if (!isAutoRefresh) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && !_isOnline) {
              _fetchEditingInvoices();
            }
          });
        }
      }
    }
  }

  Future<void> _handleTakeTurn(Map<String, dynamic> inv) async {
    final invoiceId = inv['invoiceId'].toString();

    // Helper to extract values from sqlc Null types
    String? getStringValueLocal(dynamic field) {
      if (field == null) return null;
      if (field is Map) return field['Valid'] == true ? field['String'].toString() : null;
      return field.toString();
    }

    final currentDeviceHoldingId = getStringValueLocal(inv['deviceHoldingId']);
    final deviceName = getStringValueLocal(inv['deviceName']) ?? 'Thiết bị khác';

    // Check if another device is holding the invoice
    if (currentDeviceHoldingId != null &&
        currentDeviceHoldingId != _apiService.deviceId) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text('Cảnh báo chiếm quyền'),
              ),
            ],
          ),
          content: Text(
            'Hóa đơn này đang được chỉnh sửa bởi "$deviceName".\n\n'
            'Nếu bạn tiếp tục, người kia sẽ bị mất quyền chỉnh sửa. Bạn có chắc chắn muốn tham gia không?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('TIẾP TỤC'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      await _apiService.takeTurn(invoiceId);
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/edit_invoice',
          arguments: invoiceId,
        ).then((_) {
          if (mounted) {
            _fetchEditingInvoices();
          }
        });
      }
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('Missing Authorization') ||
          errStr.contains('Invalid Authorization') ||
          errStr.contains('Invalid token') ||
          errStr.contains('Unexpected signing method')) {
        _handleLogout();
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  Future<void> _openQRScanner() async {
    final scannedInvoiceId = await Navigator.pushNamed(context, '/qr_scanner');
    if (scannedInvoiceId != null && scannedInvoiceId is String && scannedInvoiceId.isNotEmpty) {
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/invoice_detail',
          arguments: scannedInvoiceId,
        ).then((_) {
          if (mounted) {
            _fetchEditingInvoices();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    final List<Map<String, dynamic>> menuItems = [
      {'title': 'Tạo Hóa đơn mới', 'icon': Icons.add_shopping_cart, 'color': colorScheme.primary},
      {'title': 'Quản lý Mặt hàng', 'icon': Icons.inventory, 'color': Colors.orange},
      {'title': 'Quản lý Hóa đơn', 'icon': Icons.description, 'color': Colors.red},
      {'title': 'Quản lý Người mua', 'icon': Icons.people, 'color': Colors.green},
      {'title': 'Bảng báo giá', 'icon': Icons.request_quote, 'color': Colors.teal},
      {'title': 'Hàng chờ in', 'icon': Icons.print, 'color': Colors.indigo},
      {'title': 'Quản lý Thiết bị', 'icon': Icons.devices, 'color': Colors.purple},
      {'title': 'Cấu hình hệ thống', 'icon': Icons.settings, 'color': Colors.blueGrey},
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Invoice App'),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isOnline ? Colors.green : Colors.grey).withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _isOnline ? 'Online' : 'Offline',
              style: TextStyle(
                fontSize: 12,
                color: _isOnline ? Colors.green : Colors.grey,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _openQRScanner,
            tooltip: 'Quét mã QR Hóa đơn',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Menu tùy chọn',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) async {
              if (value == 'refresh') {
                _fetchEditingInvoices();
              } else if (value == 'theme') {
                themeProvider.toggleTheme();
              } else if (value == 'logout') {
                await _handleLogout();
              }
            },
            itemBuilder: (BuildContext menuContext) => [
              const PopupMenuItem<String>(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20),
                    SizedBox(width: 8),
                    Text('Làm mới'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(
                      themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(themeProvider.isDarkMode ? 'Chế độ sáng' : 'Chế độ tối'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Đăng xuất', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchEditingInvoices,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            if (_editingInvoices.isNotEmpty || _isLoadingInvoices) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Hóa đơn đang chỉnh sửa',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.secondary,
                          ),
                    ),
                    if (_editingInvoices.length > 1)
                      Row(
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () {
                              _scrollController.animateTo(
                                _scrollController.offset - 250,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () {
                              _scrollController.animateTo(
                                _scrollController.offset + 250,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 225,
                child: _isLoadingInvoices
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: _editingInvoices.length,
                        itemBuilder: (context, index) {
                          final inv = _editingInvoices[index];
                          return EditingInvoiceCard(
                            invoice: inv,
                            colorScheme: colorScheme,
                            onTap: () => _handleTakeTurn(inv),
                          );
                        },
                      ),
              ),
              const Divider(height: 32, indent: 16, endIndent: 16),
            ],
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = constraints.maxWidth > 920 ? 3 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: menuItems.length,
                    itemBuilder: (context, index) {
                      final item = menuItems[index];
                      return InkWell(
                        onTap: () {
                          if (item['title'] == 'Tạo Hóa đơn mới') {
                            Navigator.pushNamed(context, '/create_invoice').then((_) {
                              if (mounted) {
                                _fetchEditingInvoices();
                              }
                            });
                          } else if (item['title'] == 'Quản lý Thiết bị') {
                            Navigator.pushNamed(context, '/device_management');
                          } else if (item['title'] == 'Quản lý Mặt hàng') {
                            Navigator.pushNamed(context, '/item_management');
                          } else if (item['title'] == 'Quản lý Người mua') {
                            Navigator.pushNamed(context, '/buyer_management');
                          } else if (item['title'] == 'Quản lý Hóa đơn') {
                            Navigator.pushNamed(context, '/invoice_management').then((_) {
                              if (mounted) {
                                _fetchEditingInvoices();
                              }
                            });
                          } else if (item['title'] == 'Bảng báo giá') {
                            Navigator.pushNamed(context, '/pricelist_management');
                          } else if (item['title'] == 'Hàng chờ in') {
                            Navigator.pushNamed(context, '/print_management');
                          } else if (item['title'] == 'Cấu hình hệ thống') {
                            Navigator.pushNamed(context, '/settings');
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Chức năng ${item['title']} đang phát triển')),
                            );
                          }
                        },
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(item['icon'], size: 48, color: item['color']),
                              const SizedBox(height: 12),
                              Text(
                                item['title'],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
