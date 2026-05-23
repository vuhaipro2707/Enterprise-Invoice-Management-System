import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/settings/device_management_screen.dart';
import 'screens/items/item_management_screen.dart';
import 'screens/buyer/buyer_management_screen.dart';
import 'screens/buyer/buyer_search_screen.dart';
import 'screens/invoice/create_invoice_screen.dart';
import 'screens/invoice/edit_invoice_screen.dart';
import 'screens/invoice/line_item_search_screen.dart';
import 'screens/invoice/create_line_item_screen.dart';
import 'screens/invoice/invoice_management_screen.dart';
import 'screens/invoice/invoice_detail_screen.dart';
import 'screens/pricelist/pricelist_management_screen.dart';
import 'screens/pricelist/create_pricelist_screen.dart';
import 'screens/pricelist/edit_pricelist_screen.dart';
import 'screens/pricelist/pricelist_picker_screen.dart';
import 'screens/pricelist/pricelist_item_picker_screen.dart';
import 'screens/items/item_trash_screen.dart';
import 'screens/buyer/buyer_trash_screen.dart';
import 'screens/invoice/invoice_trash_screen.dart';
import 'screens/pricelist/pricelist_trash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Lỗi nạp file .env: $e');
  }

  await ApiService().init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Invoice App',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      initialRoute: ApiService().isAuthenticated ? '/dashboard' : '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/device_management': (context) => const DeviceManagementScreen(),
        '/item_management': (context) => const ItemManagementScreen(),
        '/buyer_management': (context) => const BuyerManagementScreen(),
        '/buyer_search': (context) => const BuyerSearchScreen(),
        '/create_invoice': (context) => const CreateInvoiceScreen(),
        '/edit_invoice': (context) => const EditInvoiceScreen(),
        '/line_item_search': (context) => const LineItemSearchScreen(),
        '/create_line_item': (context) => const CreateLineItemScreen(invoiceId: ''), // Will get args manually
        '/invoice_management': (context) => const InvoiceManagementScreen(),
        '/invoice_detail': (context) => const InvoiceDetailScreen(),
        '/pricelist_management': (context) => const PriceListManagementScreen(),
        '/create_pricelist': (context) => const CreatePriceListScreen(),
        '/edit_pricelist': (context) => const EditPriceListScreen(),
        '/pricelist_picker': (context) => const PriceListPickerScreen(),
        '/pricelist_item_picker': (context) => const PriceListItemPickerScreen(),
        '/item_trash': (context) => const ItemTrashScreen(),
        '/buyer_trash': (context) => const BuyerTrashScreen(),
        '/invoice_trash': (context) => const InvoiceTrashScreen(),
        '/pricelist_trash': (context) => const PricelistTrashScreen(),
      },
    );
  }
}
