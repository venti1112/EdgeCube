import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:edgecube_app/connection/client.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/connection/transport.dart';
import 'package:edgecube_app/console/pty_transport.dart';
import 'package:edgecube_app/files/models.dart';
import 'package:edgecube_app/files/providers.dart';
import 'package:edgecube_app/files/transfer.dart';
import 'package:edgecube_app/local_service/platform.dart';
import 'package:edgecube_app/local_service/settings.dart';
import 'package:edgecube_app/local_service/state.dart';
import 'package:edgecube_app/settings/appearance.dart';
import 'package:edgecube_app/storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假 zip 里的一个条目：顶层名字 + 它那一支的快照（见 [FakeFileTree._snapshot]）。
typedef FakeArchiveEntry = ({String name, Map<String, FakeNode> tree});

/// 假 zip 的全部条目。
typedef FakeArchive = List<FakeArchiveEntry>;

/// 一份玩家名单的返回形状（daemon 侧算好的两个视图：标签页 + 打标签）。
typedef FakePlayerList = ({
  List<Map<String, Object?>> entries,
  List<String> names,
});

/// 内存文件树的一个节点。
class FakeNode {
  FakeNode.dir() : isDir = true, bytes = null, linkTarget = null;

  FakeNode.file([List<int> content = const []])
    : isDir = false,
      bytes = Uint8List.fromList(content),
      linkTarget = null;

  FakeNode.link(this.linkTarget) : isDir = false, bytes = null;

  final bool isDir;

  /// 文件的字节；目录 / 链接为 null。
  Uint8List? bytes;

  /// 链接的目标（原样字符串）；不是链接时为 null。
  final String? linkTarget;

  bool get isLink => linkTarget != null;

  FakeNode copy() => switch (this) {
    FakeNode(isDir: true) => FakeNode.dir(),
    FakeNode(linkTarget: final target?) => FakeNode.link(target),
    _ => FakeNode.file(bytes ?? const []),
  };
}

/// 内存里的实例工作目录。
///
/// 形状与语义都照 daemon 的 `files.rs` 抄：目录在前 + 名称忽略大小写排序、
/// 复制重名自动 ` (n)`、移动重名报错、删除幂等、错误码与文案同表 ——
/// 假后端跟真后端一致，文件管理的 widget 测试才有意义。
///
/// 与真后端的已知差别（都不影响测试要验的行为）：
///
/// * 不跟随符号链接判定类型（真后端 `entry_of` 会跟随）；
/// * 压缩不写真 zip，只记下源列表（见 [compress] / [download]）。
class FakeFileTree {
  FakeFileTree() {
    nodes[''] = FakeNode.dir();
  }

  /// 相对路径 → 节点。`''` 是根目录；路径用 `/` 分隔，与协议一致。
  final Map<String, FakeNode> nodes = {};

  /// 由 [compress] 打出来的包：zip 路径 → 包里的条目快照。
  final Map<String, FakeArchive> archives = {};

  // ── 测试准备数据 ────────────────────────────────────────────────────────

  void addDir(String path) {
    var current = '';
    for (final part in path.split('/')) {
      current = joinPath(current, part);
      nodes.putIfAbsent(current, FakeNode.dir);
    }
  }

  void addFile(String path, String content) {
    addDir(splitPath(path).dir);
    nodes[path] = FakeNode.file(utf8.encode(content));
  }

  void addBytes(String path, List<int> content) {
    addDir(splitPath(path).dir);
    nodes[path] = FakeNode.file(content);
  }

  void addLink(String path, String target) {
    addDir(splitPath(path).dir);
    nodes[path] = FakeNode.link(target);
  }

  // ── 路径工具（daemon 的 `resolve` / `validate_name` / `ensure_dir`）─────

  static ({String dir, String name}) splitPath(String path) {
    final at = path.lastIndexOf('/');
    return at < 0
        ? (dir: '', name: path)
        : (dir: path.substring(0, at), name: path.substring(at + 1));
  }

  static String joinPath(String dir, String name) =>
      dir.isEmpty ? name : '$dir/$name';

