// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:typed_data';
import 'package:flutter/material.dart';

String registerPdfPreview(Uint8List bytes) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  
  // Generate a unique view type ID for each PDF render to ensure it refreshes correctly
  final viewId = 'pdf-preview-${DateTime.now().microsecondsSinceEpoch}';
  
  // Register the iframe using modern dart:ui_web
  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int viewId) => html.IFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%',
  );
  
  return viewId;
}

Widget buildPreviewWidget(BuildContext context, Uint8List bytes, String format, {String? viewId}) {
  final colorScheme = Theme.of(context).colorScheme;
  
  if (format == 'pdf') {
    // If a viewId is already registered and provided, we use it directly!
    // If not, we fall back to registering a new temporary one.
    var actualViewId = viewId;
    if (actualViewId == null) {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      actualViewId = 'pdf-preview-fallback-${DateTime.now().millisecondsSinceEpoch}';
      ui_web.platformViewRegistry.registerViewFactory(
        actualViewId,
        (int viewId) => html.IFrameElement()
          ..src = url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%',
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: HtmlElementView(viewType: actualViewId),
      ),
    );
  } else {
    // Excel doesn't have a native inline browser renderer like PDF,
    // so we show a clean message that it's compiled and ready for download.
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.table_chart_rounded, size: 64, color: Colors.green.withValues(alpha: 0.8)),
          const SizedBox(height: 16),
          const Text(
            'Bảng tính Excel (.xlsx) đã sẵn sàng',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Nhấn nút Lưu hoặc Gửi để tải xuống tệp tin',
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

void downloadFile(Uint8List bytes, String fileName, String mimeType, String downloadUrl) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute("download", fileName)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
