// ignore_for_file: deprecated_member_use

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdfx/pdfx.dart';

String registerPdfPreview(Uint8List bytes) {
  // No-op stub for mobile platforms
  return '';
}

Widget buildPreviewWidget(BuildContext context, Uint8List bytes, String format, {String? viewId}) {
  final colorScheme = Theme.of(context).colorScheme;
  
  if (format == 'pdf') {
    return MobilePdfPreviewWidget(bytes: bytes);
  } else {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.table_chart_rounded, size: 64, color: Colors.green.withValues(alpha: 0.8)),
          const SizedBox(height: 16),
          const Text(
            'Bản xem trước Excel sẵn sàng',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Nhấn nút Lưu hoặc Gửi để xem tệp tin thực tế',
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class MobilePdfPreviewWidget extends StatefulWidget {
  final Uint8List bytes;

  const MobilePdfPreviewWidget({super.key, required this.bytes});

  @override
  State<MobilePdfPreviewWidget> createState() => _MobilePdfPreviewWidgetState();
}

class _MobilePdfPreviewWidgetState extends State<MobilePdfPreviewWidget> {
  late PdfControllerPinch _pdfController;
  bool _hasError = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    try {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openData(widget.bytes),
      );
    } catch (e) {
      _hasError = true;
      _errorMsg = e.toString();
    }
  }

  @override
  void dispose() {
    if (!_hasError) {
      _pdfController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Lỗi hiển thị PDF: $_errorMsg',
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: PdfViewPinch(
        controller: _pdfController,
        scrollDirection: Axis.vertical,
      ),
    );
  }
}

void downloadFile(Uint8List bytes, String fileName, String mimeType, String downloadUrl) async {
  // Save/Download directly on mobile by sharing the in-memory bytes to native files/storage
  final xFile = XFile.fromData(
    bytes,
    name: fileName,
    mimeType: mimeType,
  );
  await Share.shareXFiles(
    [xFile],
    text: 'Báo giá: $fileName',
  );
}
