import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 已安装运行时的信息模型。
class RuntimeInfo {
  const RuntimeInfo({
    required this.id,
    required this.type,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.updateUrl,
    required this.minAppVersion,
  });

  final String id;
  final String type;
  final String name;
  final String version;
  final String description;
  final String author;

  /// 清单中声明的更新检查地址；为空表示未提供，无法在线检查更新。
  final String updateUrl;

  /// 清单中声明的最低 EdgeCube 构建号。
  final int minAppVersion;

  /// 是否支持在线检查更新（updateUrl 非空）。
  bool get canCheckUpdate => updateUrl.isNotEmpty;

  factory RuntimeInfo.fromMap(Map<String, dynamic> m) {
    return RuntimeInfo(
      id: m['id'] as String? ?? '',
      type: m['type'] as String? ?? '',
      name: m['name'] as String? ?? '',
      version: m['version'] as String? ?? '',
      description: m['description'] as String? ?? '',
      author: m['author'] as String? ?? '',
      updateUrl: m['updateUrl'] as String? ?? '',
      minAppVersion: m['minAppVersion'] as int? ?? 0,
    );
  }
}

/// 与原生 `runtime` 通道对接：已安装运行时的发现、导入与删除。
class RuntimeService {
  const RuntimeService();

  static const MethodChannel _method = MethodChannel(
    'com.venti1112.edgecube/runtime',
  );

  /// 运行时列表变更信号。导入或删除成功后递增，供监听方自动刷新。
  static final ValueNotifier<int> refreshSignal = ValueNotifier(0);

  /// 列出所有已安装的运行时。
  Future<List<RuntimeInfo>> installedRuntimes() async {
    final list = await _method.invokeMethod<List<dynamic>>('installedRuntimes');
    return list?.cast<Map<dynamic, dynamic>>().map((m) {
          return RuntimeInfo.fromMap(m.cast<String, dynamic>());
        }).toList() ??
        const [];
  }

  /// 导入 `.ecpkg` 文件并返回安装后的运行时信息。
  ///
  /// [force] 为 true 时不询问直接覆盖已存在的同 id 运行时。
  Future<RuntimeInfo> importPackage(String path, {bool force = false}) async {
    final map = await _method.invokeMethod<Map<dynamic, dynamic>>(
      'importPackage',
      {'path': path, 'force': force},
    );
    refreshSignal.value++;
    return RuntimeInfo.fromMap(map?.cast<String, dynamic>() ?? {});
  }

  /// 删除指定运行时。
  Future<void> deleteRuntime(String id) async {
    await _method.invokeMethod('deleteRuntime', {'id': id});
    refreshSignal.value++;
  }

  /// 列出所有已安装的 frpc 运行时。
  Future<List<RuntimeInfo>> installedFrpcRuntimes() async {
    final all = await installedRuntimes();
    return all.where((r) => r.type == 'frpc').toList();
  }

  /// 指定运行时的二进制是否正被服务端/隧道进程使用。
  Future<bool> isRuntimeRunning(String id) async {
    final running = await _method.invokeMethod<bool>('isRuntimeRunning', {
      'id': id,
    });
    return running ?? false;
  }

  /// 返回当前设备架构标识符（`arm64` / `arm` / `x86_64`）。
  /// 无法识别时返回空串。
  Future<String> getDeviceArch() async {
    final arch = await _method.invokeMethod<String>('deviceArch');
    return arch ?? '';
  }
}