  /// 归一化相对路径，挡掉绝对路径与 `..`。
  static String resolvePath(String rel) {
    final text = rel.trim();
    if (text.startsWith('/') || text.startsWith('\\')) {
      throw DaemonException('invalid_params', '路径必须是相对实例目录的：`$text`');
    }
    final parts = <String>[];
    for (final part in text.split(RegExp(r'[/\\]'))) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        throw DaemonException('invalid_params', '路径不能包含 `..`：`$text`');
      }
      parts.add(part);
    }
    return parts.join('/');
  }

  static String validateName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) throw const DaemonException('invalid_params', '名称不能为空');
    if (name == '.' || name == '..') {
      throw const DaemonException('invalid_params', '名称不合法');
    }
    if (name.contains('/') || name.contains('\\')) {
      throw const DaemonException('invalid_params', '名称里不能有路径分隔符');
    }
    return name;
  }

  static DaemonException notFound(String path) =>
      DaemonException('file_not_found', '没有 `$path` 这个条目');

  static DaemonException conflict(String name) =>
      DaemonException('file_exists', '目标位置已存在同名文件：$name');

  // ── 节点存取 ────────────────────────────────────────────────────────────

  FakeNode? node(String path) => nodes[path];

  FakeNode require(String path) {
    final found = nodes[path];
    if (found == null) throw notFound(path);
    return found;
  }

  bool exists(String path) => nodes.containsKey(path);

  List<String> childrenOf(String dir) => [
    for (final path in nodes.keys)
      if (path.isNotEmpty && splitPath(path).dir == dir) path,
  ];

  Map<String, dynamic> entryJson(String path) {
    final found = require(path);
    return {
      'name': splitPath(path).name,
      'path': path,
      'is_dir': found.isDir,
      'is_link': found.isLink,
      if (found.linkTarget != null) 'link_target': found.linkTarget,
      'size': found.bytes?.length ?? 0,
      'modified_ms': 1700000000000,
    };
  }

  /// 目录在前，然后按名称忽略大小写（同名再按原样比一次，保证稳定）。
  static void _sortEntries(List<Map<String, dynamic>> entries) {
    entries.sort((a, b) {
      final aDir = a['is_dir'] as bool;
      final bDir = b['is_dir'] as bool;
      if (aDir != bDir) return aDir ? -1 : 1;
      final byName = (a['name'] as String).toLowerCase().compareTo(
        (b['name'] as String).toLowerCase(),
      );
      if (byName != 0) return byName;
      return (a['name'] as String).compareTo(b['name'] as String);
    });
  }

  /// 不冲突的目标名，必要时追加 ` (n)`（` (n)` 插在扩展名之前）。
  String uniquePath(String dir, String name) {
    if (!exists(joinPath(dir, name))) return joinPath(dir, name);
    final at = name.lastIndexOf('.');
    final stem = at > 0 ? name.substring(0, at) : name;
    final ext = at > 0 ? name.substring(at) : '';
    for (var index = 1; index < 10000; index++) {
      final candidate = joinPath(dir, '$stem ($index)$ext');
      if (!exists(candidate)) return candidate;
    }
    throw DaemonException('file_exists', '`$name` 的可用名字试了一万次都撞车，放弃');
  }

  /// 已存在的目录（`ensure_dir`：不是目录 → `invalid_params`）。
  String _destDir(String rel) {
    final path = resolvePath(rel);
    if (!(nodes[path]?.isDir ?? false)) {
      throw DaemonException('invalid_params', '$path 不是目录');
    }
    return path;
  }

  /// 新建 / 上传的父目录：不存在 → `file_not_found`（同 `create_dir` 的报错）。
  String _parentDir(String rel) {
    final path = resolvePath(rel);
    final found = nodes[path];
    if (found == null) throw notFound(path);
    if (!found.isDir) {
      throw DaemonException('invalid_params', '$path 不是目录');
    }
    return path;
  }

  void _moveSubtree(String from, String to) {
    final moved = <String, FakeNode>{};
    for (final path in nodes.keys.toList()) {
      if (path == from || path.startsWith('$from/')) {
        moved['$to${path.substring(from.length)}'] = nodes.remove(path)!;
      }
    }
    nodes.addAll(moved);
  }

  void _copySubtree(String from, String to) {
    for (final path in nodes.keys.toList()) {
      if (path == from || path.startsWith('$from/')) {
        nodes['$to${path.substring(from.length)}'] = nodes[path]!.copy();
      }
    }
  }

  void _dropSubtree(String path) {
    nodes.removeWhere((key, _) => key == path || key.startsWith('$path/'));
    archives.removeWhere((key, _) => key == path || key.startsWith('$path/'));
  }

  /// 目录不能搬进它自己里面（`file_invalid_destination`）。
  void _guardNotIntoSelf(String source, String dest) {
    if (!(nodes[source]?.isDir ?? false)) return;
    if (dest == source || dest.startsWith('$source/')) {
      throw const DaemonException(
        'file_invalid_destination',
        '不能把文件夹移动或复制到它自身内部。',
      );
    }
  }

  // ── 读 ─────────────────────────────────────────────────────────────────

  /// `instance.files.list`：目录不存在 → 空列表，文件 → `invalid_params`。
  Map<String, dynamic> list(String rel) {
    final dir = resolvePath(rel);
    final found = nodes[dir];
    if (found != null && !found.isDir) {
      throw DaemonException('invalid_params', '$dir 不是目录');
    }
    final entries = [for (final child in childrenOf(dir)) entryJson(child)];
    _sortEntries(entries);
    return {'path': dir, 'entries': entries};
  }

  /// `instance.files.search`：名称忽略大小写的子串匹配。
  Map<String, dynamic> search(String rel, String query, bool recursive) {
    final dir = resolvePath(rel);
    final needle = query.trim().toLowerCase();
    final matches = <Map<String, dynamic>>[];
    if (needle.isNotEmpty) {
      final stack = [dir];
      while (stack.isNotEmpty) {
        final current = stack.removeLast();
        for (final child in childrenOf(current)) {
          if (splitPath(child).name.toLowerCase().contains(needle)) {
            matches.add(entryJson(child));
          }
          if (recursive && nodes[child]!.isDir) stack.add(child);
        }
      }
    }
    _sortEntries(matches);
    return {
      'path': dir,
      'query': query.trim(),
      'recursive': recursive,
      'truncated': false,
      'entries': matches,
    };
  }

  /// `instance.files.read`：不是 UTF-8 时抛 `file_not_utf8`（除非 `raw`）。
  Map<String, dynamic> read(String rel, bool raw) {
    final path = resolvePath(rel);
    final found = require(path);
    if (found.isDir) {
      throw DaemonException('invalid_params', '$path 不是普通文件');
    }
    final bytes = found.bytes ?? Uint8List(0);
    final (content, encoding) = switch (raw) {
      true => (latin1.decode(bytes), 'latin1'),
      false => _decodeUtf8(bytes),
    };
    return {
      'path': path,
      'name': splitPath(path).name,
      'content': content,
      'encoding': encoding,
      'size': bytes.length,
    };
  }

  static (String, String) _decodeUtf8(Uint8List bytes) {
    try {
      return (utf8.decode(bytes), 'utf-8');
    } on FormatException {
      throw const DaemonException(
        'file_not_utf8',
        '这个文件不是 UTF-8 文本，可以强制按 latin1 打开',
      );
    }
  }

  // ── 写 ─────────────────────────────────────────────────────────────────

  Map<String, dynamic> mkdir(String rel, String rawName) {
    final parent = _parentDir(rel);
    final name = validateName(rawName);
    if (exists(joinPath(parent, name))) throw conflict(name);
    final target = joinPath(parent, name);
    nodes[target] = FakeNode.dir();
    return {'entry': entryJson(target)};
  }

  Map<String, dynamic> create(String rel, String rawName) {
    final parent = _parentDir(rel);
    final name = validateName(rawName);
    if (exists(joinPath(parent, name))) throw conflict(name);
    final target = joinPath(parent, name);
    nodes[target] = FakeNode.file();
    return {'entry': entryJson(target)};
  }

  Map<String, dynamic> rename(String rel, String rawName) {
    final path = resolvePath(rel);
    if (path.isEmpty) {
      throw const DaemonException('invalid_params', '不能重命名实例根目录');
    }
    final name = validateName(rawName);
    final target = joinPath(splitPath(path).dir, name);
    if (target == path) return {'entry': entryJson(path)};
    if (exists(target)) throw conflict(name);
    require(path);
    _moveSubtree(path, target);
    return {'entry': entryJson(target)};
  }

  Map<String, dynamic> delete(String rel) {
    final path = resolvePath(rel);
    if (path.isEmpty) {
      throw const DaemonException('invalid_params', '不能删除实例根目录');
    }
    final found = nodes[path];
    if (found == null) return {'deleted': false, 'path': path};
    final isDir = found.isDir;
    _dropSubtree(path);
    return {'deleted': true, 'path': path, 'is_dir': isDir};
  }

  Map<String, dynamic> write(String rel, String content) {
    final path = resolvePath(rel);
    final found = require(path);
    if (found.isDir) {
      throw DaemonException('invalid_params', '$path 不是普通文件');
    }
    found.bytes = Uint8List.fromList(utf8.encode(content));
    return {'path': path, 'size': found.bytes!.length};
  }

  Map<String, dynamic> copy(String rel, String destRel) {
    final source = resolvePath(rel);
    if (source.isEmpty) {
      throw const DaemonException('invalid_params', '不能复制实例根目录');
    }
    final dest = _destDir(destRel);
    require(source);
    _guardNotIntoSelf(source, dest);
    final target = uniquePath(dest, splitPath(source).name);
    _copySubtree(source, target);
    return {'entry': entryJson(target)};
  }

  Map<String, dynamic> move(String rel, String destRel) {
    final source = resolvePath(rel);
    if (source.isEmpty) {
      throw const DaemonException('invalid_params', '不能移动实例根目录');
    }
    final dest = _destDir(destRel);
    require(source);
    _guardNotIntoSelf(source, dest);
    final name = splitPath(source).name;
    final target = joinPath(dest, name);
    if (target == source) return {'entry': entryJson(source)};
    if (exists(target)) throw conflict(name);
    _moveSubtree(source, target);
    return {'entry': entryJson(target)};
  }

  // ── 归档 ───────────────────────────────────────────────────────────────

  /// 假 zip 的内容：`zip:mods/a.jar+mods/b.jar`。
  ///
  /// 真后端写的是真 zip，但测试只需要能断言「下载回来的就是刚压进去的那一份」。
  static Uint8List zipBytes(String label) =>
      Uint8List.fromList(utf8.encode('zip:$label'));

  /// 压缩格式 → 归档后缀（与 daemon 的 `parse_compress_format` 一致）。
  static const _compressSuffixes = {
    'zip': '.zip',
    'tar.gz': '.tar.gz',
    'tar.xz': '.tar.xz',
    'tar.zst': '.tar.zst',
  };

  Map<String, dynamic> compress(
    List<String> rels,
    String destRel,
    String? rawName,
    String format,
  ) {
    if (rels.isEmpty) {
      throw const DaemonException('invalid_params', '没有要压缩的条目');
    }
    final dest = _destDir(destRel);
    final sources = [for (final rel in rels) resolvePath(rel)];
    for (final source in sources) {
      if (!exists(source)) throw notFound(source);
    }
    for (final source in sources) {
      _guardNotIntoSelf(source, dest);
    }

    final suffix = _compressSuffixes[format] ?? '.zip';
    final String name;
    if (rawName != null && rawName.trim().isNotEmpty) {
      // 用户手打的别的归档后缀会被换掉（`备份.zip` 选 tar.gz → `备份.tar.gz`）
      name = validateName('${_stripArchiveSuffix(rawName.trim())}$suffix');
    } else if (sources.length == 1) {
      name = validateName('${_archiveBaseFor(sources.single)}$suffix');
    } else {
      name = validateName('压缩文件$suffix');
    }

    final target = uniquePath(dest, name);
    nodes[target] = FakeNode.file(
      Uint8List.fromList(utf8.encode('$format:${sources.join('+')}')),
    );
    archives[target] = [
      for (final source in sources)
        (name: splitPath(source).name, tree: _snapshot(source)),
    ];
    return {'entry': entryJson(target)};
  }

  /// 去掉名字末尾任何认得的归档后缀。
  String _stripArchiveSuffix(String name) {
    final lower = name.toLowerCase();
    for (final suffix in archiveSuffixes) {
      if (lower.endsWith(suffix)) {
        return name.substring(0, name.length - suffix.length);
      }
    }
    return name;
  }

  /// 压缩名的取法：目录取全名，文件去掉扩展名（后缀由调用方补）。
  String _archiveBaseFor(String path) {
    final name = splitPath(path).name;
    if (nodes[path]?.isDir ?? false) return name;
    final at = name.lastIndexOf('.');
    return at > 0 ? name.substring(0, at) : name;
  }

  /// 压缩那一刻的子树快照：键是相对 [root] 的路径（根本身是 `''`）。
  ///
  /// 存快照而不是源路径 —— 真 zip 冻结字节，源目录删了改了都不影响解压。
  Map<String, FakeNode> _snapshot(String root) => {
    for (final path in nodes.keys.toList())
      if (path == root || path.startsWith('$root/'))
        (path == root ? '' : path.substring(root.length + 1)): nodes[path]!
            .copy(),
  };

  Map<String, dynamic> extract(String rel, String destRel, String? rawName) {
    final archive = resolvePath(rel);
    final dest = _destDir(destRel);
    final found = require(archive);
    if (found.isDir) {
      throw DaemonException('invalid_params', '$archive 不是文件');
    }
    final given = rawName?.trim();
    final name = validateName(
      (given == null || given.isEmpty)
          ? archiveBaseName(splitPath(archive).name)
          : given,
    );
    final target = uniquePath(dest, name);
    nodes[target] = FakeNode.dir();
    // 自己压的包能按快照把内容还原回来；手塞的 zip 只有个空目录（真后端会真解开）
    for (final entry in archives[archive] ?? const <FakeArchiveEntry>[]) {
      final base = joinPath(target, entry.name);
      for (final node in entry.tree.entries) {
        final path = node.key.isEmpty ? base : joinPath(base, node.key);
        nodes[path] = node.value.copy();
      }
    }
    return {'entry': entryJson(target)};
  }

  // ── 传输（HTTP 那两条路的假实现）──────────────────────────────────────

  /// 下载：文件回原字节，目录回现场打的假 zip。
  Uint8List download(String rel) {
    final path = resolvePath(rel);
    final found = require(path);
    if (!found.isDir) return found.bytes ?? Uint8List(0);
    return zipBytes(childrenOf(path).join('+'));
  }

  /// 上传落盘：`overwrite` 为 false 时重名自动 ` (n)`（同 daemon）。
  Map<String, dynamic> upload(
    String rel,
    String rawName,
    List<int> bytes, {
    bool overwrite = false,
  }) {
    final dir = _parentDir(rel);
    final name = validateName(rawName);
    final existing = joinPath(dir, name);
    final String target;
    if (overwrite) {
      if (nodes[existing]?.isDir ?? false) {
        throw DaemonException('file_exists', '$name 是个文件夹，不能覆盖');
      }
      target = existing;
    } else {
      target = uniquePath(dir, name);
    }
    nodes[target] = FakeNode.file(bytes);
    return {'entry': entryJson(target)};
  }
}

/// 直接用 [FakeInstanceStore] 的文件树当后端的传输实现（不碰网络）。
class FakeFileTransfer implements FileTransfer {
  FakeFileTransfer(this.store);

  final FakeInstanceStore store;

  /// 记录过的请求，用来断言 UI 发了什么。
  final List<({String instanceId, String path})> downloads = [];
  final List<({String instanceId, String dir, String name, int size})> uploads =
      [];

  FakeFileTree _tree(String instanceId) {
    if (!store.instances.containsKey(instanceId)) {
      throw DaemonException('instance_not_found', '没有 id 为 `$instanceId` 的实例');
    }
    return store.filesFor(instanceId);
  }

  @override
  Future<Uint8List> download(String instanceId, String path) async {
    downloads.add((instanceId: instanceId, path: path));
    return _tree(instanceId).download(path);
  }

  @override
  Future<FileEntry> upload(
    String instanceId, {
    required String dir,
    required String name,
    required Stream<List<int>> content,
    int? length,
    bool overwrite = false,
  }) async {
    final bytes = <int>[];
    await for (final chunk in content) {
      bytes.addAll(chunk);
    }
    uploads.add((
      instanceId: instanceId,
      dir: dir,
      name: name,
      size: bytes.length,
    ));
    final result = _tree(
      instanceId,
    ).upload(dir, name, bytes, overwrite: overwrite);
    return FileEntry.fromJson((result['entry'] as Map).cast<String, dynamic>());
  }
}

/// 内存里的运行环境后端：够 widget 测试跑「实例设置里选运行环境」。
///
/// 只实现「列出来」与「厂商表」—— 安装那套要真下载真解压，不是 widget 测试该碰的
/// （测试要几个环境就直接 [seedEnv] 摆几个）。形状照 daemon 的 `runtime.catalog` /
/// `runtime.list` 抄（`runtime/model.rs` 的 `Env`）。
class FakeRuntimeStore {
  /// 厂商表，与 daemon 的 `model::PROVIDERS` 同形同序。
  static const List<Map<String, Object?>> providers = [
    {
      'id': 'zulu',
      'name': 'Zulu',
      'homepage': 'https://www.azul.com/downloads/',
      'package_types': ['jdk'],
    },
    {
      'id': 'frp',
      'name': 'frp',
      'homepage': 'https://github.com/fatedier/frp',
      'package_types': ['frpc'],
    },
  ];

  /// 包类型表，与 `model::PACKAGE_TYPES` 同形。
  static const List<Map<String, Object?>> packageTypes = [
    {'id': 'jdk', 'name': 'JDK', 'description': '开发工具包，含 javac 等工具；跑服务端用它'},
    {'id': 'jre', 'name': 'JRE', 'description': '只含运行时，体积更小（本轮未开放下载）'},
    {
      'id': 'frpc',
      'name': 'frp 客户端',
      'description': '内网穿透客户端；同一个包里也带 frps（自建服务端用）',
    },
  ];

  /// id → 环境（线上形状）。测试要改状态就直接改这里的字段。
  final Map<String, Map<String, Object?>> environments = {};

  /// 每个方法被调用了几次。
  final Map<String, int> calls = {};

  String dataDir = '/tmp/edgecube-fake/runtimes';

