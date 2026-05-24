import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'buyer_detail_screen.dart';

class BuyerTrashScreen extends StatefulWidget {
  const BuyerTrashScreen({super.key});

  @override
  State<BuyerTrashScreen> createState() => _BuyerTrashScreenState();
}

class _BuyerTrashScreenState extends State<BuyerTrashScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _deletedBuyers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDeletedBuyers();
  }

  Future<void> _fetchDeletedBuyers() async {
    setState(() => _isLoading = true);
    try {
      final buyers = await _apiService.getDeletedBuyers();
      if (mounted) {
        setState(() {
          _deletedBuyers = buyers;
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 920;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thùng rác khách hàng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDeletedBuyers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _deletedBuyers.isEmpty
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
                      itemCount: _deletedBuyers.length,
                      itemBuilder: (context, index) {
                        return _buildBuyerCard(_deletedBuyers[index]);
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _deletedBuyers.length,
                      itemBuilder: (context, index) {
                        return _buildBuyerCard(_deletedBuyers[index]);
                      },
                    ),
    );
  }

  Widget _buildBuyerCard(Map<String, dynamic> buyer) {
    final colorScheme = Theme.of(context).colorScheme;
    final code = buyer['buyerCode'] ?? '';
    final name = buyer['buyerName'] ?? '';
    final phone = buyer['phoneNumber'] ?? '';
    final address = buyer['address'] ?? '';

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
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (builderContext) => BuyerDetailScreen(
                buyer: buyer,
                isDeleted: true,
              ),
            ),
          );
          if (result == true) {
            _fetchDeletedBuyers();
          }
        },
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
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (phone.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(Icons.phone, size: 14, color: colorScheme.outline),
                    const SizedBox(width: 6),
                    Text(
                      phone,
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              if (address.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: colorScheme.outline),
                    const SizedBox(width: 6),
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
