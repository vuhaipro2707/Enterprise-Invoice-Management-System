// ignore_for_file: deprecated_member_use

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

String registerPdfPreview(Uint8List bytes) {
  // No-op stub for mobile platforms
  return '';
}

Widget buildPreviewWidget(BuildContext context, Uint8List bytes, String format, {String? viewId}) {
  final colorScheme = Theme.of(context).colorScheme;
  
  if (format == 'pdf') {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf_rounded, size: 64, color: Colors.redAccent.withValues(alpha: 0.8)),
          const SizedBox(height: 16),
          const Text(
            'Bản xem trước PDF sẵn sàng',
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