  /// 摆一个环境（默认是「装好了的 Zulu JDK 21」）。
  ///
  /// id 不给就按 daemon 的规则拼：`<厂商>-<包类型>-<版本>-<平台>`。
  String seedEnv({
    String vendor = 'zulu',
    String packageType = 'jdk',
    String version = '21',
    String? versionName,
    String id = '',
    String state = 'installed',
    String os = 'linux',
    String arch = 'x64',
  }) {
    final envId = id.isNotEmpty
        ? id
        : '$vendor-$packageType-$version-$os-$arch';
    final jdk = packageType == 'jdk';
    environments[envId] = {
      'id': envId,
      'vendor': vendor,
      'package_type': packageType,
      'version': version,
      'version_name': versionName ?? version,
      'vendor_version': '',
      'os': os,
      'arch': arch,
      'archive_type': 'tar.gz',
      'package_uuid': '${1 + environments.length}',
      'file_name': '$envId.tar.gz',
      'url': 'https://example.com/$envId.tar.gz',
      'sha256': null,
      'md5': null,
      'size': 1024,
      'support_term': null,
      'build_date': null,
      'state': state,
      'stage': null,
      'error': null,
      'task_id': null,
      'home': jdk ? 'zulu-$version' : '',
      'binary': jdk ? 'bin/java' : 'frpc',
      'created_at_ms': 1700000000000,
      'installed_at_ms': state == 'installed' ? 1700000001000 : null,
      'updated_at_ms': 1700000001000,
    };
    return envId;
  }

  Map<String, dynamic> handle(String method, Map<String, dynamic> params) {
    calls[method] = (calls[method] ?? 0) + 1;
    switch (method) {
      case 'runtime.catalog':
        return {
          'providers': providers,
          'package_types': packageTypes,
          'default_provider': 'zulu',
          'default_package_type': 'jdk',
          'host': {
            'os': 'linux',
            'arch': 'x64',
            'archive_type': 'tar.gz',
            'libc': 'glibc',
          },
          'supported': true,
        };

      case 'runtime.list':
        return {
          'environments': [
            for (final env in environments.values)
              Map<String, Object?>.from(env),
          ],
          'count': environments.length,
          'dir': dataDir,
        };

      case 'runtime.delete':
        final id = params['id'] as String? ?? '';
        environments.remove(id);
        return {
          'deleted': true,
          'id': id,
          'meta_deleted': true,
          'files_deleted': true,
        };

      default:
        throw DaemonException('method_not_found', '假传输没有实现 $method');
    }
  }
}

/// 内存里的 UPnP 后端：够 widget 测试跑「网络映射页看总览 / 重新探测」。
///
/// 形状照 daemon 的 `upnp.status` 抄（`gateway` + `mappings` + `count` + `ts`）。
/// 真后端里映射行是「实例配置 + 进程状态」的投影，假后端**不重演那套推导** ——
/// 测试要什么行就用 [seedRow] 摆什么行（推导由 daemon 的单测钉着）。
///
/// 与真后端的已知差别（不影响测试要验的行为）：`upnp.probe` 不真的去发现，
/// 直接回当前摆好的快照（要验「探测后变好」就在点按钮前先改 [seedGateway]）。
class FakeUpnpStore {
  /// 网关状态（线上形状）。默认「还没探测过」。
  Map<String, Object?> gateway = {
    'state': 'unknown',
    'external_ip': null,
    'cgnat': false,
    'address': null,
    'error': null,
    'probed_at_ms': null,
  };

  /// 映射行（线上形状），顺序即返回顺序。
  final List<Map<String, Object?>> rows = [];

  /// 每个方法被调用了几次（验「点重新探测确实发了 upnp.probe」）。
  final Map<String, int> calls = {};

  /// 摆网关状态。默认是「发现成功」那份（改 `state: 'error'` 等可摆别的）。
  void seedGateway({
    String state = 'ready',
    String? externalIp = '203.0.113.7',
    bool cgnat = false,
    String? address = '192.168.1.1:1900',
    String? error,
    int? probedAtMs = 1700000000000,
  }) {
    gateway = {
      'state': state,
      'external_ip': externalIp,
      'cgnat': cgnat,
      'address': address,
      'error': error,
      'probed_at_ms': probedAtMs,
    };
  }

  /// 摆一行映射。`state` 是 `idle` / `mapping` / `mapped` / `failed`。
  Map<String, Object?> seedRow(
    String instanceId, {
    String instanceName = '测试服',
    bool enabled = true,
    bool running = false,
    String state = 'idle',
    String protocol = 'tcp',
    int? internalPort = 25565,
    int? externalPort,
    String? publicAddress,
    String? error,
  }) {
    final row = <String, Object?>{
      'instance_id': instanceId,
      'instance_name': instanceName,
      'enabled': enabled,
      'running': running,
      'state': state,
      'protocol': protocol,
      'internal_port': internalPort,
      'external_port': externalPort,
      'public_address': publicAddress,
      'error': error,
    };
    rows.add(row);
    return row;
  }

  /// `upnp.status` / `upnp.probe` 的返回体（返回时现算，改摆的数据立刻生效）。
  Map<String, dynamic> get snapshot => {
    'gateway': Map<String, Object?>.from(gateway),
    'mappings': [for (final row in rows) Map<String, Object?>.from(row)],
    'count': rows.length,
    'ts': 1700000000000,
  };

  Map<String, dynamic> handle(String method, Map<String, dynamic> params) {
    calls[method] = (calls[method] ?? 0) + 1;
    switch (method) {
      case 'upnp.status':
      case 'upnp.probe':
        return snapshot;

      default:
        throw DaemonException('method_not_found', '假传输没有实现 $method');
    }
  }
}

/// 内存里的 STUN 后端：够 widget 测试跑「网络映射页看隧道总览 / 改全局设置 / 清日志」。
///
/// 形状照 daemon 的 `stun.status` 抄（`settings` + `tunnels` + `count` + `ts`）。
/// 真后端里隧道行是「实例配置 + 进程状态」的投影，假后端**不重演那套推导** ——
/// 测试要什么行就用 [seedTunnel] 摆什么行（推导由 daemon 的单测钉着）。
///
/// 与真后端的已知差别（不影响测试要验的行为）：`stun.settings.set` 不重演
/// clamp（前端显示的永远是 daemon 回来的那份；夹取由 daemon 单测钉着）。
class FakeStunStore {
  /// 全局设置（线上形状）。默认与 daemon 的「没配过」一致：
  /// 内置 8 台服务器 + 20s 保活 + 128 并发 + 开连接日志。
  Map<String, Object?> settings = {
    'servers': [
      'fwa.lifesizecloud.com',
      'stun.freeswitch.org',
      'turn.cloudflare.com',
      'global.turn.twilio.com',
      'stun.nextcloud.com',
      'stun.telnyx.com',
      'stun.sonetel.com',
      'stun.voip.blackberry.com',
    ],
    'keep_alive_seconds': 20,
    'max_connections': 128,
    'keepalive_http': 'www.baidu.com:80',
    'show_connection_log': true,
  };

  /// 隧道行（线上形状），顺序即返回顺序。
  final List<Map<String, Object?>> rows = [];

  /// 日志行（线上形状，旧 → 新）。
  final List<Map<String, Object?>> lines = [];

  /// 每个方法被调用了几次（验「改设置确实发了 stun.settings.set」）。
  final Map<String, int> calls = {};

  /// `stun.settings.set` 收到的最后一次参数（断言前端发的 patch）。
  Map<String, dynamic>? lastSettingsPatch;

  /// 摆一行隧道。`state` 是 `idle` / `probing` / `running` / `failed`。
  Map<String, Object?> seedTunnel(
    String instanceId, {
    String instanceName = '测试服',
    bool enabled = true,
    bool running = false,
    String state = 'idle',
    String? publicAddress,
    int? localPort,
    int targetPort = 25565,
    int activeConnections = 0,
    int maxConnections = 128,
    int totalUp = 0,
    int totalDown = 0,
    int upSpeed = 0,
    int downSpeed = 0,
    String? error,
    String? server,
  }) {
    final row = <String, Object?>{
      'instance_id': instanceId,
      'instance_name': instanceName,
      'enabled': enabled,
      'running': running,
      'state': state,
      'public_address': publicAddress,
      'local_port': localPort,
      'target_port': targetPort,
      'active_connections': activeConnections,
      'max_connections': maxConnections,
      'total_up': totalUp,
      'total_down': totalDown,
      'up_speed': upSpeed,
      'down_speed': downSpeed,
      'error': error,
      'server': server,
    };
    rows.add(row);
    return row;
  }

  /// 摆一行日志（默认挂在「测试服」的隧道上）。
  void seedLog(
    String text, {
    String? instanceId = 'a1',
    String? instanceName = '测试服',
    int timeMs = 1700000000000,
  }) {
    lines.add({
      'time_ms': timeMs,
      'instance_id': instanceId,
      'instance_name': instanceName,
      'text': text,
    });
  }

  /// `stun.status` / `stun.settings.set` 的返回体（返回时现算，改摆的数据立刻生效）。
  Map<String, dynamic> get snapshot => {
    'settings': Map<String, Object?>.from(settings),
    'tunnels': [for (final row in rows) Map<String, Object?>.from(row)],
    'count': rows.length,
    'ts': 1700000000000,
  };

  Map<String, dynamic> handle(String method, Map<String, dynamic> params) {
    calls[method] = (calls[method] ?? 0) + 1;
    switch (method) {
      case 'stun.status':
        return snapshot;

      case 'stun.settings.set':
        lastSettingsPatch = Map<String, dynamic>.from(params);
        // patch 式：只覆盖传了的字段（真后端还会 clamp，这里不重演）
        for (final key in const [
          'servers',
          'keep_alive_seconds',
          'max_connections',
          'keepalive_http',
          'show_connection_log',
        ]) {
          if (params.containsKey(key)) settings[key] = params[key];
        }
        return snapshot;

      case 'stun.logs':
        return {
          'lines': [for (final line in lines) Map<String, Object?>.from(line)],
          'count': lines.length,
        };

      case 'stun.logs.clear':
        final cleared = lines.length;
        lines.clear();
        return {'cleared': cleared};

      default:
        throw DaemonException('method_not_found', '假传输没有实现 $method');
    }
  }
}

/// 内存里的实例后端：够 widget 测试跑完「列表 / 新建 / 选中 / 编辑 / 删除」。
///
/// 数据用 daemon 的**线上格式**（snake_case）存，和真后端的响应形状一致 ——
/// 这样假传输也能当作协议文档看。
class FakeInstanceStore {
  /// id → 元数据（线上形状）。
  final Map<String, Map<String, dynamic>> instances = {};

  /// 当前选中的 id。
  String? selected;

  /// 数据根目录（列表里回给前端显示）。
  String dataDir = '/tmp/edgecube-fake';

  /// 每个实例一棵内存文件树（第一次用到才建）。
  final Map<String, FakeFileTree> fileTrees = {};

  /// `instance.status` 回的阶段（测试按需改成 `running` 等）。
  String phase = 'stopped';

  /// 每个实例的服务端配置文件（**文件名 → 内容**）。
  ///
  /// `instance.config.get` 按 daemon 那套优先级认（`pnx.yml` >
  /// `server-settings.yml` > `server.properties`），所以测试直接摆文件就行 ——
  /// 不用自己算「这该是哪种 kind」。
  final Map<String, Map<String, String>> configFiles = {};

  /// `instance.config.save` 收到的最后一次内容（id → 记录）。
  final Map<String, ({String kind, String file, String content})> savedConfig =
      {};

  /// 每个实例的服务端图标字节（没有这个键 = 这个实例还没有图标）。
  final Map<String, Uint8List> icons = {};

