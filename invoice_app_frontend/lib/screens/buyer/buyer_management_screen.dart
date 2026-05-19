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
            onPressed: () => _listKey.currentState?.refresh(),
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
            _listKey.currentState?.refresh();
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
            _listKey.currentState?.refresh();
          }
        },
      ),
    );
  }
}


//                         onPressed: () {
//                           _searchController.clear();
//                           _onSearchChanged('');
//                         },
//                       )
//                     : null,
//                 border: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//               ),
//               onChanged: _onSearchChanged,
//             ),
//           ),
//           Expanded(
//             child: _isLoading
//                 ? const Center(child: CircularProgressIndicator())
//                 : _buyers.isEmpty
//                     ? const Center(child: Text('Không tìm thấy người mua nào'))
//                     : RefreshIndicator(
//                         onRefresh: () async {
//                           _offset = 0;
//                           _hasMore = true;
//                           await _fetchBuyers();
//                         },
//                         child: ListView.builder(
//                           physics: const AlwaysScrollableScrollPhysics(),
//                           controller: _scrollController,
//                           itemCount: _buyers.length + (_isLoadingMore ? 1 : 0),
//                           itemBuilder: (context, index) {
//                             if (index == _buyers.length) {
//                               return const Padding(
//                                 padding: EdgeInsets.symmetric(vertical: 16.0),
//                                 child: Center(child: CircularProgressIndicator()),
//                               );
//                             }
//                             return BuyerCard(
//                               buyer: _buyers[index],
//                               onTap: () async {
//                                 final result = await Navigator.push(
//                                   context,
//                                   MaterialPageRoute(
//                                     builder: (context) => BuyerDetailScreen(buyer: _buyers[index]),
//                                   ),
//                                 );
//                                 if (result == true) {
//                                   _fetchBuyers();
//                                 }
//                               },
//                             );
//                           },
//                         ),
//                       ),
//           ),
//         ],
//       ),
//     );
//   }

//   @override
//   void dispose() {
//     _searchController.dispose();
//     _scrollController.dispose();
//     _debounce?.cancel();
//     super.dispose();
//   }
// }
