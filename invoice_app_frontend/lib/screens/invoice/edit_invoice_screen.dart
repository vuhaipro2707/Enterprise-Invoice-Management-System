import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/string_utils.dart';
import '../../widgets/line_item_card.dart';
import '../../widgets/address_search_field.dart';

class EditInvoiceScreen extends StatefulWidget {
  const EditInvoiceScreen({super.key});

  @override
  State<EditInvoiceScreen> createState() => _EditInvoiceScreenState();
}

class _EditInvoiceScreenState extends State<EditInvoiceScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();
  String? _invoiceId;
  Map<String, dynamic>? _invoiceData;
  bool _isLoading = true;
  bool _hasScrolledOnEntry = false;
  int? _pickedIndex;
  final String _localSearchQuery = '';
  String? _highlightedLineItemId; // for single add (create line item)
  Set<String> _highlightedLineItemIds = {}; // for batch add (from pricelist)
  final _formKey = GlobalKey<FormState>();

  final _buyerCodeController = TextEditingController();
  final _buyerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _idCardController = TextEditingController();
  final _emailController = TextEditingController();
  final _taxIdController = TextEditingController();
  String? _selectedBuyerId;
  double? _selectedLat;
  double? _selectedLng;
  bool _isFetchingBuyer = false;
  bool _isFetchingBusiness = false;
  bool _isBuyerInfoExpanded = false;

  Timer? _pingTimer;
  int _failedPingCount = 0;
  bool _isShowingAlert = false;

  @override
  void initState() {
    super.initState();
    _startPingTimer();
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _failedPingCount = 0;
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_invoiceId != null && !_isShowingAlert) {
        _pingInvoice();
      }
    });
  }

  Future<void> _pingInvoice() async {
    try {
      final response = await _apiService.get('/invoice/ping/invoiceId/$_invoiceId');
      if (response.statusCode != 200) {
        throw Exception('Ping failed');
      }
      final data = jsonDecode(response.body);
      _failedPingCount = 0; // Reset counter on success

      if (!mounted) return;

      final bool editStatus = data['editStatus'] ?? false;
      final String? holdingId = data['deviceHoldingId'];
      final String currentDeviceId = _apiService.deviceId ?? '';

      if (!editStatus) {
        _showStatusAlert(
          title: 'Hóa đơn đã được lưu',
          message: 'Hóa đơn này đã được lưu trước đó. Bạn có muốn mở lại để chỉnh sửa không?',
          confirmLabel: 'CHỈNH SỬA',
          onConfirm: _takeTurn,
        );
      } else if (holdingId != null && holdingId != currentDeviceId) {
        _showStatusAlert(
          title: 'Mất quyền chỉnh sửa',
          message: 'Thiết bị khác (${data['deviceName'] ?? 'Thiết bị khác'}) đã giành quyền chỉnh sửa hóa đơn này.',
          confirmLabel: 'GIÀNH LẠI QUYỀN',
          onConfirm: _takeTurn,
        );
      }
    } catch (e) {
      _failedPingCount++;
      if (_failedPingCount >= 5) {
        _pingTimer?.cancel();
        _showConnectionAlert();
      }
    }
  }

  void _showStatusAlert({
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) {
    if (_isShowingAlert) return;
    setState(() => _isShowingAlert = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              _pingTimer?.cancel();
              setState(() => _isShowingAlert = true);
              Navigator.pop(dialogContext); // Close dialog
              if (context.mounted) {
                Navigator.popUntil(context, (route) => route.settings.name == '/edit_invoice');
                Navigator.pop(context);
              }
            },
            child: const Text('THOÁT RA'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              setState(() => _isShowingAlert = false);
              onConfirm();
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isShowingAlert = false);
      }
    });
  }

  void _showConnectionAlert() {
    if (_isShowingAlert) return;
    setState(() => _isShowingAlert = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mất kết nối'),
        content: const Text('Không thể kết nối tới máy chủ sau nhiều lần thử. Vui lòng kiểm tra lại mạng.'),
        actions: [
          TextButton(
            onPressed: () {
              _pingTimer?.cancel(); // Dừng ngay lập tức
              setState(() => _isShowingAlert = true); // Giữ trạng thái chặn ping
              Navigator.pop(dialogContext);
              if (context.mounted) {
                Navigator.popUntil(context, (route) => route.settings.name == '/edit_invoice');
                Navigator.pop(context);
              }
            },
            child: const Text('THOÁT RA'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              setState(() => _isShowingAlert = false);
              _startPingTimer(); // Restart and try again
            },
            child: const Text('KIỂM TRA LẠI'),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isShowingAlert = false);
      }
    });
  }

  Future<void> _takeTurn() async {
    try {
      await _apiService.takeTurn(_invoiceId!);
      _fetchInvoiceDetails();
      _startPingTimer();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi giành quyền: $e')));
      }
    }
  }

  bool _hasUnsavedBuyerEdits() {
    if (_invoiceData == null) return false;
    final data = _invoiceData!;

    final currentBuyerId = _selectedBuyerId;
    final initialBuyerId = data['buyerId'];

    final currentBuyerCode = _buyerCodeController.text.trim();
    final initialBuyerCode = (data['buyerCode']?.toString() ?? '').trim();

    final currentName = _buyerNameController.text.trim();
    final initialName = (data['buyerNameSnapshot']?.toString() ?? '').trim();

    final currentAddress = _addressController.text.trim();
    final initialAddress = (data['addressSnapshot']?.toString() ?? '').trim();

    final currentPhone = _phoneController.text.trim();
    final initialPhone = (data['phoneNumberSnapshot']?.toString() ?? '').trim();

    final currentIdCard = _idCardController.text.trim();
    final initialIdCard = (data['idCardNumberSnapshot']?.toString() ?? '').trim();

    final currentEmail = _emailController.text.trim();
    final initialEmail = (data['emailSnapshot']?.toString() ?? '').trim();

    final currentTaxId = _taxIdController.text.trim();
    final initialTaxId = (data['taxIdSnapshot']?.toString() ?? '').trim();

    final double? initialLat = data['latSnapshot'] != null ? (data['latSnapshot'] as num).toDouble() : null;
    final double? initialLng = data['lngSnapshot'] != null ? (data['lngSnapshot'] as num).toDouble() : null;

    return currentBuyerId != initialBuyerId ||
        currentBuyerCode != initialBuyerCode ||
        currentName != initialName ||
        currentAddress != initialAddress ||
        currentPhone != initialPhone ||
        currentIdCard != initialIdCard ||
        currentEmail != initialEmail ||
        currentTaxId != initialTaxId ||
        _selectedLat != initialLat ||
        _selectedLng != initialLng;
  }

  Future<void> _finishInvoiceWithPrintOption(bool autoPrint, String printType) async {
    setState(() => _isLoading = true);
    try {
      if (_hasUnsavedBuyerEdits()) {
        await _apiService.updateInvoice(_invoiceId!, {
          'buyerId': _selectedBuyerId,
          'buyerNameSnapshot': _buyerNameController.text.trim(),
          'latSnapshot': _selectedLat,
          'lngSnapshot': _selectedLng,
          'addressSnapshot': _addressController.text.trim(),
          'phoneNumberSnapshot': _phoneController.text.trim(),
          'idCardNumberSnapshot': _idCardController.text.trim(),
          'emailSnapshot': _emailController.text.trim(),
          'taxIdSnapshot': _taxIdController.text.trim(),
        });
      }

      await _apiService.post('/invoice/finish/invoiceId/$_invoiceId', {});

      if (autoPrint) {
        await _apiService.createPrintJob(
          invoiceId: _invoiceId!,
          printType: printType,
          priorityNum: 0,
        );
      }

      if (mounted) {
        final message = autoPrint
            ? 'Đã lưu và đưa hóa đơn vào hàng chờ in!'
            : 'Đã lưu hóa đơn thành công!';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isShowingAlert = false; // Re-enable ping if failed
          _isLoading = false;
        });
        _startPingTimer();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi lưu hóa đơn: $e')));
      }
    }
  }

  Future<void> _deleteInvoice() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: const Text(
            'Bạn có chắc chắn muốn xóa hóa đơn này không? Bạn có thể khôi phục lại từ Thùng rác.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              child: const Text('XÓA'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    _pingTimer?.cancel();
    setState(() {
      _isShowingAlert = true;
      _isLoading = true;
    });

    try {
      await _apiService.deleteInvoice(_invoiceId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xóa hóa đơn thành công')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isShowingAlert = false;
          _isLoading = false;
        });
        _startPingTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xóa hóa đơn: $e')),
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_invoiceId == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) {
        _invoiceId = args;
      } else if (args is Map<String, dynamic>) {
        _invoiceId = args['invoiceId'];
      }
      if (_invoiceId != null) {
        _fetchInvoiceDetails();
      }
    }
  }

  Future<void> _fetchInvoiceDetails() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getInvoice(_invoiceId!);
      if (mounted) {
        setState(() {
          _invoiceData = data;
          _selectedBuyerId = data['buyerId'];
          _buyerCodeController.text = data['buyerCode']?.toString() ?? '';
          _buyerNameController.text = data['buyerNameSnapshot']?.toString() ?? '';
          _addressController.text = data['addressSnapshot']?.toString() ?? '';
          _phoneController.text = data['phoneNumberSnapshot']?.toString() ?? '';
          _idCardController.text = data['idCardNumberSnapshot']?.toString() ?? '';
          _emailController.text = data['emailSnapshot']?.toString() ?? '';
          _taxIdController.text = data['taxIdSnapshot']?.toString() ?? '';
          _selectedLat = data['latSnapshot'] != null ? (data['latSnapshot'] as num).toDouble() : null;
          _selectedLng = data['lngSnapshot'] != null ? (data['lngSnapshot'] as num).toDouble() : null;
          _isLoading = false;
        });
        if (!_hasScrolledOnEntry) {
          _hasScrolledOnEntry = true;
          _scrollToBottom();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải thông tin: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _lookupBuyer() async {
    final code = _buyerCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isFetchingBuyer = true);
    try {
      final buyer = await _apiService.getBuyerByCode(code);
      if (mounted) {
        setState(() {
          _selectedBuyerId = buyer['buyerId'];
          _buyerNameController.text = buyer['buyerName'] ?? '';
          _selectedLat = buyer['lat'] != null ? (buyer['lat'] as num).toDouble() : null;
          _selectedLng = buyer['lng'] != null ? (buyer['lng'] as num).toDouble() : null;
          _addressController.text = buyer['address'] ?? '';
          _phoneController.text = buyer['phoneNumber'] ?? '';
          _idCardController.text = buyer['idCardNumber'] ?? '';
          _emailController.text = buyer['email'] ?? '';
          _taxIdController.text = buyer['taxId'] ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tìm thấy mã khách hàng: $code')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingBuyer = false);
    }
  }

  Future<void> _searchBuyerAdvanced() async {
    final buyer = await Navigator.pushNamed(context, '/buyer_search');
    if (buyer != null && buyer is Map<String, dynamic>) {
      if (mounted) {
        setState(() {
          _selectedBuyerId = buyer['buyerId'];
          _buyerCodeController.text = buyer['buyerCode'] ?? '';
          _buyerNameController.text = buyer['buyerName'] ?? '';
          _selectedLat = buyer['lat'] != null ? (buyer['lat'] as num).toDouble() : null;
          _selectedLng = buyer['lng'] != null ? (buyer['lng'] as num).toDouble() : null;
          _addressController.text = buyer['address'] ?? '';
          _phoneController.text = buyer['phoneNumber'] ?? '';
          _idCardController.text = buyer['idCardNumber'] ?? '';
          _emailController.text = buyer['email'] ?? '';
          _taxIdController.text = buyer['taxId'] ?? '';
        });
      }
    }
  }

  Future<void> _lookupVietQR() async {
    final taxId = _taxIdController.text.trim();
    if (taxId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mã số thuế')),
      );
      return;
    }

    setState(() => _isFetchingBusiness = true);
    try {
      final business = await _apiService.fetchVietQRBusiness(taxId);
      if (business != null) {
        setState(() {
          _buyerNameController.text = business['name'] ?? '';
          _addressController.text = business['address'] ?? '';
        });

        final address = business['address'];
        if (address != null && address.isNotEmpty) {
          final coords = await _apiService.googleGeocode(address);
          if (coords != null) {
            setState(() {
              _selectedLat = coords['lat'];
              _selectedLng = coords['lng'];
            });
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã tự động điền thông tin doanh nghiệp')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không tìm thấy thông tin doanh nghiệp cho MST này')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi truy vấn thông tin doanh nghiệp: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingBusiness = false);
      }
    }
  }

  Future<void> _updateBuyerInfo() async {
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      setState(() {
        _isBuyerInfoExpanded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng kiểm tra lại thông tin khách hàng')),
      );
      return;
    }

    try {
      await _apiService.updateInvoice(_invoiceId!, {
        'buyerId': _selectedBuyerId,
        'buyerNameSnapshot': _buyerNameController.text.trim(),
        'latSnapshot': _selectedLat,
        'lngSnapshot': _selectedLng,
        'addressSnapshot': _addressController.text.trim(),
        'phoneNumberSnapshot': _phoneController.text.trim(),
        'idCardNumberSnapshot': _idCardController.text.trim(),
        'emailSnapshot': _emailController.text.trim(),
        'taxIdSnapshot': _taxIdController.text.trim(),
      });
      if (mounted) {
        setState(() {
          if (_invoiceData != null) {
            _invoiceData!['buyerId'] = _selectedBuyerId;
            _invoiceData!['buyerCode'] = _buyerCodeController.text.trim();
            _invoiceData!['buyerNameSnapshot'] = _buyerNameController.text.trim();
            _invoiceData!['addressSnapshot'] = _addressController.text.trim();
            _invoiceData!['phoneNumberSnapshot'] = _phoneController.text.trim();
            _invoiceData!['idCardNumberSnapshot'] = _idCardController.text.trim();
            _invoiceData!['emailSnapshot'] = _emailController.text.trim();
            _invoiceData!['taxIdSnapshot'] = _taxIdController.text.trim();
            _invoiceData!['latSnapshot'] = _selectedLat;
            _invoiceData!['lngSnapshot'] = _selectedLng;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật thông tin thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        if (errorMessage.contains('Code mismatch!')) {
          final nextCode = errorMessage.split('is ').last;
          errorMessage = 'Nhảy số! Mã tiếp theo cho khách hàng phải là $nextCode';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cập nhật: $errorMessage')),
        );
      }
    }
  }

  void _showSaveConfirmationDialog() {
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      setState(() {
        _isBuyerInfoExpanded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng kiểm tra lại thông tin khách hàng')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        final dialogColorScheme = Theme.of(dialogContext).colorScheme;

        Future<Map<String, bool>> checkPrintJobStatus() async {
          if (_invoiceId == null) return {'Pending': false, 'Printing': false, 'Completed': false};
          try {
            final jobs = await _apiService.getPrintJobs(invoiceId: _invoiceId);
            return {
              'Pending': jobs.any((job) => job['printStatus'] == 'Pending'),
              'Printing': jobs.any((job) => job['printStatus'] == 'Printing'),
              'Completed': jobs.any((job) => job['printStatus'] == 'Completed'),
            };
          } catch (_) {
            return {'Pending': false, 'Printing': false, 'Completed': false};
          }
        }

        return AlertDialog(
          title: const Text('Xác nhận lưu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Bạn có chắc chắn muốn hoàn tất và lưu hóa đơn này không?'),
              FutureBuilder<Map<String, bool>>(
                future: checkPrintJobStatus(),
                builder: (futureContext, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Đang kiểm tra hàng chờ in...',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  final statusMap = snapshot.data;
                  if (statusMap == null) return const SizedBox.shrink();

                  final hasPending = statusMap['Pending'] ?? false;
                  final hasPrinting = statusMap['Printing'] ?? false;
                  final hasCompleted = statusMap['Completed'] ?? false;

                  if (hasPending || hasPrinting || hasCompleted) {
                    String msg = '';
                    Color bannerColor = Colors.amber;
                    IconData bannerIcon = Icons.warning_amber_rounded;

                    if (hasPending) {
                      msg = 'Lưu ý: Có bản in của hóa đơn này đang chờ xử lý.';
                      bannerColor = Colors.orange;
                      bannerIcon = Icons.hourglass_empty;
                    } else if (hasPrinting) {
                      msg = 'Lưu ý: Hóa đơn này đang được tiến hành in.';
                      bannerColor = Colors.blue;
                      bannerIcon = Icons.print;
                    } else if (hasCompleted) {
                      msg = 'Thông báo: Hóa đơn này đã được in thành công trước đó.';
                      bannerColor = Colors.green;
                      bannerIcon = Icons.check_circle_outline;
                    }

                    return Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: bannerColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(bannerIcon, color: bannerColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              msg,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(futureContext).colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(height: 20),
              // Stacked print buttons inside the dialog body
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: dialogColorScheme.primaryContainer,
                  foregroundColor: dialogColorScheme.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  _pingTimer?.cancel();
                  setState(() => _isShowingAlert = true);
                  Navigator.pop(dialogContext);
                  _finishInvoiceWithPrintOption(true, 'Original');
                },
                icon: const Icon(Icons.print),
                label: const Text('Lưu và in 1 bản (Bản gốc)'),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: dialogColorScheme.secondaryContainer,
                  foregroundColor: dialogColorScheme.onSecondaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  _pingTimer?.cancel();
                  setState(() => _isShowingAlert = true);
                  Navigator.pop(dialogContext);
                  _finishInvoiceWithPrintOption(true, 'Triplicate');
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('Lưu và in 3 bản (Liên ba)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: dialogColorScheme.primary,
                foregroundColor: dialogColorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                _pingTimer?.cancel();
                setState(() => _isShowingAlert = true);
                Navigator.pop(dialogContext);
                _finishInvoiceWithPrintOption(false, '');
              },
              child: const Text('LƯU KHÔNG IN'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleBackNavigation() async {
    final colorScheme = Theme.of(context).colorScheme;
    
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.save_outlined, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text('Lưu hóa đơn?'),
              ),
            ],
          ),
          content: const Text(
            'Bạn có muốn lưu hóa đơn này trước khi thoát không?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('HỦY'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.error,
              ),
              child: const Text('THOÁT KHÔNG LƯU'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const Text('LƯU NGAY'),
            ),
          ],
        );
      },
    );

    if (result == 'save') {
      _showSaveConfirmationDialog();
    } else if (result == 'discard') {
      _pingTimer?.cancel();
      setState(() => _isShowingAlert = true);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chỉnh sửa hóa đơn')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final lineItems = (_invoiceData?['lineItems'] as List?) ?? [];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Sửa ${_invoiceData?['invoiceCode'] ?? 'Hóa đơn'}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBackNavigation,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchInvoiceDetails,
              tooltip: 'Làm mới',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deleteInvoice,
              tooltip: 'Xóa hóa đơn',
            ),
          ],
        ),
        body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thông tin chung (Readonly)
            Card(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thông tin chung', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _invoiceData?['invoiceCode'],
                      decoration: const InputDecoration(labelText: 'Mã hóa đơn', border: OutlineInputBorder()),
                      readOnly: true,
                      enabled: false,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Thông tin khách hàng (Editable - Collapsible)
            Card(
              color: colorScheme.surfaceContainer,
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isBuyerInfoExpanded = !_isBuyerInfoExpanded;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline_rounded,
                                      color: _isBuyerInfoExpanded ? colorScheme.primary : colorScheme.outline,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Thông tin khách hàng',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: _isBuyerInfoExpanded ? colorScheme.primary : colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isBuyerInfoExpanded) ...[
                                    TextButton.icon(
                                      onPressed: _updateBuyerInfo,
                                      icon: const Icon(Icons.save),
                                      label: const Text('Lưu'),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Icon(
                                    _isBuyerInfoExpanded
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    color: _isBuyerInfoExpanded ? colorScheme.primary : colorScheme.outline,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox.shrink(),
                        secondChild: Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _buyerCodeController,
                                      decoration: const InputDecoration(
                                        labelText: 'Mã khách hàng (Tùy chọn)',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onFieldSubmitted: (_) => _lookupBuyer(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _isFetchingBuyer
                                      ? const Padding(
                                          padding: EdgeInsets.all(12.0),
                                          child: SizedBox(
                                              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                        )
                                      : Row(
                                          children: [
                                            IconButton.filled(
                                              onPressed: _lookupBuyer,
                                              icon: const Icon(Icons.person_search),
                                              tooltip: 'Truy vấn nhanh theo mã',
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton.filledTonal(
                                              onPressed: _searchBuyerAdvanced,
                                              icon: const Icon(Icons.search),
                                              tooltip: 'Tìm kiếm nâng cao',
                                            ),
                                          ],
                                        ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _taxIdController,
                                decoration: InputDecoration(
                                  labelText: 'Mã số thuế (Tùy chọn)',
                                  suffixIcon: _isFetchingBusiness
                                    ? const Padding(
                                        padding: EdgeInsets.all(12.0),
                                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.search),
                                        onPressed: _lookupVietQR,
                                        tooltip: 'Lấy thông tin từ MST',
                                      ),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _buyerNameController,
                                decoration: const InputDecoration(labelText: 'Tên khách hàng *', border: OutlineInputBorder()),
                                validator: (value) => value == null || value.trim().isEmpty ? 'Vui lòng nhập tên khách hàng' : null,
                              ),
                              const SizedBox(height: 16),
                              AddressSearchField(
                                controller: _addressController,
                                initialLat: _selectedLat,
                                initialLng: _selectedLng,
                                initialAddress: _addressController.text,
                                onLocationSelected: (lat, lng) {
                                  setState(() {
                                    _selectedLat = lat;
                                    _selectedLng = lng;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _phoneController,
                                decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder()),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _idCardController,
                                decoration: const InputDecoration(labelText: 'Số CMND/CCCD (Tùy chọn)', border: OutlineInputBorder()),
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _emailController,
                                decoration: const InputDecoration(labelText: 'Email (Tùy chọn)', border: OutlineInputBorder()),
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) return null;
                                  final emailRegex = RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
                                  if (!emailRegex.hasMatch(value.trim())) {
                                    return 'Định dạng email không hợp lệ';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        crossFadeState: _isBuyerInfoExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 300),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Danh sách Line Items
            LayoutBuilder(
              builder: (headerContext, constraints) {
                final isNarrow = constraints.maxWidth < 450;
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sản phẩm / Dịch vụ',
                        style: Theme.of(headerContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openPriceListSelection,
                              icon: const Icon(Icons.request_quote),
                              label: const Text('Báo giá'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _openCreateLineItem(),
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm dòng'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                } else {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sản phẩm / Dịch vụ',
                        style: Theme.of(headerContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _openPriceListSelection,
                            icon: const Icon(Icons.request_quote),
                            label: const Text('Bảng báo giá'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _openCreateLineItem(),
                            icon: const Icon(Icons.add),
                            label: const Text('Thêm dòng'),
                          ),
                        ],
                      ),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            if (lineItems.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Chưa có sản phẩm nào')))
            else ...[
              if (_pickedIndex != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: colorScheme.onPrimaryContainer, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đang chọn sản phẩm để di chuyển. Hãy bấm vào nút "Chèn vào đây" để thay đổi vị trí.',
                            style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _pickedIndex = null;
                            });
                          },
                          child: Text('HỦY', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Builder(
                  builder: (builderContext) {
                  final List<Map<String, dynamic>> itemsWithOrigIndex = [];
                  for (int i = 0; i < lineItems.length; i++) {
                    final itm = Map<String, dynamic>.from(lineItems[i]);
                    itm['orig_index'] = i;
                    itemsWithOrigIndex.add(itm);
                  }

                  final filteredItems = itemsWithOrigIndex.where((itm) {
                    final name = (itm['itemNameSnapshot'] ?? '').toString();
                    return StringUtils.containsUnaccented(name, _localSearchQuery);
                  }).toList();

                  if (filteredItems.isEmpty) {
                    return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Không tìm thấy sản phẩm phù hợp')));
                  }

                  if (_pickedIndex == null) {
                    return ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredItems.length,
                      onReorder: (oldIndex, newIndex) {
                        final oldOrigIndex = filteredItems[oldIndex]['orig_index'];
                        var newOrigIndex = newIndex < filteredItems.length
                            ? filteredItems[newIndex]['orig_index']
                            : filteredItems[newIndex - 1]['orig_index'] + 1;
                        
                        _onReorderLineItems(lineItems, oldOrigIndex, newOrigIndex);
                      },
                      itemBuilder: (context, idx) {
                        final item = filteredItems[idx];
                        final origIndex = item['orig_index'];
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(item['lineItemId']),
                          index: idx,
                          child: LineItemCard(
                            item: item,
                            index: origIndex,
                            isPicked: false,
                            isHighlighted: (_highlightedLineItemId != null &&
                                _highlightedLineItemId == item['lineItemId']?.toString()) ||
                                _highlightedLineItemIds.contains(item['lineItemId']?.toString()),
                            onTap: () {
                              final tappedFilteredIdx = idx;
                              setState(() {
                                _pickedIndex = origIndex;
                              });
                              // Compensate scroll for insert slots appearing above
                              WidgetsBinding.instance.addPostFrameCallback((_) async {
                                if (mounted) {
                                  // Wait for the slot expansion and container resizing animation to complete first
                                  await Future.delayed(const Duration(milliseconds: 310));
                                  if (mounted && _scrollController.hasClients) {
                                    const slotHeight = 44.0 + 8.0; // slot height + vertical margin
                                    final extraOffset = tappedFilteredIdx * slotHeight;
                                    final target = (_scrollController.offset + extraOffset)
                                        .clamp(0.0, _scrollController.position.maxScrollExtent);
                                    _scrollController.animateTo(
                                      target,
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeOut,
                                    );
                                  }
                                }
                              });
                            },
                            onEdit: () => _openEditLineItem(item),
                            onDelete: () => _confirmDeleteLineItem(item),
                          ),
                        );
                      },
                    );
                  } else {
                    return Column(
                      children: [
                        _buildInsertSlot(builderContext, filteredItems[0]['orig_index'], _pickedIndex!, lineItems),
                        for (int j = 0; j < filteredItems.length; j++) ...[
                          LineItemCard(
                            item: filteredItems[j],
                            index: filteredItems[j]['orig_index'],
                            isPicked: _pickedIndex == filteredItems[j]['orig_index'],
                            isHighlighted: (_highlightedLineItemId != null &&
                                _highlightedLineItemId == filteredItems[j]['lineItemId']) ||
                                _highlightedLineItemIds.contains(filteredItems[j]['lineItemId']?.toString()),
                            onTap: () {
                              setState(() {
                                if (_pickedIndex == filteredItems[j]['orig_index']) {
                                  _pickedIndex = null;
                                } else {
                                  _pickedIndex = filteredItems[j]['orig_index'];
                                }
                              });
                            },
                            onEdit: () => _openEditLineItem(filteredItems[j]),
                            onDelete: () => _confirmDeleteLineItem(filteredItems[j]),
                          ),
                          _buildInsertSlot(
                            builderContext,
                            j < filteredItems.length - 1 
                                ? filteredItems[j + 1]['orig_index'] 
                                : filteredItems[j]['orig_index'] + 1,
                            _pickedIndex!,
                            lineItems,
                          ),
                        ],
                      ],
                    );
                  }
                },
              ),
            ),
          ],
            // Quick-add buttons at the bottom of the list
            if (!_isLoading) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.outlined(
                    onPressed: _openPriceListSelection,
                    icon: const Icon(Icons.request_quote),
                    tooltip: 'Thêm từ bảng báo giá',
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filled(
                    onPressed: () => _openCreateLineItem(),
                    icon: const Icon(Icons.add),
                    tooltip: 'Thêm dòng mới',
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tổng cộng:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                      .format((_invoiceData?['totalAmount'] as num?)?.toDouble() ?? 0),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _showSaveConfirmationDialog,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('HOÀN TẤT & LƯU HÓA ĐƠN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _onReorderLineItems(List<dynamic> lineItems, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final movedItem = lineItems[oldIndex];
    final String lineItemId = movedItem['lineItemId'];

    setState(() {
      final item = lineItems.removeAt(oldIndex);
      lineItems.insert(newIndex, item);
    });

    String? prevId;
    String? nextId;

    if (newIndex > 0) {
      prevId = lineItems[newIndex - 1]['lineItemId'];
    }
    if (newIndex < lineItems.length - 1) {
      nextId = lineItems[newIndex + 1]['lineItemId'];
    }

    try {
      await _apiService.changeLineItemOrder(_invoiceId!, lineItemId, prevId, nextId);
      // Không cần fetch lại ở đây để tránh chớp màn hình, vì UI đã update qua setState phía trên
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi đổi vị trí: $e')));
        _fetchInvoiceDetails(); // Revert on failure
      }
    }
  }

  Widget _buildInsertSlot(BuildContext context, int targetIndex, int? pickedIndex, List<dynamic> lineItems) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isVisible = pickedIndex != null && 
        targetIndex != pickedIndex && 
        targetIndex != pickedIndex + 1;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      height: isVisible ? 44 : 0,
      margin: EdgeInsets.symmetric(vertical: isVisible ? 4 : 0),
      decoration: BoxDecoration(
        color: isVisible 
            ? colorScheme.primaryContainer.withValues(alpha: 0.12) 
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isVisible 
              ? colorScheme.primary.withValues(alpha: 0.4) 
              : Colors.transparent,
          width: isVisible ? 1.0 : 0.0,
        ),
      ),
      child: ClipRect(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isVisible ? 1.0 : 0.0,
          child: AnimatedSlide(
            offset: isVisible ? Offset.zero : const Offset(0, 1.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: Center(
              child: InkWell(
                onTap: isVisible ? () {
                  _onReorderLineItems(lineItems, pickedIndex, targetIndex);
                  setState(() {
                    _pickedIndex = null;
                  });
                } : null,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Chèn vào đây',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openCreateLineItem() async {
    final result = await Navigator.pushNamed(
      context,
      '/create_line_item',
      arguments: {'invoiceId': _invoiceId!},
    );
    if (result == true) {
      await _fetchInvoiceDetails();
      if (!mounted) return;
      // Scroll to bottom and highlight the last added item
      final lineItems = (_invoiceData?['lineItems'] as List?) ?? [];
      if (lineItems.isNotEmpty) {
        final lastItem = lineItems.last;
        final lastId = lastItem['lineItemId']?.toString();
        setState(() => _highlightedLineItemId = lastId);
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted && _scrollController.hasClients) {
          await _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
          );
        }
        // Auto-clear highlight after animation
        await Future.delayed(const Duration(milliseconds: 1300));
        if (mounted) setState(() => _highlightedLineItemId = null);
      }
    }
  }

  void _openPriceListSelection() async {
    final result = await Navigator.pushNamed(
      context,
      '/pricelist_picker',
      arguments: _selectedBuyerId,
    );

    if (result != null && result is List<Map<String, dynamic>> && result.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        for (final item in result) {
          await _apiService.createLineItem(_invoiceId!, {
            "itemId": item['itemId'],
            "unitId": item['unitId'],
            "itemNameSnapshot": item['itemName'],
            "unitNameSnapshot": item['unitName'],
            "quantity": (item['quantity'] as num?)?.toInt() ?? 1,
            "unitPriceCustom": item['price'],
          });
        }
        await _fetchInvoiceDetails();
        if (!mounted) return;
        // Scroll to bottom and highlight ALL newly added items
        final lineItems = (_invoiceData?['lineItems'] as List?) ?? [];
        if (lineItems.isNotEmpty) {
          // The last N items correspond to the ones just added
          final addedCount = result.length;
          final addedIds = lineItems
              .skip((lineItems.length - addedCount).clamp(0, lineItems.length))
              .map((itm) => itm['lineItemId']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
          setState(() => _highlightedLineItemIds = addedIds);
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted && _scrollController.hasClients) {
            await _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
            );
          }
          await Future.delayed(const Duration(milliseconds: 1300));
          if (mounted) setState(() => _highlightedLineItemIds = {});
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi khi thêm mặt hàng từ báo giá: $e')),
          );
        }
      }
    }
  }

  void _openEditLineItem(Map<String, dynamic> lineItem) async {
    final result = await Navigator.pushNamed(
      context,
      '/create_line_item',
      arguments: {
        'invoiceId': _invoiceId!,
        'existingLineItem': lineItem,
      },
    );
    if (result == true) _fetchInvoiceDetails();
  }

  void _confirmDeleteLineItem(Map<String, dynamic> lineItem) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa dòng "${lineItem['itemNameSnapshot']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('HỦY')),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await _apiService.deleteLineItem(lineItem['lineItemId'].toString());
                if (!mounted) return;
                _fetchInvoiceDetails();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi xóa: $e')));
                }
              }
            },
            child: const Text('XÓA', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _scrollController.dispose();
    _buyerCodeController.dispose();
    _buyerNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _idCardController.dispose();
    _emailController.dispose();
    _taxIdController.dispose();
    super.dispose();
  }
}