  /// `instance.config.icon.save` 收到的图标（id → 字节），按最后一次算。
  final Map<String, Uint8List> savedIcon = {};

  /// 在线玩家（daemon 从控制台输出里解析出来的那份）。测试按需摆布，
  /// 变化照真后端推 `instance.players` 事件。
  final Map<String, List<String>> online = {};

  /// `instance.console.write` 收到的输入（命令 + 行尾），按实例记。
  final Map<String, List<String>> consoleInput = {};

  /// 每个实例的 `eula.txt` 状态：`id → (文件在不在, 有没有 eula=true)`。
  ///
  /// 首次进入时**什么都不摆** —— 新实例上服务端还没生成 `eula.txt`，
  /// 那正是「要弹 EULA 框」的情形（`instance.eula.get` 会回 false/false）。
  final Map<String, ({bool exists, bool agreed})> eula = {};

  /// `instance.eula.accept` 被调用了几次（验「点不同意就不写」）。
  int eulaAccepts = 0;

  /// 四份名单的返回值：`whitelist` / `ops` / `bans` / `ip_bans` → 两个视图。
  ///
  /// daemon 侧那套「JSON 优先、纯文本兜底」的读盘规则**不在这里重演** ——
  /// 它已经由 daemon 的单元测试与 `framework.rs` 的端到端用例钉住了。
  final Map<String, Map<String, FakePlayerList>> playerLists = {};

  /// 每个方法被调用了几次（验「某类事件不该引发重新拉取」时用）。
  final Map<String, int> calls = {};

  int _seq = 0;

  /// 取某个实例的文件树（测试准备数据、断言结果都从这里进）。
  FakeFileTree filesFor(String id) =>
      fileTrees.putIfAbsent(id, FakeFileTree.new);

  /// 摆一份名单。`names` 不给就从 `entries` 的 `name` 字段推（小写）——
  /// 真后端也是这么取打标签用的那份名字的。
  void seedList(
    String id,
    String list, {
    List<Map<String, Object?>> entries = const [],
    List<String>? names,
  }) {
    playerLists.putIfAbsent(id, () => {})[list] = (
      entries: entries,
      names:
          names ??
          [
            for (final entry in entries)
              if (entry['name'] case final String name) name.toLowerCase(),
          ],
    );
  }

  /// 直接塞一个实例（测试准备数据用）。
  ///
  /// 默认带一条启动命令，这样种子实例的 lint 是干净的（没配启动命令会出告警）。
  /// 要表单模式的实例就把 [runtimeEnvId] / [serverFile] 之类填上、并把
  /// [startupCommand] 传 `null`（daemon 那边「四个表单字段有一个就算表单模式」）。
  String seed({
    required String name,
    String? startupCommand = 'java -jar server.jar nogui',
    bool? manualCommand,
    String? runtimeEnvId,
    String? serverFile,
    int? maxMemory,
    String? customJvmArgs,
    bool compatMode = false,
    bool autoRestart = false,
    String? frpTunnelId,
    bool upnpEnabled = false,
    String upnpProtocol = 'tcp',
    int? upnpExternalPort,
    bool stunEnabled = false,
    bool stunProxyProtocol = false,
    int? stunTargetPort,
  }) {
    final id = _nextId();
    instances[id] = {
      'id': id,
      'name': name,
      'startup_command': ?startupCommand,
      'manual_command': ?manualCommand,
      'runtime_env_id': ?runtimeEnvId,
      'server_file': ?serverFile,
      'max_memory': ?maxMemory,
      'custom_jvm_args': ?customJvmArgs,
      'compat_mode': compatMode,
      'auto_restart_on_exit': autoRestart,
      'frp_tunnel_id': ?frpTunnelId,
      // 真后端 wire 总会带上这三个（没配就是 false / tcp / null）
      'upnp_enabled': upnpEnabled,
      'upnp_protocol': upnpProtocol,
      'upnp_external_port': upnpExternalPort,
      // STUN 三字段同理（false / false / null）
      'stun_enabled': stunEnabled,
      'stun_proxy_protocol': stunProxyProtocol,
      'stun_target_port': stunTargetPort,
      'path': null,
      'line_ending': '\n',
      'created_at_ms': 1700000000000 + _seq,
      'updated_at_ms': 1700000000000 + _seq,
    };
    selected ??= id;
    return id;
  }

  /// 线上形状：多一个 `launch_command`（照 daemon 的 `to_wire_value` 现算）。
  ///
  /// 与真后端的差别：java 那一截这里固定写 `java`，真后端是运行环境目录里的
  /// 绝对路径 —— 前端只显示，不解析，这条差别不影响任何断言。
  static Map<String, dynamic> wire(Map<String, dynamic> config) => {
    ...config,
    'launch_command': launchCommandFor(config),
  };

  /// 这个实例真正会跑的命令；起不来时 `null`（同 daemon 的 `Resolved::wire`）。
  ///
  /// 拼法照 daemon 的 `compose_java_command`：
  /// `<java> [-Xmx<n>M] [JVM 参数…] -jar <jar> nogui`。
  static String? launchCommandFor(Map<String, dynamic> config) {
    if (isManual(config)) {
      final text = (config['startup_command'] as String?)?.trim() ?? '';
      return text.isEmpty ? null : text;
    }
    final envId = (config['runtime_env_id'] as String?)?.trim() ?? '';
    final jar = (config['server_file'] as String?)?.trim() ?? '';
    if (envId.isEmpty || jar.isEmpty) return null;
    final parts = <String>['java'];
    final memory = config['max_memory'];
    if (memory is int && memory > 0) parts.add('-Xmx${memory}M');
    final custom = (config['custom_jvm_args'] as String?)?.trim() ?? '';
    if (custom.isNotEmpty) parts.addAll(custom.split(RegExp(r'\s+')));
    return [...parts, '-jar', jar, 'nogui'].join(' ');
  }

  /// 手动模式的判定，同 daemon 的 `InstanceConfig::manual_command`：
  /// 存过就按存的，没存过才推断（写了命令且四个表单字段全空 = 手动）。
  static bool isManual(Map<String, dynamic> config) {
    final stored = config['manual_command'];
    if (stored is bool) return stored;
    final hasFormField = [
      config['runtime_env_id'],
      config['server_file'],
      config['max_memory'],
      config['custom_jvm_args'],
    ].any((value) => value != null);
    final startup = (config['startup_command'] as String?)?.trim() ?? '';
    return startup.isNotEmpty && !hasFormField;
  }

  String _nextId() => (++_seq).toRadixString(16).padLeft(16, '0');

  /// 处理一个 `instance.*` 调用；出错时抛 [DaemonException]（假传输会转成
  /// error 信封，与真后端一致）。
  Map<String, dynamic> handle(String method, Map<String, dynamic> params) {
    calls[method] = (calls[method] ?? 0) + 1;
    if (method.startsWith('instance.files.')) {
      return _handleFiles(method, params);
    }
    if (method.startsWith('instance.players.') ||
        method == 'instance.console.write') {
      return _handlePlayers(method, params);
    }
    if (method.startsWith('instance.config.')) {
      return _handleConfig(method, params);
    }
    switch (method) {
      case 'instance.list':
        return {
          'instances': [
            for (final entry in instances.entries)
              {
                'id': entry.key,
                'name': entry.value['name'],
                'path': entry.value['path'],
                'selected': entry.key == selected,
              },
          ],
          'count': instances.length,
          'selected': selected,
          'data_dir': dataDir,
        };

      case 'instance.get':
        final config = _require(params);
        return {
          'instance': wire(config),
          'dir': _dir(config),
          'lint': <String>[],
        };

      case 'instance.status':
        final config = _require(params);
        return {
          'status': {
            'id': config['id'],
            'name': config['name'],
            'phase': phase,
            'running': phase == 'running',
            'process_managed': false,
            'dir': _dir(config),
            'dir_exists': true,
            'size_bytes': 1536,
            'size_human': '1.5 KiB',
            'file_count': 2,
            'dir_count': 1,
            'size_truncated': false,
            'created_at_ms': config['created_at_ms'],
            'updated_at_ms': config['updated_at_ms'],
            'warnings': const <String>[],
          },
        };

      case 'instance.create':
        final name = (params['name'] as String? ?? '').trim();
        if (name.isEmpty) {
          throw const DaemonException('invalid_params', '实例名称不能为空');
        }
        if (instances.values.any((c) => (c['name'] as String).trim() == name)) {
          throw DaemonException('instance_name_taken', '已存在名为 `$name` 的实例');
        }
        final id = _nextId();
        instances[id] = {
          'id': id,
          'name': name,
          // 启动配置那几项「传了才存」（真后端缺席 = 不设，且空串等同不设）
          for (final key in const [
            'startup_command',
            'manual_command',
            'runtime_env_id',
            'server_file',
            'max_memory',
            'custom_jvm_args',
            'path',
          ])
            if (_present(params[key])) key: params[key],
          'compat_mode': false,
          'auto_restart_on_exit': false,
          // UPnP 三字段：真后端 wire 总会带上（没配就是 false / tcp / null）
          'upnp_enabled': params['upnp_enabled'] as bool? ?? false,
          'upnp_protocol': (params['upnp_protocol'] as String? ?? 'tcp')
              .trim()
              .toLowerCase(),
          'upnp_external_port': (params['upnp_external_port'] as num?)?.toInt(),
          // STUN 三字段同理（false / false / null）
          'stun_enabled': params['stun_enabled'] as bool? ?? false,
          'stun_proxy_protocol':
              params['stun_proxy_protocol'] as bool? ?? false,
          'stun_target_port': (params['stun_target_port'] as num?)?.toInt(),
          'line_ending': '\n',
          'created_at_ms': 1700000000000 + _seq,
          'updated_at_ms': 1700000000000 + _seq,
        };
        selected = id;
        return {
          'instance': wire(instances[id]!),
          'dir': _dir(instances[id]!),
          'selected': id,
          'count': instances.length,
        };

      case 'instance.update':
        final config = _require(params);
        final patch = Map<String, dynamic>.from(params)..remove('id');
        final name = patch['name'] as String?;
        if (name != null) {
          if (name.trim().isEmpty) {
            throw const DaemonException('invalid_params', '实例名称不能为空');
          }
          final taken = instances.entries.any(
            (e) => e.key != config['id'] && e.value['name'] == name,
          );
          if (taken) {
            throw DaemonException('instance_name_taken', '已存在名为 `$name` 的实例');
          }
        }
        var changed = false;
        for (final entry in patch.entries) {
          var value = entry.value;
          // daemon 的两条归一化：这几项的空串 = 清空，最大内存 0 = 不限
          if (_textKeys.contains(entry.key) &&
              value is String &&
              value.trim().isEmpty) {
            value = null;
          }
          if (entry.key == 'max_memory' && value == 0) value = null;
          if (config[entry.key] != value) changed = true;
          config[entry.key] = value;
        }
        if (changed) {
          config['updated_at_ms'] = 1700000009999;
        }
        return {
          'instance': wire(config),
          'changed': changed,
          'dir': _dir(config),
          'lint': <String>[],
        };

      case 'instance.delete':
        final config = _require(params);
        instances.remove(config['id']);
        if (selected == config['id']) {
          selected = instances.keys.firstOrNull;
        }
        return {
          'deleted': true,
          'id': config['id'],
          'name': config['name'],
          'dir': _dir(config),
          'files_deleted': true,
          'metadata_deleted': true,
          'selected': selected,
          'remaining': instances.length,
        };

      case 'instance.select':
        final id = params['id'] as String?;
        if (id != null && !instances.containsKey(id)) {
          throw DaemonException('instance_not_found', '没有 id 为 `$id` 的实例');
        }
        selected = id;
        return {'selected': selected, 'count': instances.length};

      case 'instance.scan':
        return {
          'skipped': false,
          'pruned': const <String>[],
          'adopted': const <String>[],
          'ignored': const <String>[],
          'total': instances.length,
          'selected': selected,
        };

      case 'instance.eula.get':
        final id = _require(params)['id'] as String? ?? '';
        final status = eula[id] ?? (exists: false, agreed: false);
        return {
          'id': id,
          'file': 'eula.txt',
          'exists': status.exists,
          'agreed': status.agreed,
        };

      case 'instance.eula.accept':
        final id = _require(params)['id'] as String? ?? '';
        eulaAccepts++;
        eula[id] = (exists: true, agreed: true);
        return {'id': id, 'file': 'eula.txt', 'exists': true, 'agreed': true};

      default:
        throw DaemonException('method_not_found', '假传输没有实现 $method');
    }
  }

