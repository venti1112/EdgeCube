import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'signature_verify_result.dart';

/// 已安装的 proot rootfs 信息。
///
/// rootfs 可携带内嵌清单 `edgecube-rootfs.json`（formatVersion=2），声明环境类型、
/// 主程序路径等元数据。EdgeCube 导入时直接读取该清单，不再扫描文件系统判断 Java 路径。
/// 缺失清单的 rootfs 视为 `generic` 纯容器（[isGeneric] = true），启动时必须由
/// 用户在实例配置中提供完整启动命令。
/// 支持的环境类型：java / php / node / python / box64 / generic。
class ProotRootfsInfo {
  const ProotRootfsInfo({
    required this.id,
    required this.dir,
    required this.envType,
    required this.envName,
    required this.envVersionName,
    required this.envMainBin,
    required this.envArgs,
    required this.serverFileHint,
    required this.description,
    required this.buildDate,
    required this.isGeneric,
  });

  /// rootfs 标识（同时是目录名，也是 server 启动时的 runtimeId）。
  final String id;

  /// rootfs 在 Android 文件系统中的绝对路径。
  /// 调用方需要展示大小时，应基于此路径在 isolate 中实时计算
  /// （rootfs 含数万文件，放 isolate 中计算不会卡 UI，且避免缓存失效）。
  final String dir;

  /// 环境类型：'java' / 'php' / 'node' / 'python' / 'box64' / 'generic'。
  /// 无清单时为 'generic'。
  final String envType;

  /// 展示名（如 "OpenJDK 21"）。无清单时为空串。
  final String envName;

  /// 运行时版本字符串（如 "21.0.5+11"）。无清单或未声明时为空串。
  final String envVersionName;

  /// 环境主程序的容器内绝对路径（如 "/usr/bin/java"）。
  /// generic 环境或无清单时为空串，表示不预定义主程序。
  final String envMainBin;

  /// 主程序固定前缀参数（如 java 的 ["-jar"]）。generic 时为空数组。
  final List<String> envArgs;

  /// 服务端文件扩展名提示（如 ".jar"、".phar"、".js"），用于 UI 筛选服务端文件。
  /// 无清单时为空串。
  final String serverFileHint;

  /// 人类可读的描述。无清单时为空串。
  final String description;

  /// 构建日期字符串（YYYYMMDD）。无清单时为空串。
  final String buildDate;

  /// 是否为纯容器（无元数据或 envType=generic）。
  /// true 时启动服务端必须由用户提供完整启动命令。
  final bool isGeneric;

  /// 兼容旧调用方：返回主程序路径（容器视角），无则 null。
  /// 新代码应直接使用 [envMainBin]。
  String? get javaBin => envMainBin.isEmpty ? null : envMainBin;

  /// 是否已安装 Java（envType=java 且 envMainBin 非空）。
  bool get hasJava => envType == 'java' && envMainBin.isNotEmpty;

  factory ProotRootfsInfo.fromMap(Map<String, dynamic> m) {
    return ProotRootfsInfo(
      id: m['id'] as String? ?? '',
      dir: m['dir'] as String? ?? '',
      envType: m['envType'] as String? ?? 'generic',
      envName: m['envName'] as String? ?? '',
      envVersionName: m['envVersionName'] as String? ?? '',
      envMainBin: m['envMainBin'] as String? ?? '',
      envArgs:
          (m['envArgs'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
      serverFileHint: m['serverFileHint'] as String? ?? '',
      description: m['description'] as String? ?? '',
      buildDate: m['buildDate'] as String? ?? '',
      isGeneric: m['isGeneric'] as bool? ?? true,
    );
  }
}

/// 与原生 `proot` 通道对接：proot rootfs 的导入、列表、删除。
///
/// 对应 [MainActivity] 中注册的 MethodChannel `com.venti1112.edgecube/proot`。
///
/// rootfs.tar.zst 与 `.ecpkg` 是不同的产物类型（rootfs 内嵌 edgecube-rootfs.json
/// 清单、含完整 Linux 根文件系统），故独立通道管理，不走 RuntimeService。
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
  Future<ProotRootfsInfo> importRootfs(String path, {String? id}) async {
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

  /// 更新所有已安装 proot rootfs 的 /etc/resolv.conf 为当前自定义 DNS 配置。
  /// 用户在「网络设置」页保存 DNS 后立即调用，无需重启实例即可生效。
  Future<void> updateProotDns() async {
    await _method.invokeMethod('updateProotDns');
  }

  /// 验证 rootfs 包的内嵌签名是否与当前 APK 签名一致。
  ///
  /// 新格式 `rootfs.zip`（ZIP 包装）验证内嵌签名；旧格式裸 tar 包无签名，
  /// 返回 `hasSignature=false`。调用方据 [SignatureVerifyResult.isTrusted]
  /// 判断是否允许导入。
  Future<SignatureVerifyResult> verifyRootfsSignature(String path) async {
    final map = await _method.invokeMethod<Map<dynamic, dynamic>>(
      'verifyRootfsSignature',
      {'path': path},
    );
    return SignatureVerifyResult.fromMap(map ?? {});
  }
}
