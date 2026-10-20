import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

/// Turns any exception into a short bilingual (VI / EN) message — never a stack trace.
String friendlyError(Object e) {
  if (e is UserMessage) return e.message;
  if (e is DioException) {
    final code = e.response?.statusCode;
    if (e.type == DioExceptionType.cancel) return 'Đã huỷ · Cancelled';
    if (code == 401 || code == 403) return 'Máy chủ từ chối truy cập ($code) · Access denied';
    if (code == 404) return 'Không tìm thấy (404) · Not found';
    if (code != null) return 'Lỗi máy chủ ($code) · Server error';
    return 'Không có kết nối mạng hoặc máy chủ không phản hồi · No connection';
  }
  if (e is SocketException || e is HttpException) return 'Không có kết nối mạng · No network connection';
  if (e is FileSystemException) {
    final s = '${e.osError?.message}'.toLowerCase();
    if (s.contains('space')) return 'Bộ nhớ máy đã đầy · Not enough storage';
    return 'Không đọc/ghi được tệp · File access error';
  }
  if (e is FormatException) return 'Tệp bị hỏng hoặc không đúng định dạng · Invalid or damaged file';
  if (e is UnsupportedError) return e.message ?? 'Định dạng chưa hỗ trợ · Not supported';
  if (e is PlatformException) {
    final m = '${e.code} ${e.message}'.toLowerCase();
    if (m.contains('permission') || m.contains('denied')) return 'Ứng dụng chưa được cấp quyền · Permission denied';
    if (m.contains('cancel')) return 'Đã huỷ · Cancelled';
    return 'Lỗi hệ thống: ${e.message ?? e.code}';
  }
  if (e is OutOfMemoryError) return 'Tệp quá lớn cho bộ nhớ máy · File too large';
  final s = e.toString();
  return s.length > 160 ? '${s.substring(0, 160)}…' : s;
}

class UserMessage implements Exception {
  const UserMessage(this.message);
  final String message;
  @override
  String toString() => message;
}