  /// 处理 `instance.config.get` / `instance.config.save`。
  ///
  /// 检测优先级与 daemon 的 `instance::config` 一致（`pnx.yml` >
  /// `server-settings.yml` > `server.properties`；properties 再按布尔值写法分
  /// java / pmmp）。**故意重演一遍**：这样测试只要摆文件，不用自己去算 kind ——
  /// 而「怎么算」本来就有 daemon 那边的单测钉着。
  Map<String, dynamic> _handleConfig(
    String method,
    Map<String, dynamic> params,
  ) {
    final config = _require(params);
    final id = config['id'] as String;
    final files = configFiles.putIfAbsent(id, () => {});

    switch (method) {
      case 'instance.config.get':
        final kind = _detectConfigKind(files);
        final file = kind == null ? 'server.properties' : _fileNameOf(kind);
        return {
          'kind': kind,
          'file': file,
          'exists': kind != null,
          'content': kind == null ? '' : (files[file] ?? ''),
        };

      case 'instance.config.save':
        final kind = params['kind'] as String? ?? '';
        final file = _fileNameOf(kind);
        if (file == null) {
          throw DaemonException('invalid_params', '不认识的配置类型 `$kind`');
        }
        final content = params['content'] as String? ?? '';
        if (!files.containsKey(file)) {
          throw DaemonException(
            'instance_config_missing',
            '$file 不存在 —— 先启动一次服务端让它生成',
          );
        }
        files[file] = content;
        savedConfig[id] = (kind: kind, file: file, content: content);
        return {'kind': kind, 'file': file};

      case 'instance.config.icon.get':
        final icon = icons[id];
        return {
          'file': 'server-icon.png',
          'exists': icon != null,
          'data': icon == null ? null : base64Encode(icon),
        };

      case 'instance.config.icon.save':
        final data = params['data'] as String? ?? '';
        final Uint8List bytes;
        try {
          bytes = base64Decode(data);
        } on FormatException {
          throw const DaemonException('invalid_params', '图标数据不是合法的 base64');
        }
        // 与真 daemon 一样校验 64×64 PNG（见 `daemon/.../instance/config.rs`）。
        // 故意重演：这样「前端裁剪算错尺寸」在 widget 测试里就能炸出来。
        if (!_isIconPng(bytes)) {
          throw const DaemonException(
            'instance_icon_invalid',
            '图标必须是 64×64 的 PNG',
          );
        }
        icons[id] = bytes;
        savedIcon[id] = bytes;
        return {'file': 'server-icon.png', 'size': bytes.length};

      default:
        throw DaemonException('method_not_found', '假传输没有实现 $method');
    }
  }

  /// 64×64 PNG 的头部检查（照 daemon 的 `check_icon`）。
  static bool _isIconPng(Uint8List bytes) {
    if (bytes.length < 24) return false;
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') return false;
    int be32(int at) =>
        (bytes[at] << 24) |
        (bytes[at + 1] << 16) |
        (bytes[at + 2] << 8) |
        bytes[at + 3];
    return be32(16) == 64 && be32(20) == 64;
  }

  /// daemon 那套检测（见 `daemon/.../instance/config.rs` 的 `detect_kind`）。
  String? _detectConfigKind(Map<String, String> files) {
    if (files.containsKey('pnx.yml')) return 'pnx';
    if (files.containsKey('server-settings.yml')) return 'allay';
    if (files.containsKey('server.properties')) {
      if (files.containsKey('pocketmine.yml')) return 'pmmp';
      final content = files['server.properties'] ?? '';
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split('=');
        if (parts.length < 2) continue;
        if (!const [
          'pvp',
          'enable-query',
          'white-list',
        ].contains(parts[0].trim())) {
          continue;
        }
        final value = parts[1].trim().toLowerCase();
        if (value == 'on' || value == 'off') return 'pmmp';
        if (value == 'true' || value == 'false') return 'java';
      }
      return 'java';
    }
    return null;
  }

  String? _fileNameOf(String kind) => switch (kind) {
    'pnx' => 'pnx.yml',
    'allay' => 'server-settings.yml',
    'java' || 'pmmp' => 'server.properties',
    _ => null,
  };

  /// 处理一个 `instance.files.*` 调用（参数名与真后端一致）。
  Map<String, dynamic> _handleFiles(
    String method,
    Map<String, dynamic> params,
  ) {
    final config = _require(params);
    final tree = filesFor(config['id'] as String);
    String text(String key) => params[key] as String? ?? '';

    return switch (method) {
      'instance.files.list' => tree.list(text('path')),
      'instance.files.search' => tree.search(
        text('path'),
        text('query'),
        params['recursive'] as bool? ?? false,
      ),
      'instance.files.mkdir' => tree.mkdir(text('path'), text('name')),
      'instance.files.create' => tree.create(text('path'), text('name')),
      'instance.files.rename' => tree.rename(text('path'), text('name')),
      'instance.files.delete' => tree.delete(text('path')),
      'instance.files.copy' => tree.copy(text('path'), text('dest')),
      'instance.files.move' => tree.move(text('path'), text('dest')),
      'instance.files.read' => tree.read(
        text('path'),
        params['raw'] as bool? ?? false,
      ),
      'instance.files.write' => tree.write(text('path'), text('content')),
      'instance.files.compress' => tree.compress(
        [for (final path in params['paths'] as List? ?? const []) '$path'],
        text('dest'),
        params['name'] as String?,
        text('format').isEmpty ? 'zip' : text('format'),
      ),
      'instance.files.extract' => tree.extract(
        text('path'),
        text('dest'),
        params['name'] as String?,
      ),
      _ => throw DaemonException('method_not_found', '假传输没有实现 $method'),
    };
  }

  /// 处理 `instance.players.*` 与 `instance.console.write`（形状同真后端）。
  Map<String, dynamic> _handlePlayers(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = _require(params)['id'] as String;

    if (method == 'instance.players.online') {
      final players = online[id] ?? const <String>[];
      return {'id': id, 'players': players, 'count': players.length};
    }
    if (method == 'instance.console.write') {
      // 真后端是「没有会话就报没在运行」，这里用阶段近似
      if (phase != 'running') {
        throw const DaemonException('instance_not_running', '实例没在运行');
      }
      final data = params['data'] as String? ?? '';
      consoleInput.putIfAbsent(id, () => []).add(data);
      return {'written': data.length};
    }

    final list = playerLists[id]?[method.substring('instance.players.'.length)];
    // 没摆过 = 这份名单在磁盘上不存在，两个视图都是空（同真后端）
    return {
      'id': id,
      'entries': list?.entries ?? const <Map<String, Object?>>[],
      'names': list?.names ?? const <String>[],
    };
  }

  /// 可选文本字段：空串等同没填（daemon 的 `normalize_optional_text`）。
  static const Set<String> _textKeys = {
    'startup_command',
    'stop_command',
    'runtime_env_id',
    'server_file',
    'custom_jvm_args',
    'frp_runtime_id',
    'frp_tunnel_id',
  };

  static bool _present(Object? value) =>
      value != null && (value is! String || value.trim().isNotEmpty);

  Map<String, dynamic> _require(Map<String, dynamic> params) {
    final id = params['id'] as String?;
    final config = id == null ? null : instances[id];
    if (config == null) {
      throw DaemonException('instance_not_found', '没有 id 为 `$id` 的实例');
    }
    return config;
  }

  String _dir(Map<String, dynamic> config) =>
      '${config['path'] ?? '$dataDir/instances/${config['id']}'}';
}

/// 内存里的 FRP 后端：够 widget 测试跑完「选平台 / 登录 / 建隧道 / 存隧道 / 看配置」。
///
/// 形状与语义都照 daemon 的 `frp` 模块抄：平台清单与登录方式
/// （`providers_json`）、令牌非空**且**账号名非空才跳得过登录页
/// （`cached_account_json`）、两句校验文案（`validate_custom` /
/// `require_create_fields`）、自定义隧道保存时顺带生成 TOML
/// （`save_tunnel` + `generate_config`）—— 假后端跟真后端一致，
/// 这些用例才有意义。
///
/// 与真后端的已知差别（都不影响测试要验的行为）：平台侧 API 不联网
/// （复核令牌、平台隧道都读内存）；非自定义平台的配置文本按
/// `builder.rs::standard_toml` 的形状现拼，不是平台下发的原文。
class FakeFrpStore {
  /// 平台清单，与 daemon 的 `providers_json()` 逐字同形。
  static const List<Map<String, Object?>> providers = [
    {
      'key': 'mslfrp',
      'name': 'MSL Frp',
      'requires_login': true,
      'browser_login': true,
      'token_login': false,
    },
    {
      'key': 'openfrp',
      'name': 'OpenFrp',
      'requires_login': true,
      'browser_login': true,
      'token_login': false,
    },
    {
      'key': 'sakurafrp',
      'name': 'Sakura Frp',
      'requires_login': true,
      'browser_login': false,
      'token_login': true,
    },
    {
      'key': 'chmlfrp',
      'name': 'ChmlFrp',
      'requires_login': true,
      'browser_login': true,
      'token_login': false,
    },
    {
      'key': 'mefrp',
      'name': 'ME Frp',
      'requires_login': true,
      'browser_login': false,
      'token_login': true,
    },
    {
      'key': 'custom',
      'name': '',
      'requires_login': false,
      'browser_login': false,
      'token_login': false,
    },
  ];

  /// provider key → 令牌（daemon 的 `config/frp/auth.json`）。
  final Map<String, String> tokens = {};

  /// provider key → 账号缓存。
  final Map<String, Map<String, Object?>> accounts = {};

  /// 平台侧隧道 / 节点（`frp.remote.*` 直接回这两份）。
  final Map<String, List<Map<String, Object?>>> remoteTunnels = {};
  final Map<String, List<Map<String, Object?>>> nodes = {};

  /// 浏览器授权会话（`frp.login.*`）：provider → 会话快照。
  final Map<String, Map<String, Object?>> sessions = {};

  /// 本地已保存的隧道：localId → 线上形状（snake_case）。
  final Map<String, Map<String, Object?>> savedTunnels = {};

  /// 自定义隧道的配置原文（保存时那份，重新生成时用它）。
  final Map<String, String> customToml = {};

  /// 已写到盘上的配置：localId → TOML。
  final Map<String, String> tomls = {};

  /// 平台侧调用一律回 `frp_unauthorized`（验「登录已失效」那条路）。
  bool unauthorized = false;

