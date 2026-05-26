import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'preview_helper.dart';

class ExportPriceListScreen extends StatefulWidget {
  const ExportPriceListScreen({super.key});

  @override
  State<ExportPriceListScreen> createState() => _ExportPriceListScreenState();
}

class _ExportPriceListScreenState extends State<ExportPriceListScreen> {
  final ApiService _apiService = ApiService();
  final _emailFormKey = GlobalKey<FormState>();
  final _customEmailController = TextEditingController();

  Map<String, dynamic>? _priceList;
  Map<String, dynamic>? _buyerProfile;
  bool _isLoading = true;
  String _selectedFormat = 'pdf'; // 'pdf' or 'excel'

  // Document preview bytes and cache from backend export API
  Uint8List? _previewBytes;
  Uint8List? _pdfBytes;
  Uint8List? _excelBytes;
  String? _pdfViewId;
  bool _isFrameLoading = false;

  // Action switches
  bool _sendToBuyer = false;
  bool _sendToCustom = false;
  bool _saveLocally = true;
  bool _addToPrintQueue = false;

  // Execution state for premium progress animation
  bool _isExecuting = false;
  int _currentStep = 0; // 0, 1, 2, 3
  String _execError = '';
  bool _execSuccess = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_priceList == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _priceList = args;
        _fetchPriceListAndBuyerDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy thông tin bảng báo giá')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _customEmailController.dispose();
    super.dispose();
  }

  Future<void> _fetchPriceListAndBuyerDetails() async {
    if (_priceList == null) return;
    
    final pricelistId = _priceList!['customerPriceListId']?.toString();
    final buyerCode = _priceList!['buyerCode']?.toString();

    setState(() => _isLoading = true);

    try {
      // 1. Fetch full details to get fresh item prices
      if (pricelistId != null) {
        final fullPl = await _apiService.getCustomerPriceList(pricelistId);
        _priceList = fullPl;
      }

      // 2. Fetch buyer profile to extract customer email
      if (buyerCode != null && buyerCode.isNotEmpty && buyerCode != 'N/A') {
        final buyer = await _apiService.getBuyerByCode(buyerCode);
        _buyerProfile = buyer;
        // Do NOT auto-enable _sendToBuyer; user must opt in manually
      }
    } catch (e) {
      debugPrint('Lỗi tải thông tin chi tiết: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _loadPreviewBytes(); // Fetch the real PDF/Excel bytes for preview right after general details loaded
      }
    }
  }

  // Fetch actual exported file bytes from backend with caching
  Future<void> _loadPreviewBytes() async {
    final pricelistId = _priceList?['customerPriceListId']?.toString();
    if (pricelistId == null) return;

    // Check format-specific memory cache first to avoid redundant API hits
    if (_selectedFormat == 'pdf' && _pdfBytes != null) {
      setState(() {
        _previewBytes = _pdfBytes;
      });
      return;
    }
    if (_selectedFormat == 'excel' && _excelBytes != null) {
      setState(() {
        _previewBytes = _excelBytes;
      });
      return;
    }

    setState(() {
      _isFrameLoading = true;
      _previewBytes = null;
    });

    try {
      final bytes = await _apiService.exportPriceList(pricelistId, _selectedFormat, pageSize: 'A4');
      if (mounted) {
        setState(() {
          final typedBytes = bytes as Uint8List;
          _previewBytes = typedBytes;
          
          // Cache the result
          if (_selectedFormat == 'pdf') {
            _pdfBytes = typedBytes;
            _pdfViewId = registerPdfPreview(typedBytes);
          } else {
            _excelBytes = typedBytes;
          }
          
          _isFrameLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải tệp tin xem trước: $e');
      if (mounted) {
        setState(() {
          _isFrameLoading = false;
        });
      }
    }
  }

  // Handle export or send action execution
  Future<void> _handleExecution() async {
    if (_sendToCustom && !_emailFormKey.currentState!.validate()) {
      return;
    }

    if (!_sendToBuyer && !_sendToCustom && !_saveLocally && !_addToPrintQueue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn ít nhất một tác vụ thực hiện!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isExecuting = true;
      _currentStep = 0;
      _execError = '';
      _execSuccess = false;
    });

    final pricelistId = _priceList?['customerPriceListId']?.toString();
    if (pricelistId == null) {
      setState(() {
        _isExecuting = false;
        _execError = 'Không tìm thấy ID báo giá';
      });
      return;
    }

    try {
      // STEP 1: Extract Data
      await Future.delayed(const Duration(milliseconds: 800));
      setState(() => _currentStep = 1);

      // STEP 2: Compile Document
      await Future.delayed(const Duration(milliseconds: 1000));
      setState(() => _currentStep = 2);

      // Save locally if selected
      if (_saveLocally) {
        final bytes = _previewBytes ?? await _apiService.exportPriceList(pricelistId, _selectedFormat, pageSize: 'A4');
        final description = _priceList?['description'] ?? 'Bao_gia';
        final cleanDescription = description.replaceAll(' ', '_');
        
        final fileName = _selectedFormat == 'excel' 
            ? 'Bao_gia_$cleanDescription.xlsx'
            : 'Bao_gia_$cleanDescription.pdf';
            
        final mimeType = _selectedFormat == 'excel'
            ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            : 'application/pdf';
            
        final downloadUrl = '${ApiService.baseUrl}/pricelist/id/$pricelistId/export?format=$_selectedFormat';
        
        downloadFile(bytes as Uint8List, fileName, mimeType, downloadUrl);
      }

      // Send emails or add to print queue if selected
      if (_sendToBuyer || _sendToCustom || _addToPrintQueue) {
        setState(() => _currentStep = 3);
        
        if (_sendToBuyer && _buyerProfile?['email'] != null) {
          final buyerEmail = _buyerProfile!['email'].toString();
          await _apiService.exportAndEmailPriceList(pricelistId, buyerEmail, _selectedFormat);
        }

        if (_sendToCustom) {
          final customEmail = _customEmailController.text.trim();
          await _apiService.exportAndEmailPriceList(pricelistId, customEmail, _selectedFormat);
        }

        if (_addToPrintQueue) {
          await _apiService.createPrintJob(
            customerPriceListId: pricelistId,
            printType: 'Original',
            priorityNum: 0,
          );
        }
      }

      // Complete successfully
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _currentStep = 4;
          _execSuccess = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _execError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Widget _buildSettingsPanel(BuildContext context, ColorScheme colorScheme, bool isDesktop) {
    final buyerName = _priceList?['buyerName'] ?? 'Khách lẻ';
    final buyerEmail = _buyerProfile?['email']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('ĐỊNH DẠNG XUẤT FILE', colorScheme),
        const SizedBox(height: 12),
        _buildFormatSelector(colorScheme),
        const SizedBox(height: 24),
        
        _buildSectionHeader('TÁC VỤ THỰC HIỆN', colorScheme),
        const SizedBox(height: 12),
        
        // Save locally option
        _buildActionCheckbox(
          title: 'Lưu trực tiếp về máy',
          subtitle: 'Tải tệp tin $_selectedFormat xuống thiết bị',
          icon: Icons.download_for_offline_rounded,
          value: _saveLocally,
          onChanged: (val) => setState(() => _saveLocally = val ?? false),
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 12),

        // Send to buyer option
        _buildActionCheckbox(
          title: 'Gửi email cho khách hàng',
          subtitle: buyerEmail.isNotEmpty 
              ? 'Tới: $buyerEmail' 
              : 'Khách hàng $buyerName chưa cập nhật email',
          icon: Icons.contact_mail_rounded,
          value: _sendToBuyer,
          enabled: buyerEmail.isNotEmpty,
          onChanged: (val) => setState(() => _sendToBuyer = val ?? false),
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 12),

        // Send to custom email option
        _buildActionCheckbox(
          title: 'Gửi tới email tùy chỉnh khác',
          subtitle: 'Nhập địa chỉ hòm thư bất kỳ',
          icon: Icons.alternate_email_rounded,
          value: _sendToCustom,
          onChanged: (val) => setState(() => _sendToCustom = val ?? false),
          colorScheme: colorScheme,
        ),
        if (_sendToCustom) ...[
          const SizedBox(height: 12),
          Form(
            key: _emailFormKey,
            child: TextFormField(
              controller: _customEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Địa chỉ email nhận *',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vui lòng nhập địa chỉ email';
                }
                final emailRegex = RegExp(
                    r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
                if (!emailRegex.hasMatch(value.trim())) {
                  return 'Định dạng email không hợp lệ';
                }
                return null;
              },
            ),
          ),
        ],
        const SizedBox(height: 12),

        // Add to print queue option
        _buildActionCheckbox(
          title: 'Đưa vào hàng chờ in',
          subtitle: 'In một bản duy nhất',
          icon: Icons.print_rounded,
          value: _addToPrintQueue,
          onChanged: (val) => setState(() => _addToPrintQueue = val ?? false),
          colorScheme: colorScheme,
        ),

        const SizedBox(height: 32),
        
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _handleExecution,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.flash_on_rounded),
                SizedBox(width: 8),
                Text(
                  'TIẾN HÀNH THỰC HIỆN',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 920;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xuất & Gửi Báo Giá'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                isDesktop
                    ? Row(
                        children: [
                          // Settings Panel (Left Column)
                          Expanded(
                            flex: 4,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20.0),
                              child: _buildSettingsPanel(context, colorScheme, true),
                            ),
                          ),
                          
                          // Live Document Preview Panel (Right Column - Desktop Only)
                          Expanded(
                            flex: 6,
                            child: Container(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                              padding: const EdgeInsets.all(32.0),
                              alignment: Alignment.center,
                              child: _buildDocumentPreview(colorScheme),
                            ),
                          )
                        ],
                      )
                    : Column(
                        children: [
                          // In mobile, PDF preview takes up the top part (Expanded)
                          Expanded(
                            child: Container(
                              color: colorScheme.surfaceContainerLowest,
                              padding: const EdgeInsets.all(12.0),
                              child: _buildDocumentPreview(colorScheme),
                            ),
                          ),
                          // Metadata / Settings collapsible panel at the bottom
                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              border: Border(
                                top: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                            child: ExpansionTile(
                              initiallyExpanded: true,
                              title: Text(
                                'Cấu hình & Tác vụ xuất',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                                  ),
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(16.0),
                                    child: _buildSettingsPanel(context, colorScheme, false),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                
                // Premium Progress step-by-step loading overlay
                if (_isExecuting) _buildProgressOverlay(colorScheme),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: colorScheme.primary,
      ),
    );
  }

  Widget _buildFormatSelector(ColorScheme colorScheme) {
    final isPDF = _selectedFormat == 'pdf';
    return Row(
      children: [
        Expanded(
          child: _buildFormatCard(
            label: 'PDF Document',
            extension: '.pdf',
            icon: Icons.picture_as_pdf_rounded,
            isSelected: isPDF,
            activeColor: Colors.redAccent,
            onTap: () {
              if (_selectedFormat != 'pdf') {
                setState(() => _selectedFormat = 'pdf');
                _loadPreviewBytes();
              }
            },
            colorScheme: colorScheme,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildFormatCard(
            label: 'Excel Sheet',
            extension: '.xlsx',
            icon: Icons.table_chart_rounded,
            isSelected: !isPDF,
            activeColor: Colors.green,
            onTap: () {
              if (_selectedFormat != 'excel') {
                setState(() => _selectedFormat = 'excel');
                _loadPreviewBytes();
              }
            },
            colorScheme: colorScheme,
          ),
        ),
      ],
    );
  }

  Widget _buildFormatCard({
    required String label,
    required String extension,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected 
          ? activeColor.withValues(alpha: 0.08)
          : colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? activeColor : colorScheme.outline.withValues(alpha: 0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            children: [
              Icon(
                icon,
                size: 32,
                color: isSelected ? activeColor : colorScheme.outline,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isSelected ? colorScheme.onSurface : colorScheme.outline,
                ),
              ),
              Text(
                extension,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? activeColor : colorScheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCheckbox({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool?> onChanged,
    required ColorScheme colorScheme,
    bool enabled = true,
  }) {
    return Card(
      color: enabled 
          ? (value ? colorScheme.primaryContainer.withValues(alpha: 0.15) : colorScheme.surfaceContainer)
          : colorScheme.surfaceContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: value && enabled ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      elevation: 0,
      child: CheckboxListTile(
        enabled: enabled,
        activeColor: colorScheme.primary,
        value: value,
        onChanged: enabled ? onChanged : null,
        secondary: CircleAvatar(
          backgroundColor: enabled 
              ? (value ? colorScheme.primary : colorScheme.surfaceContainerHighest)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Icon(
            icon, 
            color: enabled 
                ? (value ? colorScheme.onPrimary : colorScheme.onSurfaceVariant)
                : colorScheme.outline.withValues(alpha: 0.5),
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: enabled ? colorScheme.onSurface : colorScheme.outline,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: enabled 
                ? (value ? colorScheme.primary : colorScheme.outline)
                : colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  // Renders the live platform preview using the actual binary bytes retrieved from the backend export API
  Widget _buildDocumentPreview(ColorScheme colorScheme) {
    if (_isExecuting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty_rounded,
              size: 64,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Đang xử lý tác vụ...',
              style: TextStyle(fontSize: 13, color: colorScheme.outline, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    Widget content;
    if (_isFrameLoading) {
      content = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Đang nạp bản xem trước từ máy chủ...',
              style: TextStyle(fontSize: 13, color: colorScheme.outline),
            ),
          ],
        ),
      );
    } else if (_previewBytes != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: buildPreviewWidget(
          context,
          _previewBytes!,
          _selectedFormat,
          viewId: _selectedFormat == 'pdf' ? _pdfViewId : null,
        ),
      );
    } else {
      content = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            const Text(
              'Không thể tải bản xem trước trực tiếp',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loadPreviewBytes,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Tải lại bản xem trước'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.secondaryContainer,
                foregroundColor: colorScheme.onSecondaryContainer,
                elevation: 0,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: colorScheme.surfaceContainer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _selectedFormat == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.table_chart_rounded,
                      size: 18,
                      color: _selectedFormat == 'pdf' ? Colors.redAccent : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _selectedFormat == 'pdf' ? 'BẢN XEM TRƯỚC PDF (A4)' : 'BẢN XEM TRƯỚC EXCEL (.xlsx)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                if (!_isFrameLoading && _previewBytes != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _loadPreviewBytes,
                    tooltip: 'Tải lại',
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: colorScheme.surfaceContainerLowest,
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  // Floating glassmorphic progress overlay step-by-step
  Widget _buildProgressOverlay(ColorScheme colorScheme) {
    return Container(
      color: Colors.black54,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_execError.isNotEmpty) ...[
                    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 64),
                    const SizedBox(height: 16),
                    const Text('Thực Hiện Thất Bại', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red)),
                    const SizedBox(height: 12),
                    Text(_execError, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => setState(() => _isExecuting = false),
                      child: const Text('QUAY LẠI'),
                    )
                  ] else if (_execSuccess) ...[
                    const CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.green,
                      child: Icon(Icons.check, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 16),
                    const Text('Thành Công!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                    const SizedBox(height: 12),
                    Text(
                      () {
                        final List<String> actions = [];
                        if (_saveLocally) actions.add('tải xuống tệp tin');
                        if (_sendToBuyer || _sendToCustom) actions.add('gửi email');
                        if (_addToPrintQueue) actions.add('thêm vào hàng chờ in');
                        if (actions.isEmpty) return 'Đã hoàn thành tác vụ!';
                        final formattedActions = actions.join(' và ');
                        return 'Đã $formattedActions thành công!';
                      }(),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() => _isExecuting = false);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('HOÀN TẤT'),
                    )
                  ] else ...[
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(strokeWidth: 4),
                    ),
                    const SizedBox(height: 24),
                    const Text('Đang xử lý tác vụ...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 20),
                    _buildStepRow('1. Đang kết xuất dữ liệu báo giá...', _currentStep > 0, _currentStep == 0, colorScheme),
                    const SizedBox(height: 10),
                    _buildStepRow('2. Đang kết xuất tệp tin $_selectedFormat...', _currentStep > 1, _currentStep == 1, colorScheme),
                    const SizedBox(height: 10),
                    _buildStepRow(
                      () {
                        final List<String> steps = [];
                        if (_sendToBuyer || _sendToCustom) steps.add('chuyển giao email SMTP');
                        if (_addToPrintQueue) steps.add('gửi lệnh tới hàng chờ in');
                        if (steps.isEmpty) return '3. Đang truyền tải tệp tin...';
                        return '3. Đang ${steps.join(' và ')}...';
                      }(),
                      _currentStep > 2, 
                      _currentStep == 2, 
                      colorScheme,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(String text, bool isDone, bool isActive, ColorScheme colorScheme) {
    Color textColor = Colors.grey.shade400;
    Widget icon = Icon(Icons.circle_outlined, size: 16, color: Colors.grey.shade300);

    if (isDone) {
      textColor = Colors.green;
      icon = const Icon(Icons.check_circle, size: 16, color: Colors.green);
    } else if (isActive) {
      textColor = colorScheme.primary;
      icon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
      );
    }

    return Row(
      children: [
        icon,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}
