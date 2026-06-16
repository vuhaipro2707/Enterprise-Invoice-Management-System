import 'package:flutter/material.dart';
import '../../widgets/buyer_list_widget.dart';
import 'create_buyer_screen.dart';
import 'buyer_detail_screen.dart';

class BuyerManagementScreen extends StatefulWidget {
  const BuyerManagementScreen({super.key});

  @override
  State<BuyerManagementScreen> createState() => _BuyerManagementScreenState();
}

class _BuyerManagementScreenState extends State<BuyerManagementScreen> {
  final GlobalKey<BuyerListWidgetState> _listKey = GlobalKey<BuyerListWidgetState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý người mua'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () {
              Navigator.pushNamed(context, '/buyer_trash').then((_) {
                _listKey.currentState?.refresh(isQuiet: true);
              });
            },
            tooltip: 'Thùng rác',
          ),
          IconButton(
            onPressed: () => _listKey.currentState?.refresh(isQuiet: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới dữ liệu',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (builderContext) => const CreateBuyerScreen()),
          );
          if (result == true) {
            _listKey.currentState?.refresh(isQuiet: true);
          }
        },
        tooltip: 'Thêm người mua mới',
        child: const Icon(Icons.add),
      ),
      body: BuyerListWidget(
        key: _listKey,
        onBuyerSelected: (buyer) async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (builderContext) => BuyerDetailScreen(buyer: buyer),
            ),
          );
          if (result == true) {
            _listKey.currentState?.refresh(isQuiet: true);
          }
        },
      ),
    );
  }
}