  /// `frp.account` 带 `verify` 时回未登录并清令牌（验自动登录失败）。
  bool verifyFails = false;

  /// 令牌登录 / 账号条用的账号（测试要改就改这几个）。
  String username = 'steve';
  String group = '普通用户';
  int usedTunnels = 1;
  int maxTunnels = 3;

  /// 每个方法被调用了几次。
  final Map<String, int> calls = {};

  /// `frp.remote.create` / `frp.tunnels.save` 收到的参数（断言前端发了什么）。
  final List<Map<String, dynamic>> created = [];
  final List<Map<String, dynamic>> savedInputs = [];

  // ── FRP 实例的运行（一条隧道配置 = 一个可独立运行的实例）──

  /// 能拿来跑隧道的 frpc 运行环境（`frp.runtimes`）。空 = 一个都没装。
  final List<({String id, String name})> frpcRuntimes = [];

  /// `frp.settings.save` 记下的那个（`null` = 还没选过）。
  String? savedFrpcRuntimeId;

  /// 运行态：localId → 快照（**不含日志** —— 列表接口本来就不带）。
  final Map<String, Map<String, Object?>> runs = {};

  /// localId → 日志行（只有 `frp.run.get` 会带出去）。
  final Map<String, List<String>> runLogs = {};

  /// `frp.run.start` 一律失败（验错误提示那条路）。
  bool runStartFails = false;

  /// 摆一条运行态。`state` 是 `running` / `exited` / `failed`。
  void seedRun(
    String localId, {
    String state = 'running',
    String tunnelName = '',
    int? exitCode,
    String? message,
    int? pid,
  }) {
    runs[localId] = {
      'local_id': localId,
      'tunnel_name': tunnelName,
      'state': state,
      'runtime_id': frpcRuntimes.isEmpty ? '' : frpcRuntimes.first.id,
      'config_path': '/data/config/frp/toml/$localId.toml',
      'pid': pid ?? (state == 'running' ? 4242 : null),
      'started_at_ms': 1700000000000,
      'exit_code': exitCode,
      'message': message,
    };
  }

  int _seq = 0;

  String get dataDir => '/tmp/edgecube-fake/config/frp';

  // ── 测试准备数据 ────────────────────────────────────────────────────────

  /// 摆一份登录态：令牌 + 账号缓存（两个都有才跳得过登录页）。
  void login(
    String provider, {
    String? username,
    String? group,
    int? usedTunnels,
    int? maxTunnels,
  }) {
    tokens[provider] = 'token-$provider';
    accounts[provider] = {
      'username': username ?? this.username,
      'group': group ?? this.group,
      'used_tunnels': usedTunnels ?? this.usedTunnels,
      'max_tunnels': maxTunnels ?? this.maxTunnels,
    };
  }

  /// 摆一份浏览器授权会话（默认 `waiting`：daemon 正在轮询）。
  void seedSession(
    String provider, {
    String state = 'waiting',
    String url = 'https://example.com/authorize',
    String userCode = '',
    String message = '',
  }) {
    sessions[provider] = _session(
      provider,
      state: state,
      url: url,
      userCode: userCode,
      message: message,
    );
  }

  /// 摆一个平台侧节点。
  Map<String, Object?> seedNode(
    String provider, {
    required String name,
    String? id,
    String hostname = '',
    int serverPort = 7000,
    int? minPort,
    int? maxPort,
    String description = '',
    bool online = true,
    bool vip = false,
  }) {
    final node = <String, Object?>{
      'id': id ?? '${++_seq}',
      'name': name,
      'hostname': hostname,
      'server_port': serverPort,
      'min_port': minPort,
      'max_port': maxPort,
      'description': description,
      'online': online,
      'vip': vip,
      'udp_support': false,
    };
    nodes.putIfAbsent(provider, () => []).add(node);
    return node;
  }

  /// 摆一条平台侧隧道。
  Map<String, Object?> seedRemoteTunnel(
    String provider, {
    required String name,
    String? id,
    String nodeId = '1',
    String nodeName = 'cn-1',
    String type = 'tcp',
    String localIp = '127.0.0.1',
    int localPort = 25565,
    int? remotePort = 25566,
    String remoteAddress = '',
    bool online = true,
  }) {
    final tunnel = <String, Object?>{
      'id': id ?? '${++_seq}',
      'name': name,
      'node_id': nodeId,
      'node_name': nodeName,
      'type': type,
      'local_ip': localIp,
      'local_port': localPort,
      'remote_port': remotePort,
      'remote_address': remoteAddress,
      'online': online,
    };
    remoteTunnels.putIfAbsent(provider, () => []).add(tunnel);
    return tunnel;
  }

  /// 摆一条本地已保存的隧道（返回 localId）；`toml` 给了就当配置已在盘上。
  String seedSavedTunnel({
    required String provider,
    required String name,
    String? toml,
    String remoteTunnelId = '',
    String nodeId = '',
    String nodeName = '',
    String type = 'tcp',
    String localIp = '127.0.0.1',
    int localPort = 25565,
    int? remotePort,
    String remoteAddress = '',
  }) {
    final localId = _nextId();
    savedTunnels[localId] = {
      'local_id': localId,
      'provider': provider,
      'name': name,
      'remote_tunnel_id': remoteTunnelId,
      'node_id': nodeId,
      'node_name': nodeName,
      'type': type,
      'local_ip': localIp,
      'local_port': localPort,
      'remote_port': remotePort,
      'remote_address': remoteAddress,
    };
    if (toml != null) {
      tomls[localId] = toml;
      if (provider == 'custom') customToml[localId] = toml;
    }
    return localId;
  }

  /// 简易表单 → TOML（逐行复刻 daemon 的 `CustomForm::to_toml`）。
  static String easyToml(String name, Map<String, dynamic> form) {
    String text(Object? value) => value is String ? value : '';
    final buffer = StringBuffer()
      ..writeln('serverAddr = ${_tomlQuote(text(form['server_addr']).trim())}')
      ..writeln('serverPort = ${form['server_port'] ?? 7000}');
    final user = text(form['user']).trim();
    if (user.isNotEmpty) buffer.writeln('user = ${_tomlQuote(user)}');
    final token = text(form['auth_token']).trim();
    if (token.isNotEmpty) buffer.writeln('auth.token = ${_tomlQuote(token)}');
    buffer
      ..writeln('transport.tls.enable = ${form['tls_enable'] ?? true}')
      ..writeln('log.to = "console"')
      ..writeln('log.level = "info"')
      ..writeln()
      ..writeln('[[proxies]]')
      ..writeln('name = ${_tomlQuote(name)}')
      ..writeln('type = ${_tomlQuote(text(form['kind'] ?? 'tcp'))}')
      ..writeln(
        'localIP = ${_tomlQuote(text(form['local_ip'] ?? '127.0.0.1'))}',
      )
      ..writeln('localPort = ${form['local_port'] ?? 25565}')
      ..writeln('remotePort = ${form['remote_port'] ?? 0}');
    return buffer.toString();
  }

