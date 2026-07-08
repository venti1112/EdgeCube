import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 已安装的 proot rootfs 信息。
class ProotRootfsInfo {
  const ProotRootfsInfo({
    required this.id,
    required this.dir,
    required this.sizeBytes,
    required this.javaBin,
  });

  /// rootfs 标识（同时是目录名，也是 server 启动时的 runtimeId）。
  final String id;

  /// rootfs 在 Android 文件系统中的绝对路径。
  final String dir;

  /// rootfs 目录总字节数（用于展示）。
  final int sizeBytes;

  /// rootfs 内 java 可执行文件路径（容器视角的绝对路径，如 /usr/bin/java）。
  /// 为 null 表示 rootfs 尚未安装 OpenJDK——可进 shell apt install 后再启动服务端。
  final String? javaBin;

  /// 是否已安装 Java（服务端启动的前置条件）。
  bool get hasJava => javaBin != null && javaBin!.isNotEmpty;

  factory ProotRootfsInfo.fromMap(Map<String, dynamic> m) {
    return ProotRootfsInfo(
      id: m['id'] as String? ?? '',
      dir: m['dir'] as String? ?? '',
      sizeBytes: m['sizeBytes'] as int? ?? 0,
      javaBin: m['javaBin'] as String?,
    );
  }
}

/// 与原生 `proot` 通道对接：proot rootfs 的导入、列表、删除。
///
/// 对应 [MainActivity] 中注册的 MethodChannel `com.venti1112.edgecube/proot`。
///
/// rootfs.tar.zst 与 `.ecpkg` 是不同的产物类型（无清单文件、无启动器配置、
/// 内含完整 Linux 根文件系统），故独立通道管理，不走 RuntimeService。
class ProotService {
  const ProotService();

  static const MethodChannel _method = MethodChannel(
    'com.venti1112.edgecube/proot',
  );

  /// 运行时列表变更信号。导入或删除成功后递增，供监听方自动刷新。
  static final ValueNotifier<int> refreshSignal = ValueNotifier(0);

  /// proot 二进制（lib__bin__proot-classic__.so）是否已随 APK 打包。
  ///
  /// UI 据此决定是否显示 proot 入口；未打包时引导用户下载 jniLibs。
  Future<bool> isAvailable() async {
    final ok = await _method.invokeMethod<bool>('isProotAvailable');
    return ok ?? false;
  }

  /// 列出所有已导入的 rootfs。
  Future<List<ProotRootfsInfo>> listRootfs() async {
    final list = await _method.invokeMethod<List<dynamic>>('listRootfs');
    return list?.cast<Map<dynamic, dynamic>>().map((m) {
          return ProotRootfsInfo.fromMap(m.cast<String, dynamic>());
        }).toList() ??
        const [];
  }

  /// 导入 rootfs.tar.zst（也接受 .tar.xz / .tar.gz）。
  ///
  /// [id] 为用户指定的 rootfs 标识；为空时从文件名推导。
  /// 解压耗时数十秒到数分钟，调用方应展示进度提示。
  Future<ProotRootfsInfo> importRootfs(
    String path, {
    String? id,
  }) async {
    final map = await _method.invokeMethod<Map<dynamic, dynamic>>(
      'importRootfs',
      {'path': path, 'id': id},
    );
    refreshSignal.value++;
    return ProotRootfsInfo.fromMap(map?.cast<String, dynamic>() ?? {});
  }

  /// 删除指定 rootfs。
  Future<void> deleteRootfs(String id) async {
    await _method.invokeMethod('deleteRootfs', {'id': id});
    refreshSignal.value++;
  }
}
