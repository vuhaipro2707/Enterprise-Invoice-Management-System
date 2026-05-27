import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'services/api_service.dart';
import 'services/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/dashboard/qr_scanner_screen.dart';
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
import 'screens/pricelist/export_pricelist_screen.dart';
import 'screens/print/print_queue_management_screen.dart';
import 'screens/settings/settings_screen.dart';

/// Global RouteObserver to allow screens to detect when they are returned to.
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Lỗi nạp file .env: $e');
  }

  await ApiService().init();

  // Proactively clean up any temporary update APK installers from previous installations to save user storage space
  try {
    if (!kIsWeb) {
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/app-release.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
        debugPrint('🧹 Đã dọn dẹp file cài đặt APK tạm thời thành công!');
      }
    }
  } catch (e) {
    debugPrint('Lỗi khi dọn dẹp APK: $e');
  }

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
    final isDark = themeProvider.isDarkMode;

    final lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );

    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    final currentTheme = isDark ? darkTheme : lightTheme;

    return MaterialApp(
      navigatorObservers: [routeObserver],
      title: 'Invoice App',
      debugShowCheckedModeBanner: false,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: lightTheme,
      darkTheme: darkTheme,
      initialRoute: ApiService().isAuthenticated ? '/dashboard' : '/login',
      builder: (context, child) {
        final double screenWidth = MediaQuery.of(context).size.width;
        final double constrainedWidth = screenWidth > 1200 ? 1200 : screenWidth;
        final bool isWide = screenWidth > 1200;

        return Material(
          color: currentTheme.colorScheme.surfaceContainerLowest,
          child: Stack(
            children: [
              // 1. Ambient Gradient Blob 1 (Top Left)
              Positioned(
                top: -150,
                left: -150,
                child: Container(
                  width: 500,
                  height: 500,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        currentTheme.colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                        currentTheme.colorScheme.primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // 2. Ambient Gradient Blob 2 (Bottom Right)
              Positioned(
                bottom: -200,
                right: -200,
                child: Container(
                  width: 600,
                  height: 600,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        currentTheme.colorScheme.tertiary.withValues(alpha: isDark ? 0.12 : 0.06),
                        currentTheme.colorScheme.tertiary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // 3. Dot Grid overlay pattern (only visible in margins when wide)
              Positioned.fill(
                child: CustomPaint(
                  painter: DotPatternPainter(
                    color: currentTheme.colorScheme.onSurface.withValues(alpha: isDark ? 0.04 : 0.02),
                  ),
                ),
              ),
              // 4. Central app content (floating panel when wide)
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  margin: isWide
                      ? const EdgeInsets.symmetric(vertical: 8, horizontal: 16)
                      : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: currentTheme.colorScheme.surface,
                    borderRadius: isWide ? BorderRadius.circular(24) : BorderRadius.zero,
                    border: isWide
                        ? Border.all(
                            color: currentTheme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                            width: 1.0,
                          )
                        : null,
                    boxShadow: isWide
                        ? [
                            BoxShadow(
                              color: currentTheme.colorScheme.shadow.withValues(alpha: isDark ? 0.25 : 0.08),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                              spreadRadius: -4,
                            ),
                            BoxShadow(
                              color: currentTheme.colorScheme.primary.withValues(alpha: isDark ? 0.05 : 0.02),
                              blurRadius: 15,
                              offset: const Offset(0, 4),
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  clipBehavior: isWide ? Clip.antiAlias : Clip.none,
                  child: isWide
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(23),
                          clipBehavior: Clip.antiAlias,
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              size: Size(constrainedWidth, MediaQuery.of(context).size.height),
                            ),
                            child: child ?? const SizedBox.shrink(),
                          ),
                        )
                      : MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            size: Size(constrainedWidth, MediaQuery.of(context).size.height),
                          ),
                          child: child ?? const SizedBox.shrink(),
                        ),
                ),
              ),
            ],
          ),
        );
      },
      routes: {
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/qr_scanner': (context) => const QRScannerScreen(),
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
        '/export_pricelist': (context) => const ExportPriceListScreen(),
        '/print_management': (context) => const PrintQueueManagementScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}

/// A beautiful background dot matrix/blueprint pattern painter.
class DotPatternPainter extends CustomPainter {
  final Color color;
  const DotPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const double spacing = 24.0;
    for (double x = 0.0; x < size.width; x += spacing) {
      for (double y = 0.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotPatternPainter oldDelegate) =>
      color != oldDelegate.color;
}