  static String _tomlQuote(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  // ── 方法处理 ────────────────────────────────────────────────────────────

  /// 处理一个 `frp.*` 调用；出错时抛 [DaemonException]（假传输会转成 error
  /// 信封，与真后端一致）。
  Map<String, dynamic> handle(String method, Map<String, dynamic> params) {
    calls[method] = (calls[method] ?? 0) + 1;
    switch (method) {
      case 'frp.providers':
        return {'providers': providers};

      case 'frp.account':
        return _account(params);

      case 'frp.login.start':
        final provider = _text(params, 'provider');
        // daemon 一起来就进 waiting；设备码只有 ChmlFrp 有
        seedSession(
          provider,
          userCode: provider == 'chmlfrp' ? 'ABCD-1234' : '',
        );
        return sessions[provider]!;

      case 'frp.login.status':
        final provider = _text(params, 'provider');
        return sessions[provider] ?? _idleSession(provider);

      case 'frp.login.cancel':
        final provider = _text(params, 'provider');
        return {'cancelled': sessions.remove(provider) != null};

      case 'frp.login.token':
        return _loginWithToken(params);

      case 'frp.logout':
        final provider = _text(params, 'provider');
        tokens.remove(provider);
        accounts.remove(provider);
        sessions.remove(provider);
        return {'ok': true};

      case 'frp.remote.tunnels':
        return {'tunnels': remoteTunnels[_requireLogin(params)] ?? const []};

      case 'frp.remote.nodes':
        return {'nodes': nodes[_requireLogin(params)] ?? const []};

      case 'frp.remote.create':
        return _createTunnel(params);

      case 'frp.remote.delete':
        final provider = _requireLogin(params);
        final remoteId = _text(params, 'remote_tunnel_id').trim();
        remoteTunnels[provider]?.removeWhere((t) => t['id'] == remoteId);
        return {'ok': true};

      case 'frp.tunnels.list':
        return {
          'tunnels': [for (final id in savedTunnels.keys) _wireTunnel(id)],
          'count': savedTunnels.length,
          'data_dir': dataDir,
        };

      case 'frp.tunnels.save':
        savedInputs.add(params);
        return _saveTunnel(params);

      case 'frp.tunnels.config':
        return _tunnelConfig(params);

      case 'frp.tunnels.remove':
        final localId = _text(params, 'local_id');
        savedTunnels.remove(localId);
        tomls.remove(localId);
        customToml.remove(localId);
        return {'ok': true};

      case 'frp.runtimes':
        final selected = savedFrpcRuntimeId;
        return {
          'runtimes': [
            for (final runtime in frpcRuntimes)
              {'id': runtime.id, 'name': runtime.name},
          ],
          // 与 daemon 一致：选过的那个还在就用它，否则回落到第一个
          'selected': frpcRuntimes.any((r) => r.id == selected)
              ? selected
              : (frpcRuntimes.isEmpty ? null : frpcRuntimes.first.id),
        };

      case 'frp.settings.save':
        savedFrpcRuntimeId = params['frpc_runtime_id'] as String?;
        return {'frpc_runtime_id': savedFrpcRuntimeId};

      case 'frp.run.list':
        return {
          'runs': [
            for (final run in runs.values) {...run},
          ],
        };

      case 'frp.run.get':
        final localId = _text(params, 'local_id');
        final run = runs[localId];
        return {
          'run': run == null
              ? null
              : {
                  ...run,
                  'log': [...?runLogs[localId]],
                },
        };

      case 'frp.run.start':
        if (runStartFails) {
          throw const DaemonException('frp_run_failed', '没装 frpc');
        }
        final localId = _text(params, 'local_id');
        // 已经在跑就**幂等**：不起第二个、状态也不变（与 daemon 一致）
        if (runs[localId]?['state'] != 'running') {
          final tunnel = savedTunnels[localId];
          seedRun(
            localId,
            tunnelName: tunnel == null ? '' : _text(tunnel.cast(), 'name'),
          );
          runLogs[localId] = ['[fake] frpc 起来了'];
        }
        return {
          'run': {...?runs[localId]},
        };

      case 'frp.run.stop':
        final localId = _text(params, 'local_id');
        runs.remove(localId);
        runLogs.remove(localId);
        return {'stopped': true};

      case 'frp.run.clear_log':
        runLogs[_text(params, 'local_id')] = [];
        return {'cleared': true};

      default:
        throw DaemonException('method_not_found', '假传输没有实现 $method');
    }
  }

  /// `frp.account`：`verify` 走「联网复核」（失败清令牌回未登录），
  /// 否则只读缓存；两条路都只给非空用户名的账号（同 `cached_account_json`）。
  Map<String, dynamic> _account(Map<String, dynamic> params) {
    final provider = _text(params, 'provider');
    if (params['verify'] == true && verifyFails) {
      tokens.remove(provider);
      accounts.remove(provider);
    }
    final account = accounts[provider];
    final visible = account != null && '${account['username']}'.isNotEmpty;
    return {
      'provider': provider,
      'logged_in': (tokens[provider] ?? '').trim().isNotEmpty,
      'account': visible ? account : null,
    };
  }

  /// `frp.login.token`：空令牌报「请输入访问 Token」，否则验过就落盘。
  Map<String, dynamic> _loginWithToken(Map<String, dynamic> params) {
    final provider = _text(params, 'provider');
    final token = _text(params, 'token').trim();
    if (token.isEmpty) {
      throw const DaemonException('invalid_params', '请输入访问 Token');
    }
    if (unauthorized) {
      throw const DaemonException('frp_unauthorized', '令牌无效或已过期');
    }
    login(provider);
    tokens[provider] = token;
    return {
      'provider': provider,
      'logged_in': true,
      'account': accounts[provider],
    };
  }

  /// `frp.remote.create`：校验名称 + 两个端口，节点从清单里取。
  Map<String, dynamic> _createTunnel(Map<String, dynamic> params) {
    created.add(params);
    final provider = _requireLogin(params);
    final name = _text(params, 'name').trim();
    final localPort = params['local_port'];
    final remotePort = params['remote_port'];
    if (name.isEmpty || localPort == null || remotePort == null) {
      throw const DaemonException('invalid_params', '请完整填写隧道名称与端口');
    }
    final nodeId = _text(params, 'node_id');
    final node = _findNode(provider, nodeId);
    if (node == null) {
      throw DaemonException('frp_node_not_found', '节点不存在或已下线（id=$nodeId）');
    }
    final hostname = '${node['hostname']}';
    seedRemoteTunnel(
      provider,
      name: name,
      nodeId: nodeId,
      nodeName: '${node['name']}',
      type: _nonEmpty(_text(params, 'type')) ?? 'tcp',
      localIp: _nonEmpty(_text(params, 'local_ip')) ?? '127.0.0.1',
      localPort: localPort as int,
      remotePort: remotePort as int,
      remoteAddress: hostname.isEmpty ? '' : '$hostname:$remotePort',
    );
    return {'ok': true};
  }

  /// `frp.tunnels.save`：两条校验 + 自定义隧道顺带生成 TOML
  /// （daemon 的 `save_tunnel` / `generate_config`）。
  Map<String, dynamic> _saveTunnel(Map<String, dynamic> params) {
    final provider = _text(params, 'provider');
    final name = _text(params, 'name').trim();
    final form = (params['custom_form'] as Map?)?.cast<String, dynamic>();
    final raw = _text(params, 'custom_toml');
    if (provider == 'custom') {
      if (form != null) {
        if (name.isEmpty ||
            _text(form, 'server_addr').trim().isEmpty ||
            form['server_port'] == null ||
            form['local_port'] == null ||
            form['remote_port'] == null) {
          throw const DaemonException('invalid_params', '请完整填写隧道名称与端口');
        }
      } else if (raw.trim().isEmpty) {
        throw const DaemonException('invalid_params', '配置内容不能为空');
      }
    }

    final given = _text(params, 'local_id');
    final localId = given.isEmpty ? _nextId() : given;
    final displayName = name.isEmpty ? 'Custom' : name;
    final localPort = form?['local_port'] ?? params['local_port'] ?? 25565;
    final remotePort = form?['remote_port'] ?? params['remote_port'];
    final serverAddr = _text(form ?? const {}, 'server_addr').trim();
    savedTunnels[localId] = {
      'local_id': localId,
      'provider': provider,
      'name': displayName,
      'remote_tunnel_id': _text(params, 'remote_tunnel_id'),
      'node_id': _text(params, 'node_id'),
      'node_name': _text(params, 'node_name'),
      'type':
          _nonEmpty(_text(form ?? const {}, 'kind')) ??
          _nonEmpty(_text(params, 'type')) ??
          'tcp',
      'local_ip':
          _nonEmpty(_text(form ?? const {}, 'local_ip')) ??
          _nonEmpty(_text(params, 'local_ip')) ??
          '127.0.0.1',
      'local_port': localPort,
      'remote_port': remotePort,
      'remote_address':
          (form != null && serverAddr.isNotEmpty && remotePort != null)
          ? '$serverAddr:$remotePort'
          : _text(params, 'remote_address'),
    };
    if (provider == 'custom') {
      customToml[localId] = form != null ? easyToml(displayName, form) : raw;
      tomls[localId] = customToml[localId]!;
    }
    return {'tunnel': _wireTunnel(localId)};
  }

  /// `frp.tunnels.config`：盘上有就读盘（`generated: false`），
  /// `refresh` 或没有才现生成（`generated: true`）。
  Map<String, dynamic> _tunnelConfig(Map<String, dynamic> params) {
    final localId = _text(params, 'local_id');
    final existing = tomls[localId];
    if (params['refresh'] != true && existing != null) {
      return {
        'config': existing,
        'path': _tomlPath(localId),
        'generated': false,
      };
    }
    final tunnel = savedTunnels[localId];
    if (tunnel == null) {
      throw DaemonException(
        'frp_tunnel_not_found',
        '本地没有隧道 `$localId`（可能已被删除）',
      );
    }
    final text = '${tunnel['provider']}' == 'custom'
        ? (customToml[localId] ?? '')
        : _standardToml(tunnel);
    if (text.trim().isEmpty) {
      throw const DaemonException('frp_config_error', '自定义配置为空');
    }
    tomls[localId] = text;
    return {'config': text, 'path': _tomlPath(localId), 'generated': true};
  }

  /// 非自定义平台的配置：照 `builder.rs::standard_toml` 的形状拼。
  String _standardToml(Map<String, Object?> tunnel) {
    final provider = '${tunnel['provider']}';
    final node = _findNode(provider, '${tunnel['node_id']}');
    final hostname = '${node?['hostname'] ?? ''}';
    final address = hostname.isNotEmpty ? hostname : '${tunnel['node_name']}';
    final buffer = StringBuffer()
      ..writeln('serverAddr = ${_tomlQuote(address)}')
      ..writeln('serverPort = ${node?['server_port'] ?? 7000}');
    final user = '${accounts[provider]?['username'] ?? ''}';
    if (user.isNotEmpty) buffer.writeln('user = ${_tomlQuote(user)}');
    buffer
      ..writeln('auth.token = ${_tomlQuote(tokens[provider] ?? '')}')
      ..writeln('log.to = "console"')
      ..writeln('log.level = "info"')
      ..writeln()
      ..writeln('[[proxies]]')
      ..writeln('name = ${_tomlQuote('${tunnel['name']}')}')
      ..writeln('type = ${_tomlQuote('${tunnel['type']}')}')
      ..writeln('localIP = ${_tomlQuote('${tunnel['local_ip']}')}')
      ..writeln('localPort = ${tunnel['local_port']}');
    final remotePort = tunnel['remote_port'];
    if (remotePort != null) buffer.writeln('remotePort = $remotePort');
    return buffer.toString();
  }

  Map<String, dynamic> _wireTunnel(String localId) => {
    ...Map<String, dynamic>.from(savedTunnels[localId]!),
    'config_exists': tomls.containsKey(localId),
  };

  String _tomlPath(String localId) => '$dataDir/toml/$localId.toml';

  /// 平台侧调用前的登录检查（真后端由各 `*_api` 抛这两个错）。
  String _requireLogin(Map<String, dynamic> params) {
    final provider = _text(params, 'provider');
    if (unauthorized) {
      throw const DaemonException('frp_unauthorized', '令牌无效或已过期');
    }
    if ((tokens[provider] ?? '').trim().isEmpty) {
      throw DaemonException('frp_not_logged_in', '尚未登录 $provider');
    }
    return provider;
  }

  Map<String, Object?>? _findNode(String provider, String id) {
    for (final node in nodes[provider] ?? const <Map<String, Object?>>[]) {
      if (node['id'] == id) return node;
    }
    return null;
  }

  static Map<String, Object?> _session(
    String provider, {
    required String state,
    String url = '',
    String userCode = '',
    String message = '',
  }) => {
    'provider': provider,
    'session_id': 'session-$provider',
    'state': state,
    'message': message,
    'url': url,
    'user_code': userCode,
    'account': null,
  };

  static Map<String, Object?> _idleSession(String provider) =>
      _session(provider, state: 'idle');

  static String _text(Map<String, dynamic> params, String key) {
    final value = params[key];
    return value is String ? value : '';
  }

  static String? _nonEmpty(String value) =>
      value.trim().isEmpty ? null : value.trim();

  String _nextId() => (++_seq).toRadixString(16).padLeft(16, '0');
}

/// 测试用的假传输:在内存里把协议跑一遍,不碰真实网络。
///
/// 它能做三件真实服务端能做的事:发 hello、按 method 回 result、
/// 主动推 event;还能模拟握手被拒与连接中断。
class FakeDaemonTransport implements DaemonTransport {
  FakeDaemonTransport({
    this.accept = true,
    this.rejectWith,
    this.helloDelay = Duration.zero,
    Map<String, Object?>? responses,
    Map<String, Object? Function(Map<String, dynamic> params)>? responders,
    this.instances,
    this.frp,
    this.runtime,
    this.upnp,
    this.stun,
  }) : responses = {...defaultResponses, ...?responses},
       responders = responders ?? const {};

  /// daemon `core.info` 的假返回值
  static const Map<String, Object?> defaultResponses = {
    'core.info': {
      'product': 'edgecube-daemon',
      'version': '2.0.0',
      'protocol_version': 1,
      'pid': 1,
      'os': 'linux',
      'arch': 'x86_64',
      'bind': '127.0.0.1:8787',
      'uptime_human': '1m 00s',
      'uptime_ms': 60000,
      'connections': 1,
      'subscribers': 0,
      'auth_required': true,
      'config_path': null,
      'shutting_down': false,
    },
    // daemon `core.host` 的假返回值：关于页的「后端运行设备」用。
    'core.host': {
      'hostname': 'edgecube-test',
      'os_name': 'Linux',
      'os_version': '6.8.0-test',
      'kernel_version': '6.8.0-test',
      'arch': 'x86_64',
      'cpu_brand': 'Test CPU',
      'cpu_cores': 8,
      'cpu_physical_cores': 4,
      'memory_total_mb': 16384,
      'uptime_secs': 90061,
    },
    // daemon `monitor.snapshot` 的假返回值。形状照真后端抄（形状不对的话
    // e2e 用例会先炸，所以这里只当便捷默认值用）。
    'monitor.snapshot': {
      'sampled_at_ms': 1700000000000,
      'interval_ms': 2000,
      'supported': true,
      'total_mem_mb': 31845,
      'used_mem_mb': 10253,
      'available_mem_mb': 21592,
      'used_mem_percent': 32.2,
      'cpu_usage': 11.0,
      'cpu_cores': 8,
      'server_mem_mb': null,
    },
  };

  /// 是否接受握手
  final bool accept;

  /// 拒绝时抛出的异常(默认当成"连不上")
  final DaemonException? rejectWith;

  /// 握手包延迟多久发出(用于制造"连接还在途中"的竞态)
  final Duration helloDelay;

