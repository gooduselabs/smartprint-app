import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Camera permission must be granted at runtime because the manifest declares CAMERA
/// (otherwise Android refuses even the IMAGE_CAPTURE intent).
Future<bool> ensureCamera(BuildContext context) async {
  var s = await Permission.camera.status;
  if (s.isGranted) return true;
  if (!s.isPermanentlyDenied) s = await Permission.camera.request();
  if (s.isGranted) return true;
  if (!context.mounted) return false;
  if (s.isPermanentlyDenied || s.isRestricted) {
    final open = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cần quyền Camera · Camera permission'),
        content: const Text('Hãy bật quyền Camera cho SmartPrint trong Cài đặt để chụp/quét tài liệu.\nPlease allow Camera in Settings to take photos or scan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ · Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Mở cài đặt · Settings')),
        ],
      ),
    );
    if (open == true) await openAppSettings();
  } else {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa cấp quyền Camera · Camera permission denied')));
  }
  return false;
}
