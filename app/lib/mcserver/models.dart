/// 服务端目录的线上模型。
///
/// 字段名与 daemon 的线上格式一一对应（snake_case）。类型表、文件名、建议启动命令
/// 全部由 daemon 给（`mcserver.types`），前端**不硬编码**任何源的知识 ——
/// daemon 加一个源，App 不用改。
library;

import '../download/models.dart';

/// 一个服务端分类（向导第一层要选的东西）。
class ServerCategory {
  const ServerCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.types,
  });

  final String id;
  final String name;
  final String description;

  /// 这个分类下的类型 id，顺序即展示顺序。
  final List<String> types;

  static ServerCategory fromJson(Map<String, dynamic> json) {
    final raw = json['types'];
    return ServerCategory(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      types: [
        if (raw is List)
          for (final item in raw)
            if (item is String) item,
      ],
    );
  }
}

/// 一个可下载的服务端类型。
class ServerKind {
  const ServerKind({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.fileName,
    required this.startupCommand,
    required this.checksum,
    required this.needsVersion,
    required this.needsLoader,
  });

  final String id;
  final String name;
  final String description;

  /// 所属分类 id。
  final String category;

  /// 落盘文件名（daemon 定死的）。
  final String fileName;

  /// 建议的启动命令。实例只有一个 `startupCommand`，这就是要写进去的那条。
  final String startupCommand;

  /// 上游能提供的校验算法：`sha1` / `sha256` / `md5` / `none`。
  final String checksum;

  /// 要不要先选版本（BungeeCord 只有 latest，没有版本概念）。
  final bool needsVersion;

  /// 还要不要选一个加载器版本（目前只有 Fabric）。
  final bool needsLoader;

  /// 上游给不给校验值。
  bool get hasChecksum => checksum != 'none';

  static ServerKind fromJson(Map<String, dynamic> json) {
    return ServerKind(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      startupCommand: json['startup_command']?.toString() ?? '',
      checksum: json['checksum']?.toString() ?? 'none',
      needsVersion: json['needs_version'] != false,
      needsLoader: json['needs_loader'] == true,
    );
  }
}

/// 分类 + 类型表。
class ServerCatalog {
  const ServerCatalog({required this.categories, required this.kinds});

  final List<ServerCategory> categories;
  final List<ServerKind> kinds;

  static const ServerCatalog empty = ServerCatalog(
    categories: [],
    kinds: [],
  );

  ServerKind? byId(String id) {
    for (final kind in kinds) {
      if (kind.id == id) return kind;
    }
    return null;
  }

  /// 某个分类下的类型（按分类里声明的顺序）。
  List<ServerKind> kindsOf(ServerCategory category) {
    final result = <ServerKind>[];
    for (final id in category.types) {
      final kind = byId(id);
      if (kind != null) result.add(kind);
    }
    return result;
  }

  static ServerCatalog fromJson(Map<String, dynamic> json) {
    final categories = json['categories'];
    final kinds = json['types'];
    return ServerCatalog(
      categories: [
        if (categories is List)
          for (final item in categories)
            if (item is Map)
              ServerCategory.fromJson(item.cast<String, dynamic>()),
      ],
      kinds: [
        if (kinds is List)
          for (final item in kinds)
            if (item is Map) ServerKind.fromJson(item.cast<String, dynamic>()),
      ],
    );
  }
}

/// `mcserver.plan` 的结果：把「选了什么」翻译成「下什么」。
///
/// 前端拿到它之后就是三步：`instance.create`（用 [startupCommand]）→
/// `download.add`（用 [url] / [fileName] / [checksum]）。
class ServerPlan {
  const ServerPlan({
    required this.type,
    required this.typeName,
    required this.version,
    required this.url,
    required this.fileName,
    required this.startupCommand,
    this.loaderVersion,
    this.checksum,
  });

  final String type;
  final String typeName;
  final String version;

  /// 只有需要加载器的源（Fabric）才有。
  final String? loaderVersion;

  final String url;
  final String fileName;
  final String startupCommand;

  /// `null` 表示上游没给校验值（Fabric / BungeeCord），下载就不带校验。
  final DownloadChecksum? checksum;

  /// 展示用的一句话（`Paper 1.21.8`、`Fabric 1.21.8 + 0.16.14`）。
  String get label => loaderVersion == null
      ? '$typeName $version'
      : '$typeName $version + $loaderVersion';

  static ServerPlan fromJson(Map<String, dynamic> json) {
    return ServerPlan(
      type: json['type']?.toString() ?? '',
      typeName: json['type_name']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      loaderVersion: json['loader_version']?.toString(),
      url: json['url']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      startupCommand: json['startup_command']?.toString() ?? '',
      checksum: DownloadChecksum.fromJson(json['checksum']),
    );
  }
}
