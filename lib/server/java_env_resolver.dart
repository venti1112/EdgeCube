import '../config/runtime_pref_store.dart';
import '../i18n/i18n_service.dart';
import 'proot_service.dart';

/// 解析出的 Java 环境类型。
enum JavaEnvKind {
  /// 原生运行时（导入的 .ecpkg JRE，经 liblaunch.so 启动）。
  native,

  /// proot 容器内的 Java（rootfs 里的原版 JDK）。
  proot,
}

/// 一次 Java 环境解析的结果。
class JavaEnv {
  const JavaEnv({
    required this.kind,
    required this.id,
    required this.displayName,
  });

  final JavaEnvKind kind;

  /// [JavaEnvKind.native] 时为原生 JRE 标识（如 `jre21`）；
  /// [JavaEnvKind.proot] 时为 rootfs 标识。
  final String id;

  /// 供 UI 展示的环境名（如 `原生 JRE 21` / `proot · OpenJDK 21`）。
  final String displayName;

  bool get isProot => kind == JavaEnvKind.proot;
}

/// 判断一个 rootfs 是否为可运行 Java 的容器（带元数据且 envType=java）。
bool isJavaRootfs(ProotRootfsInfo r) => !r.isGeneric && r.envType == 'java';

/// 按优先级 + 可用性解析实际使用的 Java 环境；两种都不可用时返回 null。
///
/// [priority] 决定先试哪种，先试的不可用时自动回退到另一种。
/// [nativeJreIds] 为当前可用的原生 JRE 标识列表（`ServerService.availableJreIds`）。
/// [rootfsList] 为已导入的全部 rootfs（`ProotService.listRootfs`），内部只会挑
/// [isJavaRootfs] 为真者。
/// [preferredNativeJreId] / [preferredRootfsId] 为调用方希望优先选中的具体标识
/// （如按 MC 版本推荐的 jreXX、实例已配置的 rootfs），无效或缺失时回退到列表首项。
JavaEnv? resolveJavaEnv({
  required RuntimePriority priority,
  required List<String> nativeJreIds,
  required List<ProotRootfsInfo> rootfsList,
  String? preferredNativeJreId,
  String? preferredRootfsId,
}) {
  final javaRootfs = rootfsList.where(isJavaRootfs).toList();

  // 实例已保存的具体选择优先于全局默认：用户曾在实例配置里显式选定某个原生 JRE
  // 或 proot rootfs，它就代表用户的意图，不应被全局优先级覆盖。只有实例未配置
  // （javaVersion 为空 / 都不匹配）时才用全局优先级。
  final effectivePriority = _resolveEffectivePriority(
    priority,
    nativeJreIds,
    javaRootfs,
    preferredNativeJreId: preferredNativeJreId,
    preferredRootfsId: preferredRootfsId,
  );

  JavaEnv? nativeEnv() {
    if (nativeJreIds.isEmpty) return null;
    final id = (preferredNativeJreId != null &&
            nativeJreIds.contains(preferredNativeJreId))
        ? preferredNativeJreId
        : nativeJreIds.first;
    return JavaEnv(
      kind: JavaEnvKind.native,
      id: id,
      displayName: tr('javaEnv.nativeJre', {'shortName': _jreShortName(id)}),
    );
  }

  JavaEnv? prootEnv() {
    if (javaRootfs.isEmpty) return null;
    final rootfs = javaRootfs.firstWhere(
      (r) => r.id == preferredRootfsId,
      orElse: () => javaRootfs.first,
    );
    final label = rootfs.envName.isNotEmpty ? rootfs.envName : rootfs.id;
    return JavaEnv(
      kind: JavaEnvKind.proot,
      id: rootfs.id,
      displayName: tr('javaEnv.prootLabel', {'label': label}),
    );
  }

  // 按优先级顺序尝试；先试的不可用则回退另一种。
  final order = effectivePriority == RuntimePriority.proot
      ? [prootEnv, nativeEnv]
      : [nativeEnv, prootEnv];
  for (final build in order) {
    final env = build();
    if (env != null) return env;
  }
  return null;
}

/// 综合「全局优先级」与「实例保存的具体选择」计算实际生效的优先级。
///
/// - 如果实例的 [preferredNativeJreId] 命中某个可用的原生 JRE → 返回 native，
///   即使用户全局设置为优先 proot 也遵循实例选择。
/// - 如果实例的 [preferredRootfsId] 命中某个可用的 proot Java rootfs → 返回 proot。
/// - 两者都不命中（新实例未配置、或已选的环境被删除了）→ 按全局 [priority] 执行。
RuntimePriority _resolveEffectivePriority(
  RuntimePriority priority,
  List<String> nativeJreIds,
  List<ProotRootfsInfo> javaRootfs, {
  String? preferredNativeJreId,
  String? preferredRootfsId,
}) {
  if (preferredNativeJreId != null &&
      nativeJreIds.contains(preferredNativeJreId)) {
    return RuntimePriority.native;
  }
  if (preferredRootfsId != null &&
      javaRootfs.any((r) => r.id == preferredRootfsId)) {
    return RuntimePriority.proot;
  }
  return priority;
}

/// 把原生 JRE 标识（`jre21`）转成简短展示名（`21`）；非 `jreN` 形式原样返回。
String _jreShortName(String id) {
  final m = RegExp(r'^jre(\d+)$').firstMatch(id);
  return m != null ? m.group(1)! : id;
}
