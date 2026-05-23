import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';

class PricelistTrashScreen extends StatefulWidget {
  const PricelistTrashScreen({super.key});

  @override
  State<PricelistTrashScreen> createState() => _PricelistTrashScreenState();
}

class _PricelistTrashScreenState extends State<PricelistTrashScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _deletedPriceLists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDeletedPriceLists();
  }

  Future<void> _fetchDeletedPriceLists() async {
    setState(() => _isLoading = true);
    try {
      final lists = await _apiService.getDeletedCustomerPriceLists();
      if (mounted) {
        setState(() {
          _deletedPriceLists = lists;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tải danh sách đã xóa: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _formatDateTime(dynamic timestampStr) {
    if (timestampStr == null) return 'N/A';
    try {
      final date = DateTime.parse(timestampStr.toString());
      return DateFormat('HH:mm dd/MM/yyyy').format(date.toLocal());
    } catch (_) {
      return timestampStr.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 920;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thùng rác bảng báo giá'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDeletedPriceLists,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _deletedPriceLists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 64,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Thùng rác trống',
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.outline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : isDesktop
                  ? GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.2,
                      ),
                      itemCount: _deletedPriceLists.length,
                      itemBuilder: (context, index) {
                        return _buildPriceListCard(_deletedPriceLists[index]);
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _deletedPriceLists.length,
                      itemBuilder: (context, index) {
                        return _buildPriceListCard(_deletedPriceLists[index]);
                      },
                    ),
    );
  }

  Widget _buildPriceListCard(Map<String, dynamic> priceList) {
    final colorScheme = Theme.of(context).colorScheme;
    final description = priceList['description'] ?? 'Không có mô tả';
    final buyerName = priceList['buyer_name'] ?? 'Bảng báo giá chung';
    final buyerCode = priceList['buyer_code'];
    final updatedAt = _formatDateTime(priceList['updated_at']);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await Navigator.pushNamed(
            context,
            '/edit_pricelist',
            arguments: {
              'pricelistId': priceList['customer_price_list_id'],
              'isDeleted': true,
            },
          );
          if (result == true) {
            _fetchDeletedPriceLists();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      buyerCode != null ? '[$buyerCode] $buyerName' : buyerName,
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    'Cập nhật: $updatedAt',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ),
              if (MediaQuery.of(context).size.width > 920) const Spacer() else const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.restore_from_trash_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Xem chi tiết để khôi phục',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
