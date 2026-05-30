import 'package:flutter/material.dart';
import '../../widgets/buyer_list_widget.dart';
import 'create_buyer_screen.dart';

class BuyerSearchScreen extends StatefulWidget {
  const BuyerSearchScreen({super.key});

  @override
  State<BuyerSearchScreen> createState() => _BuyerSearchScreenState();
}

class _BuyerSearchScreenState extends State<BuyerSearchScreen> {
  final GlobalKey<BuyerListWidgetState> _listKey = GlobalKey<BuyerListWidgetState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tìm kiếm người mua'),
        actions: [
          IconButton(
            onPressed: () => _listKey.currentState?.refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới dữ liệu',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          _listKey.currentState?.unfocusSearch();
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateBuyerScreen()),
          );
          if (context.mounted) {
            _listKey.currentState?.unfocusSearch();
          }
          if (result == true) {
            _listKey.currentState?.refresh();
          }
        },
        tooltip: 'Thêm người mua mới',
        child: const Icon(Icons.add),
      ),
      body: BuyerListWidget(
        key: _listKey,
        showInvoiceButton: false,
        showEditButton: true,
        onBuyerSelected: (buyer) {
          Navigator.pop(context, buyer);
        },
      ),
    );
  }
}

