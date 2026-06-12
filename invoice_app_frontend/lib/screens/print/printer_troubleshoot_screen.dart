// NOTE: This troubleshoot screen and HTML parser is specifically designed and optimized 
// only for the Fuji Xerox DocuPrint M115 w printer (and equivalent Brother printer models).
// Other printer models returning a different HTML maintenance structure will NOT work 
// with this parser logic.
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class PrinterTroubleshootScreen extends StatefulWidget {
  const PrinterTroubleshootScreen({super.key});

  @override
  State<PrinterTroubleshootScreen> createState() => _PrinterTroubleshootScreenState();
}

class _PrinterTroubleshootScreenState extends State<PrinterTroubleshootScreen> {
  final TextEditingController _ipController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  PrinterMaintenanceData? _printerData;
  bool _isUsingMockData = false;
  Timer? _refreshTimer;
  int? _expandedErrorIndex;
  bool _isJobStuck = false;

  @override
  void initState() {
    super.initState();
    // Query backend default printer status initially
    _fetchPrinterStatus(ip: '');
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_isLoading) {
        _fetchPrinterStatus(ip: _ipController.text, isSilent: true);
      }
    });
  }

  Future<void> _fetchPrinterStatus({required String ip, bool isSilent = false}) async {
    // If we already have data and someone submits an empty IP manually, show error
    if (ip.trim().isEmpty && _printerData != null && !isSilent) {
      setState(() {
        _errorMessage = 'Vui lòng nhập địa chỉ IP hợp lệ';
      });
      return;
    }

    if (!isSilent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isUsingMockData = false;
      });
    }

    try {
      final queryParam = ip.trim().isEmpty ? '' : '?ip=${Uri.encodeComponent(ip.trim())}';
      final response = await ApiService()
          .get('/print/printer/info$queryParam')
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        // Read printer IP returned by proxy header to populate the text field if empty
        final actualIp = response.headers['x-printer-ip'] ?? ip;
        if (actualIp.isNotEmpty && _ipController.text.isEmpty) {
          _ipController.text = actualIp;
        }

        final data = _parseHtml(response.body, actualIp);
        final isStuck = response.headers['x-printing-stuck'] == 'true';
        if (mounted) {
          setState(() {
            _printerData = data;
            _isJobStuck = isStuck;
            _isLoading = false;
            _errorMessage = null;
          });
          _startRefreshTimer();
        }
      } else {
        throw Exception('Mã phản hồi từ backend proxy: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted && !isSilent) {
        final target = ip.trim().isEmpty ? 'mặc định' : 'tại $ip';
        setState(() {
          _errorMessage =
              'Không thể kết nối đến máy in $target (thông qua proxy backend).\nChi tiết: ${e.toString().replaceAll('Exception: ', '')}';
          _isLoading = false;
        });
      }
    }
  }




  void _loadMockData() {
    setState(() {
      _printerData = _parseHtml(_mockHtmlContent, '192.168.1.183 (Mock)');
      _isJobStuck = false;
      _isLoading = false;
      _errorMessage = null;
      _isUsingMockData = true;
    });
  }

  // Parse printer HTML page logic
  PrinterMaintenanceData _parseHtml(String rawHtml, String ip) {
    // Unescape common HTML characters
    final html = rawHtml
        .replaceAll('&#32;', ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');

    // Extract all group contents
    final groupRegex = RegExp(r'<div class="contentsGroup">(.*?)</div>', dotAll: true);
    final groupMatches = groupRegex.allMatches(html);
    final List<String> groups = groupMatches.map((m) => m.group(1)!).toList();

    // Helper map extraction for DL items
    Map<String, String> extractDlItems(String block) {
      final Map<String, String> items = {};
      final dlRegex = RegExp(r'<dt>(.*?)</dt>\s*<dd>(.*?)</dd>', dotAll: true);
      final matches = dlRegex.allMatches(block);
      for (final m in matches) {
        final key = m.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        final val = m.group(2)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (key.isNotEmpty) {
          items[key] = val;
        }
      }
      return items;
    }

    Map<String, String> nodeInfo = {};
    Map<String, String> deviceStatus = {};
    Map<String, String> remainingLife = {};
    Map<String, String> pagesPrintedSize = {};
    Map<String, String> pagesPrintedType = {};
    Map<String, String> pagesPrintedMode = {};
    Map<String, String> pagesScanned = {};
    Map<String, String> replaceCount = {};
    Map<String, String> paperJams = {};
    List<Map<String, String>> errorHistory = [];

    // Parse each content block dynamically or by pattern matching
    for (final group in groups) {
      final h3Match = RegExp(r'<h3>(.*?)</h3>', dotAll: true).firstMatch(group);
      final h3Title = h3Match != null
          ? h3Match.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim()
          : '';

      if (h3Title.contains('Node Information')) {
        nodeInfo = extractDlItems(group);
      } else if (h3Title.contains('Device Status')) {
        deviceStatus = extractDlItems(group);
      } else if (h3Title.contains('Remaining Life')) {
        remainingLife = extractDlItems(group);
      } else if (h3Title.contains('Total Pages Printed')) {
        final dlItems = extractDlItems(group);
        if (dlItems.containsKey('A4/Letter')) {
          pagesPrintedSize = dlItems;
        } else if (dlItems.containsKey('Plain/Recycled')) {
          pagesPrintedType = dlItems;
        } else if (dlItems.containsKey('List') || dlItems.containsKey('Copy')) {
          pagesPrintedMode = dlItems;
        }
      } else if (h3Title.contains('Total Pages Scanned')) {
        pagesScanned = extractDlItems(group);
      } else if (h3Title.contains('Replace Count')) {
        replaceCount = extractDlItems(group);
      } else if (h3Title.contains('Error History')) {
        // Parse table rows
        final rowRegex = RegExp(
            r'<tr>\s*<th>(\d+)</th>\s*<td>([^<]*)</td>\s*<td>Page\s*:\s*(\d+)</td>\s*</tr>',
            dotAll: true);
        final rowsMatches = rowRegex.allMatches(group);
        for (final rMatch in rowsMatches) {
          errorHistory.add({
            'index': rMatch.group(1)!,
            'error': rMatch.group(2)!.trim(),
            'page': rMatch.group(3)!,
          });
        }
      } else if (group.contains('Total Paper Jams') || group.contains('Jam Tray')) {
        // Group without title (Paper jams)
        paperJams = extractDlItems(group);
      }
    }

    return PrinterMaintenanceData(
      ipAddress: ip,
      nodeInfo: nodeInfo,
      deviceStatus: deviceStatus,
      remainingLife: remainingLife,
      pagesPrintedSize: pagesPrintedSize,
      pagesPrintedType: pagesPrintedType,
      pagesPrintedMode: pagesPrintedMode,
      pagesScanned: pagesScanned,
      replaceCount: replaceCount,
      paperJams: paperJams,
      errorHistory: errorHistory,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final double width = MediaQuery.of(context).size.width;
    final bool isWide = width > 750;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông tin & Troubleshoot'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchPrinterStatus(ip: _ipController.text),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. IP Configuration Card
            _buildIpConfigCard(colorScheme, isWide),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_errorMessage != null)
              _buildErrorWidget(colorScheme)
            else if (_printerData != null) ...[
              if (_isJobStuck) ...[
                _buildStuckJobAlertCard(colorScheme),
              ],
              if (_isUsingMockData) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Đang xem dữ liệu máy in mẫu (Offline Mode). Vui lòng kết nối máy in để xem trạng thái thực tế.',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 2. Main content area (responsive grid)
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildConsumablesCard(colorScheme),
                          const SizedBox(height: 16),
                          _buildNodeAndStatusCard(colorScheme),
                          const SizedBox(height: 16),
                          _buildUsageStatsCard(colorScheme),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTroubleshootingCard(colorScheme),
                          const SizedBox(height: 16),
                          _buildErrorHistoryCard(colorScheme),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _buildConsumablesCard(colorScheme),
                const SizedBox(height: 16),
                _buildNodeAndStatusCard(colorScheme),
                const SizedBox(height: 16),
                _buildUsageStatsCard(colorScheme),
                const SizedBox(height: 16),
                _buildTroubleshootingCard(colorScheme),
                const SizedBox(height: 16),
                _buildErrorHistoryCard(colorScheme),
              ],
            ] else
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60.0),
                  child: Column(
                    children: [
                      Icon(Icons.print_disabled_outlined, size: 64, color: colorScheme.outline),
                      const SizedBox(height: 12),
                      const Text(
                        'Chưa có thông tin máy in nào được tải.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Section 1: IP Config Bar
  Widget _buildIpConfigCard(ColorScheme colorScheme, bool isWide) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_input_hdmi, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ IP Máy in',
                      hintText: 'Ví dụ: 192.168.1.183',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    keyboardType: TextInputType.url,
                    onFieldSubmitted: (val) => _fetchPrinterStatus(ip: val),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _fetchPrinterStatus(ip: _ipController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('KẾT NỐI'),
                ),
              ],
            ),
            const Divider(height: 12),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Lưu ý: Tính năng này chỉ thiết kế riêng cho dòng máy in Fuji Xerox DocuPrint M115 w (hoặc Brother tương đương). Các loại máy in khác sẽ không tương thích với bộ phân tách HTML này.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Section 2: Consumables (Toner & Drum Remaining Life)
  Widget _buildConsumablesCard(ColorScheme colorScheme) {
    final life = _printerData!.remainingLife;
    
    // Parse toner percentage (e.g. "(100.00%)" or "100.00%")
    final tonerStr = life['Toner**'] ?? '0';
    final tonerVal = _extractPercent(tonerStr);
    
    // Parse drum percentage (e.g. "(63.00%)" or "63.00%")
    final drumStr = life['(% of Life Remaining)'] ?? '0';
    final drumVal = _extractPercent(drumStr);
    final drumPages = life['Drum Unit*'] ?? '0 trang';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mức vật tư tiêu hao',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                // Toner display
                Expanded(
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            height: 100,
                            child: CircularProgressIndicator(
                              value: tonerVal / 100.0,
                              strokeWidth: 10,
                              backgroundColor: colorScheme.surfaceContainerHighest,
                              color: _getMetricColor(tonerVal),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.opacity, color: _getMetricColor(tonerVal), size: 28),
                              const SizedBox(height: 4),
                              Text(
                                '${tonerVal.toStringAsFixed(0)}%',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Ống mực (Toner)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Còn lại: $tonerStr',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // Drum display
                Expanded(
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            height: 100,
                            child: CircularProgressIndicator(
                              value: drumVal / 100.0,
                              strokeWidth: 10,
                              backgroundColor: colorScheme.surfaceContainerHighest,
                              color: _getMetricColor(drumVal),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.replay_circle_filled, color: _getMetricColor(drumVal), size: 28),
                              const SizedBox(height: 4),
                              Text(
                                '${drumVal.toStringAsFixed(0)}%',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Trống từ (Drum Unit)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Còn lại: $drumPages',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Section 3: Node and Status
  Widget _buildNodeAndStatusCard(ColorScheme colorScheme) {
    final info = _printerData!.nodeInfo;
    final status = _printerData!.deviceStatus;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Thông tin thiết bị',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildDetailRow('Tên Model', info['Model Name'] ?? 'FX DocuPrint M115 w'),
            _buildDetailRow('Số Serial', info['Serial no.'] ?? 'Không rõ'),
            _buildDetailRow('Phiên bản Firmware', info['Main Firmware Version'] ?? 'D'),
            _buildDetailRow('Bộ nhớ máy in', info['Memory Size'] ?? '32MB'),
            const Divider(height: 24),
            _buildDetailRow('Tổng số trang in (Page Counter)', status['Page Counter'] ?? '0', isHighlight: true),
            _buildDetailRow('Số vòng quay trống (Drum Count)', status['Drum Count'] ?? '0'),
          ],
        ),
      ),
    );
  }

  // Section 4: Usage Stats Card (Grouped printed pages counters)
  Widget _buildUsageStatsCard(ColorScheme colorScheme) {
    final size = _printerData!.pagesPrintedSize;
    final type = _printerData!.pagesPrintedType;
    final mode = _printerData!.pagesPrintedMode;
    final scanned = _printerData!.pagesScanned;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      color: colorScheme.surface,
      child: DefaultTabController(
        length: 3,
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.analytics_outlined, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Thống kê lượng sử dụng',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TabBar(
                labelColor: colorScheme.primary,
                unselectedLabelColor: colorScheme.onSurfaceVariant,
                indicatorColor: colorScheme.primary,
                tabs: const [
                  Tab(text: 'Khổ giấy'),
                  Tab(text: 'Loại / Chức năng'),
                  Tab(text: 'Quét (Scan)'),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: TabBarView(
                  children: [
                    // Tab 1: Size
                    Column(
                      children: [
                        _buildStatBar('A4 / Letter', size['A4/Letter'] ?? '0 trang'),
                        _buildStatBar('A5', size['A5'] ?? '0 trang'),
                        _buildStatBar('Legal / Folio', size['Legal/Folio'] ?? '0 trang'),
                        _buildStatBar('B5 / Executive', size['B5/Executive'] ?? '0 trang'),
                        _buildStatBar('Khác', size['Others'] ?? '0 trang'),
                      ],
                    ),
                    // Tab 2: Type / Function
                    Column(
                      children: [
                        _buildStatBar('Giấy Thường / Tái chế', type['Plain/Recycled'] ?? '0 trang'),
                        const Divider(height: 16),
                        _buildStatBar('Bản in máy tính', mode['Print'] ?? '0 trang'),
                        _buildStatBar('Bản sao chụp (Copy)', mode['Copy'] ?? '0 trang'),
                        _buildStatBar('Danh sách báo cáo', mode['List'] ?? '0 trang'),
                      ],
                    ),
                    // Tab 3: Scan
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.scanner, size: 48, color: colorScheme.primary.withValues(alpha: 0.7)),
                        const SizedBox(height: 12),
                        const Text('Số trang quét mặt kính phẳng (Flatbed)'),
                        const SizedBox(height: 8),
                        Text(
                          scanned['Flatbed'] ?? '0 trang',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Section 5: Troubleshooting (Jams & Replace Counts)
  Widget _buildTroubleshootingCard(ColorScheme colorScheme) {
    final jams = _printerData!.paperJams;
    final replaces = _printerData!.replaceCount;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build_circle_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Lịch sử thay thế & Kẹt giấy',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Số lần kẹt giấy',
              style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.secondary),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCountIndicator('Tổng số lần kẹt', jams['Total Paper Jams'] ?? '0', Colors.red, colorScheme),
                _buildCountIndicator('Khay giấy', jams['Jam Tray'] ?? '0', Colors.orange, colorScheme),
                _buildCountIndicator('Kẹt trong 1', jams['Jam Inside 1'] ?? '0', Colors.orange, colorScheme),
                _buildCountIndicator('Kẹt trong 2', jams['Jam Inside 2'] ?? '0', Colors.orange, colorScheme),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Số lần thay linh kiện',
              style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.secondary),
            ),
            const SizedBox(height: 8),
            _buildDetailRow('Số lần thay mực (Toner)', replaces['Toner'] ?? '0'),
            _buildDetailRow('Số lần thay trống (Drum)', replaces['Drum Unit'] ?? '0'),
          ],
        ),
      ),
    );
  }

  // Section 6: Error History
  Widget _buildErrorHistoryCard(ColorScheme colorScheme) {
    final errors = _printerData!.errorHistory;
    final currentPage = _printerData!.deviceStatus['Page Counter'] ?? '0';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '10 lỗi gần nhất (Trang hiện tại: $currentPage)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (errors.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text('Không có lịch sử lỗi nào.'),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: errors.length,
                itemBuilder: (context, index) {
                  final err = errors[index];
                  final isCritical = err['error']!.contains('No Toner') ||
                      err['error']!.contains('Drum !') ||
                      err['error']!.contains('Jam');
                  final isExpanded = _expandedErrorIndex == index;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expandedErrorIndex = isExpanded ? null : index;
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isCritical
                                ? Colors.red.withValues(alpha: 0.08)
                                : colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCritical
                                  ? Colors.red.withValues(alpha: 0.2)
                                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: isCritical ? Colors.red : colorScheme.secondary,
                                child: Text(
                                  err['index']!,
                                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Builder(
                                      builder: (builderContext) {
                                        final translation = _translateError(err['error']!);
                                        final displayError = translation.isNotEmpty
                                            ? "${err['error']} ($translation)"
                                            : err['error']!;
                                        return Text(
                                          displayError,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isCritical ? Colors.red[800] : colorScheme.onSurface,
                                          ),
                                        );
                                      },
                                    ),
                                    Text(
                                      'Tại số trang: ${err['page']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isCritical ? Icons.error : Icons.warning_amber_rounded,
                                    color: isCritical ? Colors.red : Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: _buildTroubleshootingGuidance(err['error']!, colorScheme),
                        ),
                      const SizedBox(height: 10),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // Row builder helper
  Widget _buildDetailRow(String label, String val, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            val,
            style: TextStyle(
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
              fontSize: isHighlight ? 15 : 13,
              color: isHighlight ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }

  // Horizontal stat indicator bar helper
  Widget _buildStatBar(String label, String valueStr) {
    final count = int.tryParse(valueStr.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final total = int.tryParse(_printerData!.deviceStatus['Page Counter'] ?? '1') ?? 1;
    final ratio = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              Text(valueStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: colorScheme.primary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  // Grid box count indicator helper
  Widget _buildCountIndicator(String label, String countStr, Color color, ColorScheme colorScheme) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
          child: Column(
            children: [
              Text(
                countStr,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Error screen helper
  Widget _buildErrorWidget(ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.errorContainer.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _loadMockData,
                  icon: const Icon(Icons.remove_red_eye_outlined),
                  label: const Text('Xem dữ liệu mẫu'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _fetchPrinterStatus(ip: _ipController.text),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper parser percentage
  double _extractPercent(String valueStr) {
    final clean = valueStr.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  // Helper consumable color coding
  Color _getMetricColor(double val) {
    if (val > 40) return Colors.green;
    if (val > 15) return Colors.orange;
    return Colors.red;
  }

  // Helper error message translation
  String _translateError(String error) {
    final cleanError = error.trim().toLowerCase();
    if (cleanError.contains('no toner')) {
      return 'Không có hộp mực / Hết mực';
    } else if (cleanError.contains('drum !')) {
      return 'Lỗi trống từ / Drum';
    } else if (cleanError.contains('toner low')) {
      return 'Mực sắp hết';
    } else if (cleanError.contains('cover is open')) {
      return 'Nắp máy in đang mở';
    } else if (cleanError.contains('jam inside 1')) {
      return 'Kẹt giấy bên trong (Vị trí 1)';
    } else if (cleanError.contains('jam inside 2')) {
      return 'Kẹt giấy bên trong (Vị trí 2)';
    } else if (cleanError.contains('jam inside')) {
      return 'Kẹt giấy bên trong';
    } else if (cleanError.contains('jam tray')) {
      return 'Kẹt giấy tại khay';
    } else if (cleanError.contains('cartridge error')) {
      return 'Lỗi hộp mực';
    } else if (cleanError.contains('drum end soon')) {
      return 'Trống từ sắp hết hạn';
    } else if (cleanError.contains('size error') || cleanError.contains('size mismatch')) {
      return 'Sai khổ giấy';
    } else if (cleanError.contains('replace toner')) {
      return 'Thay hộp mực';
    } else if (cleanError.contains('replace drum')) {
      return 'Thay trống từ';
    }
    return '';
  }

  // Guidance helper method
  Widget _buildTroubleshootingGuidance(String error, ColorScheme colorScheme) {
    final cleanError = error.trim().toLowerCase();
    String title = 'Hướng dẫn khắc phục nhanh';
    List<String> steps = [];

    if (cleanError.contains('no toner') || cleanError.contains('toner low') || cleanError.contains('replace toner')) {
      title = 'Hướng dẫn khắc phục (Lỗi Mực in)';
      steps = [
        'Mở nắp trước của máy in.',
        'Nhấc cụm trống từ (Drum Unit màu đen lá cây) ra ngoài.',
        'Nhấn lẫy khóa màu xanh lá cây xuống và lấy hộp mực (Toner Cartridge) cũ ra.',
        'Lấy hộp mực mới, lắc đều nhẹ qua lại vài lần để phân phối đều mực.',
        'Tháo nắp bảo vệ, lắp hộp mực mới vào cụm trống từ cho đến khi nghe tiếng "cạch" khóa lại.',
        'Lắp lại cụm trống từ vào máy in và đóng nắp trước lại.'
      ];
    } else if (cleanError.contains('drum !') || cleanError.contains('drum end soon') || cleanError.contains('replace drum')) {
      title = 'Hướng dẫn khắc phục (Lỗi Trống từ / Drum)';
      steps = [
        'Kiểm tra xem máy có bị kẹt giấy không (vì lỗi Drum! thường đi kèm với kẹt giấy). Nếu có, hãy gỡ sạch giấy kẹt ra trước.',
        'Nếu không phải kẹt giấy, hãy mở nắp trước, rút cụm trống từ (Drum) ra và gắn chặt lại vào máy in (nhiều trường hợp chỉ cần tháo ra gắn lại là xong).',
        'Đóng nắp trước lại và kiểm tra xem đèn báo trạng thái trên máy in đã chuyển sang màu xanh chưa.'
      ];
    } else if (cleanError.contains('jam')) {
      title = 'Hướng dẫn xử lý (Giấy bị kẹt)';
      steps = [
        'Bước 1: Mở nắp trước máy in, rút cụm trống từ (Drum) ra ngoài và kéo nhẹ tờ giấy bị kẹt bên dưới trống ra (luôn kéo theo chiều ra của giấy).',
        'Bước 2: Mở nắp lưng phía sau máy in và mở lẫy ép lô sấy (nếu có) để kéo giấy kẹt từ phía sau ra ngoài.',
        'Bước 3: Rút khay chứa giấy ra hoàn toàn và kiểm tra xem có tờ giấy nào bị kẹt hoặc lệch bên trong gầm máy không.',
        'LƯU Ý: Không dùng dao, kéo hoặc vật sắc nhọn để gắp giấy kẹt vì dễ làm xước trống từ hoặc rách rulo sấy nhiệt.'
      ];
    } else if (cleanError.contains('cover is open')) {
      title = 'Hướng dẫn khắc phục (Nắp máy đang mở)';
      steps = [
        'Đảm bảo nắp đậy phía trước (khu vực lấy giấy ra) đã được đóng khớp kín.',
        'Kiểm tra nắp lưng phía sau máy in xem đã được đóng khớp hoàn toàn chưa.',
        'Nếu đóng rồi vẫn báo lỗi, hãy kiểm tra xem cụm trống từ đã được đẩy sát vào vị trí khay gá chưa.'
      ];
    } else if (cleanError.contains('cartridge error')) {
      title = 'Hướng dẫn khắc phục (Lỗi hộp mực)';
      steps = [
        'Lấy cụm trống từ và hộp mực ra khỏi máy in.',
        'Tách hộp mực ra khỏi trống từ, lau sạch các bề mặt tiếp xúc kim loại của hộp mực.',
        'Lắp lại hộp mực vào trống từ chắc chắn, kiểm tra xem bánh răng reset của hộp mực đã ở đúng vị trí chưa.',
        'Lắp cụm trống trở lại máy in.'
      ];
    } else {
      title = 'Lời khuyên kỹ thuật';
      steps = [
        'Tắt công tắc nguồn máy in, đợi khoảng 10 giây rồi bật lại để khởi động lại máy.',
        'Kiểm tra lại cáp kết nối hoặc đèn hiển thị trên bảng điều khiển của máy in.',
        'Nếu lỗi tiếp tục lặp lại, vui lòng liên hệ kỹ thuật viên hỗ trợ để tránh hư hại phần cứng.'
      ];
    }

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, size: 18, color: Colors.amber[700]),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...steps.map((step) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        step,
                        style: const TextStyle(fontSize: 11.5, height: 1.3),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStuckJobAlertCard(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lệnh in bị kẹt!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Phát hiện có một lệnh in đang bị kẹt (lâu hơn 30 giây) và chưa được truyền qua máy in thành công.',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.error.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb, size: 16, color: Colors.amber[700]),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Gợi ý khắc phục: Tháo dây cắm nguồn (phích điện) của máy in ra, đợi khoảng 20 giây, sau đó cắm lại nguồn để khởi động lại bộ nhớ máy in.',
                          style: TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Sample HTML mock data when offline
const String _mockHtmlContent = '''
<?xml version="1.0" encoding="iso-8859-1"?><!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"><html lang="en-gb" xmlns="http://www.w3.org/1999/xhtml" xml:lang="en-gb"><head><meta http-equiv="Content-Script-Type" content="text/javascript" /><meta http-equiv="content-style-type" content="text/css" /><meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" /><script type="text/javascript" src="/common/js/ews.js"></script>
 <link rel="stylesheet" type="text/css" href="../common/css/common.css" /> 
 <link rel="stylesheet" type="text/css" href="../common/css/ews.css" /><title>FX DocuPrint M115 w</title></head><body><div id="baseFrame"><div id="frameContainer"><div id="headerFrameContainerLeft"><div id="headerFrameContainerRight"><div id="headerFrameInner"><div id="headerFrame"><div id="modelName"><h1>DocuPrint M115 w</h1><div class="SetBox" id="SetBoxNoAuthRight"><div id="SetBoxNoAuthLeft"><a href="/admin/password.html">Please&#32;configure&#32;the&#32;password &gt;&gt;</a></div></div></div><div id="corporateLogo"><a href="http://www.fujixeroxprinters.com" target="_blank" ><img src="/common/images/logo.gif" alt="FX" /></a></div></div><div id="tabMenu"><ul><li><ul><li class="selected"><p>General</p></li></ul></li><li><ul><li><a href="/copy/copy.html">Copy</a></li><li><a href="/print/print.html">Print</a></li></ul></li><li><ul><li><a href="/admin/password.html">Administrator</a></li></ul></li><li><ul><li><a href="/net/net/net.html">Network</a></li></ul></li></ul></div></div></div></div><div id="mainFrameContainer"><div id="mainFrameTopLeft"><div id="mainFrameTopRight"><div id="mainFrameTopInner"><div id="subTabMenu">&nbsp;</div></div></div></div><div id="mainFrameInner"><div id="subMenu"><div><a href="/general/status.html">Status</a></div><div><a href="/general/reflesh.html" class="subPage">Auto&#32;Refresh&#32;Interval</a></div><div class="selected"><div class="top"><div class="bottom"><a href="/general/information.html?kind=item">Maintenance&#32;Information</a></div></div></div><div><a href="/general/lists.html">Lists/Reports</a></div><div><a href="/general/find.html">Find&#32;Device</a></div><div><a href="/general/contact.html">Contact&#32;&amp;&#32;Location</a></div><div><a href="/general/powerdown.html">Auto&#32;Power&#32;Off</a></div><div><a href="/general/panel.html">Panel</a></div><div><a href="/general/replacetoner.html">Replace&#32;Toner</a></div></div><div id="rightFrameContainer"><div id="rightFrame"><div id="mainContent"><div id="pageTitle"><h2>Maintenance&#32;Information</h2></div><div id="pageContents"><form method="post" action="/etc/mnt_info.csv"><div><input type="hidden" id="pageid" name="pageid" value="3" /></div><div class="contentsGroup"><h3>Node&#32;Information</h3><dl class="items"><dt>Model&#32;Name</dt><dd>FX DocuPrint M115 w</dd><dt>Serial&#32;no.</dt><dd>DJ8--734572</dd><dt>Main&#32;Firmware&#32;Version</dt><dd>D</dd><dt>Memory&#32;Size</dt><dd>32<span class="unit">MB</span></dd></dl></div><div class="contentsGroup"><h3>Device&#32;Status</h3><dl class="items"><dt>Page&#32;Counter</dt><dd>51482</dd><dt>Drum&#32;Count</dt><dd>3770</dd></dl></div><div class="contentsGroup"><h3>Remaining&#32;Life</h3><dl class="items"><dt>Drum&#32;Unit*</dt><dd>6230<span class="unit">pages</span></dd><dt>(%&#32;of&#32;Life&#32;Remaining)</dt><dd>(63.00%)</dd><dt>Toner**</dt><dd>(100.00%)</dd></dl></div><div class="contentsGroup"><h3>Total&#32;Pages&#32;Printed</h3><dl class="items"><dt>A4/Letter</dt><dd>50235<span class="unit">pages</span></dd><dt>Legal/Folio</dt><dd>3<span class="unit">pages</span></dd><dt>B5/Executive</dt><dd>0<span class="unit">pages</span></dd><dt>A5</dt><dd>1221<span class="unit">pages</span></dd><dt>Others</dt><dd>23<span class="unit">pages</span></dd></dl></div><div class="contentsGroup"><h3>Total&#32;Pages&#32;Printed</h3><dl class="items"><dt>Plain/Recycled</dt><dd>51482<span class="unit">pages</span></dd></dl></div><div class="contentsGroup"><h3>Total&#32;Pages&#32;Printed</h3><dl class="items"><dt>List</dt><dd>6<span class="unit">pages</span></dd><dt>Copy</dt><dd>12087<span class="unit">pages</span></dd><dt>Print</dt><dd>39389<span class="unit">pages</span></dd></dl></div><div class="contentsGroup"><h3>Total&#32;Pages&#32;Scanned</h3><dl class="items"><dt>Flatbed</dt><dd>12107<span class="unit">pages</span></dd></dl></div><div class="contentsGroup"><h3>Replace&#32;Count</h3><dl class="items"><dt>Toner</dt><dd>82</dd><dt>Drum&#32;Unit</dt><dd>12</dd></dl></div><div class="contentsGroup"><dl class="items"><dt>Total&#32;Paper&#32;Jams</dt><dd>29</dd></dl><dl class="items"><dt>Jam&#32;Tray</dt><dd>1</dd><dt>Jam&#32;Inside&#32;1</dt><dd>22</dd><dt>Jam&#32;Inside&#32;2</dt><dd>6</dd></dl></div><div class="contentsGroup"><h3>Error&#32;History(last&#32;10&#32;errors)</h3><table class="list errorHistory" summary="Error History"><tbody><tr><th>1</th><td>No Toner</td><td>Page&nbsp;:&nbsp;51436</td></tr><tr><th>2</th><td>Drum !</td><td>Page&nbsp;:&nbsp;51052</td></tr><tr><th>3</th><td>No Toner</td><td>Page&nbsp;:&nbsp;51041</td></tr><tr><th>4</th><td>Jam Inside 1</td><td>Page&nbsp;:&nbsp;50701</td></tr><tr><th>5</th><td>Drum !</td><td>Page&nbsp;:&nbsp;50701</td></tr><tr><th>6</th><td>Toner Low</td><td>Page&nbsp;:&nbsp;50681</td></tr><tr><th>7</th><td>Cover is Open BD</td><td>Page&nbsp;:&nbsp;50606</td></tr><tr><th>8</th><td>Jam Inside 1</td><td>Page&nbsp;:&nbsp;50204</td></tr><tr><th>9</th><td>No Toner</td><td>Page&nbsp;:&nbsp;49912</td></tr><tr><th>10</th><td>Cartridge Error</td><td>Page&nbsp;:&nbsp;49907</td></tr></tbody></table></div><div class="contentsGroup"><p class="noteMessage">*Based&#32;on&#32;A4/Letter&#32;printing<br />**Remaining&#32;life&#32;will&#32;vary&#32;depending&#32;on&#32;the&#32;types&#32;of&#32;documents&#32;printed,&#32;their&#32;coverage&#32;and&#32;device&#32;usage.<br /></p></div><div class="contentsGroup"><p class="noteMessage">You&#32;can&#32;convert&#32;this&#32;Maintenance&#32;Information&#32;page&#32;to&#32;a&#32;CSV&#32;file&#32;format.<br />Click&#32;Submit&#32;to&#32;create&#32;the&#32;CSV&#32;file</p></div><div class="contentsButtons"><input type="submit"  value="Submit" /></div></form></div></div></div></div><script type="text/javascript"><!--
SetMinHeight();
// --></script></div><div id="mainFrameBottomLeft"><div id="mainFrameBottomRight"><div id="mainFrameBottomInner"></div></div></div></div><div id="footerFrameContainer"><div id="copyright">Copyright(C) Fuji Xerox Co., Ltd. 2014<br/>Copyright(C) 2000-2014 Brother Industries, Ltd. All Rights Reserved.</div><div id="topBack"><a href="#">Top<img src="/common/images/ic_pt.gif" alt="Top" /></a></div></div></div></div></body></html>
''';

// Data container class
class PrinterMaintenanceData {
  final String ipAddress;
  final Map<String, String> nodeInfo;
  final Map<String, String> deviceStatus;
  final Map<String, String> remainingLife;
  final Map<String, String> pagesPrintedSize;
  final Map<String, String> pagesPrintedType;
  final Map<String, String> pagesPrintedMode;
  final Map<String, String> pagesScanned;
  final Map<String, String> replaceCount;
  final Map<String, String> paperJams;
  final List<Map<String, String>> errorHistory;

  PrinterMaintenanceData({
    required this.ipAddress,
    required this.nodeInfo,
    required this.deviceStatus,
    required this.remainingLife,
    required this.pagesPrintedSize,
    required this.pagesPrintedType,
    required this.pagesPrintedMode,
    required this.pagesScanned,
    required this.replaceCount,
    required this.paperJams,
    required this.errorHistory,
  });
}
