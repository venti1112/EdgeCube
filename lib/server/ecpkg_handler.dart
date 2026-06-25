import 'package:flutter/services.dart';

/// 处理从 Android 文件管理器打开 .ecpkg 文件的 Intent。
///
/// 当用户从外部打开 .ecpkg 文件时，Android 会通过 MethodChannel 发送文件路径。
/// UI 层应监听 [onOpenEcpkg] 回调并导航到导入流程。
class EcpkgHandler {
  EcpkgHandler._();

  static const _channel = MethodChannel('com.venti1112.edgecube/ecpkg');

  static void Function(String path)? _onOpenEcpkg;
  static String? _pendingPath;

  /// 当从外部打开 .ecpkg 文件时触发。
  /// UI 层应设置此回调以处理导入。
  /// 设置后会立即发送缓冲的路径（如有）。
  static void Function(String path)? get onOpenEcpkg => _onOpenEcpkg;
  static set onOpenEcpkg(void Function(String path)? callback) {
    _onOpenEcpkg = callback;
    if (callback != null && _pendingPath != null) {
      final path = _pendingPath!;
      _pendingPath = null;
      callback(path);
    }
  }

  /// 当打开 .ecpkg 文件出错时触发。
  /// UI 层应设置此回调以显示错误信息。
  static void Function(String error)? onError;

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openEcpkg') {
        final path = call.arguments as String?;
        if (path != null) {
          if (_onOpenEcpkg != null) {
            _onOpenEcpkg!(path);
          } else {
            _pendingPath = path;
          }
        }
      } else if (call.method == 'ecpkgError') {
        final error = call.arguments as String?;
        if (error != null) {
          onError?.call(error);
        }
      }
    });
  }
}
