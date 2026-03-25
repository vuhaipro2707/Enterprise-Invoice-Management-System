import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Nhớ chạy 'flutter pub add flutter_dotenv'

// 1. Chuyển hàm main thành Future để dùng await nạp Env
Future<void> main() async {
  // Bắt buộc phải có dòng này khi dùng async trong main
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Nạp file .env từ assets
    await dotenv.load(fileName: ".env");
    print("Đã nạp file .env thành công!");
  } catch (e) {
    print("Lỗi nạp file .env: $e. Kiểm tra lại pubspec.yaml nhé!");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Invoice App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const InvoiceScreen(),
    );
  }
}

class InvoiceScreen extends StatelessWidget {
  const InvoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 2. Lấy biến BACKEND_PORT từ file .env
    final String backendPort = dotenv.env['BACKEND_PORT'] ?? "Chưa cấu hình";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Hệ Thống Hóa Đơn - Tablet Mode"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Row(
        children: [
          // BÊN TRÁI: DANH MỤC SẢN PHẨM (Chiếm 2 phần)
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[100],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inventory, size: 80, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text(
                    "DANH SÁCH SẢN PHẨM",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  // HIỂN THỊ BIẾN ENV RA ĐÂY
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Text(
                      "📍 Backend đang chạy tại Port: $backendPort",
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // BÊN PHẢI: CHI TIẾT HÓA ĐƠN (Chiếm 1 phần)
          Expanded(
            flex: 1,
            child: Card(
              elevation: 4,
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      "HÓA ĐƠN TẠM",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const Divider(height: 30),
                    // Giả lập danh sách item trong hóa đơn
                    const ListTile(
                      leading: CircleAvatar(child: Text("1")),
                      title: Text("Sản phẩm mẫu A"),
                      trailing: Text("100.000đ"),
                    ),
                    const Spacer(),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Tổng cộng:", style: TextStyle(fontSize: 18)),
                          Text("100.000đ", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          // In ra console để debug khi bấm nút
                          print("Đang gửi yêu cầu đến http://localhost:$backendPort/api/v1/invoices");
                        },
                        icon: const Icon(Icons.print),
                        label: const Text("XUẤT HÓA ĐƠN & IN", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}