  final Map<String, Object?> responses;

  /// **按每次调用**算出来的返回（参数进、结果出）。
  ///
  /// 给「同一个方法的两次调用要回不一样的东西」用 —— 比如 `download.add`
  /// 每次都是一个新任务 id（真后端就是这样，而固定返回会让两轮流程命中同一个
  /// provider 实例，测出假象）。优先级高于 [responses]；抛 [DaemonException]
  /// 会照常变成 error 信封。
  final Map<String, Object? Function(Map<String, dynamic> params)> responders;

  /// 内存实例后端；给了它就会接管所有 `instance.*` 调用。
  final FakeInstanceStore? instances;

  /// 内存 FRP 后端；给了它就会接管所有 `frp.*` 调用。
  final FakeFrpStore? frp;

  /// 内存运行环境后端；给了它就会接管所有 `runtime.*` 调用。
  final FakeRuntimeStore? runtime;

  /// 内存 UPnP 后端；给了它就会接管所有 `upnp.*` 调用。
  final FakeUpnpStore? upnp;

  /// 内存 STUN 后端；给了它就会接管所有 `stun.*` 调用。
  final FakeStunStore? stun;

  /// 客户端实际连接的地址,用来断言令牌是否放进了查询串
  Uri? uri;

  final _incoming = StreamController<String>.broadcast();
  final _sent = <Map<String, dynamic>>[];
  bool _closed = false;

  /// 客户端发出去的所有信封
  List<Map<String, dynamic>> get sent => List.unmodifiable(_sent);

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> connect(Uri uri) async {
    this.uri = uri;
    if (!accept) {
      throw rejectWith ?? const DaemonException('disconnected', '测试:无法连接到服务端');
    }
    if (helloDelay == Duration.zero) {
      _emit(helloFor(uri));
    } else {
      Timer(helloDelay, () => _emit(helloFor(uri)));
    }
  }

  /// 服务端握手包
  static Map<String, Object?> helloFor(Uri uri) => {
    'type': 'hello',
    'protocol': 1,
    'product': 'edgecube-daemon',
    'version': '2.0.0',
    'pid': 1,
    'conn_id': 1,
    'peer': '127.0.0.1:55555',
    'started_at_ms': 0,
    'auth_required': true,
    'config_path': null,
    'modules': [
      {'id': 'core'},
      {'id': 'ticker'},
      {'id': 'monitor'},
      {'id': 'instance'},
      {'id': 'upnp'},
      {'id': 'stun'},
    ],
    'methods': [
      {'name': 'core.ping'},
      {'name': 'core.host'},
      {'name': 'ticker.start'},
      {'name': 'monitor.snapshot'},
      {'name': 'monitor.status'},
      {'name': 'instance.list'},
      {'name': 'frp.providers'},
      {'name': 'frp.tunnels.save'},
      {'name': 'upnp.status'},
      {'name': 'upnp.probe'},
      {'name': 'stun.status'},
      {'name': 'stun.settings.set'},
      {'name': 'stun.logs'},
      {'name': 'stun.logs.clear'},
    ],
    'topics': [
      {'topic': 'ticker.tick'},
      {'topic': 'monitor.stats'},
      {'topic': 'instance.created'},
      {'topic': 'frp.login'},
      {'topic': 'upnp.evt'},
      {'topic': 'stun.evt'},
    ],
    'max_inflight_calls': 32,
    'request_timeout_secs': 30,
    'ts': 0,
  };

  @override
  void send(String payload) {
    final Map<String, dynamic> envelope;
    try {
      envelope = (jsonDecode(payload) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    _sent.add(envelope);
    final id = envelope['id'];
    // 模拟服务端异步处理:下一轮微任务再回包
    scheduleMicrotask(() {
      if (_closed) return;
      switch (envelope['type']) {
        case 'call':
          final method = envelope['method'] as String?;
          final params =
              (envelope['params'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          try {
            final Object? result;
            if (instances != null && (method ?? '').startsWith('instance.')) {
              result = instances!.handle(method!, params);
            } else if (frp != null && (method ?? '').startsWith('frp.')) {
              result = frp!.handle(method!, params);
            } else if (runtime != null &&
                (method ?? '').startsWith('runtime.')) {
              result = runtime!.handle(method!, params);
            } else if (upnp != null && (method ?? '').startsWith('upnp.')) {
              result = upnp!.handle(method!, params);
            } else if (stun != null && (method ?? '').startsWith('stun.')) {
              result = stun!.handle(method!, params);
            } else if (responders[method] case final responder?) {
              result = responder(params);
            } else if (responses.containsKey(method)) {
              result = responses[method];
            } else {
              throw DaemonException('method_not_found', '假传输没有实现 $method');
            }
            _emit({'type': 'result', 'id': id, 'ok': true, 'result': result});
          } on DaemonException catch (error) {
            _emit({
              'type': 'result',
              'id': id,
              'ok': false,
              'error': {'code': error.code, 'message': error.message},
            });
          }
        case 'subscribe':
          _emit({
            'type': 'result',
            'id': id,
            'ok': true,
            'result': {'topic': envelope['topic']},
          });
        case 'unsubscribe':
          _emit({
            'type': 'result',
            'id': id,
            'ok': true,
            'result': {'unsubscribed': true},
          });
        case 'ping':
          _emit({'type': 'pong', 'id': id, 'ts': 0});
      }
    });
  }

  /// 服务端主动推送一条事件
  void pushEvent(String topic, [Map<String, Object?> data = const {}]) =>
      _emit({
        'type': 'event',
        'topic': topic,
        'seq': 1,
        'ts': 0,
        'source': 'fake',
        'data': data,
      });

  /// 模拟连接中断(触发客户端掉线处理)
  void dropConnection() {
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    _closed = true;
    if (!_incoming.isClosed) _incoming.close();
  }

  void _emit(Map<String, Object?> frame) {
    if (_incoming.isClosed) return;
    _incoming.add(jsonEncode(frame));
  }
}

/// 每次连接都新建一个假传输(重连时才会拿到干净的一条)。
///
/// 客户端每次 `connect` 都会调用一次工厂,所以重连场景下
/// [latest] 指向的是当前这条连接。
class FakeTransportFactory {
  FakeTransportFactory({
    this.accept = true,
    this.rejectWith,
    this.helloDelay = Duration.zero,
    this.responses,
    this.responders,
    FakeInstanceStore? instances,
    this.frp,
    this.runtime,
    FakeUpnpStore? upnp,
    FakeStunStore? stun,
  }) : instances = instances ?? FakeInstanceStore(),
       upnp = upnp ?? FakeUpnpStore(),
       stun = stun ?? FakeStunStore();

  final List<FakeDaemonTransport> created = [];
  bool accept;
  DaemonException? rejectWith;
  Duration helloDelay;
  Map<String, Object?>? responses;

  /// 按调用算的返回；见 [FakeDaemonTransport.responders]。
  Map<String, Object? Function(Map<String, dynamic> params)>? responders;

  /// 内存实例后端。**默认就有一个**：真 daemon 必然挂着 instance 模块，假后端
  /// 缺了它 `instance.list` 会以 `method_not_found` 失败 —— riverpod 会给失败的
  /// 服务排一个重试定时器，widget 测试收尾时撞上「A Timer is still pending」。
  /// 要摆数据就自己传一个进来。
  FakeInstanceStore instances;
  FakeFrpStore? frp;
  FakeRuntimeStore? runtime;

  /// 内存 UPnP 后端。**默认就有一个**，理由同 [instances]：网络映射页一进来
  /// 就拉 `upnp.status`，缺了它 provider 会带错误静默重试，widget 测试收尾撞上
  /// 「A Timer is still pending」。要摆数据就自己传一个进来。
  FakeUpnpStore upnp;

  /// 内存 STUN 后端。**默认就有一个**，理由同 [upnp]：网络映射页一进来就拉
  /// `stun.status`，缺了它 provider 会带错误静默重试，widget 测试收尾撞上
  /// 「A Timer is still pending」。
  FakeStunStore stun;

  FakeDaemonTransport get latest => created.last;

  int get count => created.length;

  DaemonTransport call() {
    final transport = FakeDaemonTransport(
      accept: accept,
      rejectWith: rejectWith,
      helloDelay: helloDelay,
      responses: responses,
      responders: responders,
      instances: instances,
      frp: frp,
      runtime: runtime,
      upnp: upnp,
      stun: stun,
    );
    created.add(transport);
    return transport;
  }
}

/// 内存里的控制台连接：够验协议解析，不用真起 daemon。
class FakePtyTransport implements PtyTransport {
  final _frames = StreamController<dynamic>.broadcast();
  final sent = <dynamic>[];
  bool closed = false;

  /// 客户端 → 服务端发过的原始输出（二进制帧解码成的字符串）。
  ///
  /// 玩家管理这类「往控制台写命令」的用例只关心这个。
  List<String> get typed => [
    for (final frame in sent)
      if (frame is List<int>) utf8.decode(frame),
  ];

  @override
  Stream<dynamic> get frames => _frames.stream;

  @override
  void send(dynamic frame) => sent.add(frame);

  @override
  Future<void> close() async {
    closed = true;
    if (!_frames.isClosed) await _frames.close();
  }

  /// 服务端 → 客户端：文本帧（控制 JSON）
  void pushControl(Map<String, Object?> json) => _frames.add(jsonEncode(json));

  /// 服务端 → 客户端：二进制帧（原始输出）
  void pushBytes(List<int> bytes) => _frames.add(bytes);

  /// 模拟连接断开。
  void drop() {
    if (!_frames.isClosed) _frames.close();
  }
}

/// 复刻 `main()` 的启动路径:预加载 → override。
///
/// 直接返回建好的容器(而不是丢一个 overrides 列表出来),
/// 因为 riverpod 3 不再从 `flutter_riverpod` 导出 `Override` 类型。
ProviderContainer bootContainer({
  required SharedPreferences storage,
  AppearanceSettings appearance = const AppearanceSettings(),
  ConnectionSettings? persisted,
  required DaemonTransportFactory transportFactory,
  FileTransfer? fileTransfer,
  PtyTransport? ptyTransport,
  PtyTransport Function(Uri)? ptyTransportFactory,
  bool localServiceEnabled = false,
  LocalServicePlatform? localServicePlatform,
}) => ProviderContainer(
  overrides: [
    storageProvider.overrideWithValue(storage),
    initialAppearanceProvider.overrideWithValue(appearance),
    initialPersistedConnectionProvider.overrideWithValue(persisted),
    initialConnectionSettingsProvider.overrideWithValue(
      persisted ?? ConnectionSettings.empty,
    ),
    initialLocalServiceEnabledProvider.overrideWithValue(localServiceEnabled),
    daemonTransportFactoryProvider.overrideWithValue(transportFactory),
    if (localServicePlatform != null)
      localServicePlatformProvider.overrideWithValue(localServicePlatform),
    // 不给就还是真的 HttpFileTransfer（会去连网络），文件测试记得传假的
    if (fileTransfer != null)
      fileTransferProvider.overrideWithValue(fileTransfer),
    // 不给就还是真的 WebSocket（会去连网络），控制台相关测试记得传假的。
    // 需要「每次重连都是一个新连接」的用例传 ptyTransportFactory。
    if (ptyTransportFactory != null)
      ptyTransportFactoryProvider.overrideWithValue(ptyTransportFactory)
    else if (ptyTransport != null)
      ptyTransportFactoryProvider.overrideWithValue((_) => ptyTransport),
  ],
);
