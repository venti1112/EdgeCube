import '../connection/client.dart';

/// 实例目录里的一个条目（文件 / 文件夹 / 符号链接）。
///
/// 字段与 daemon `files.rs` 的 `Entry` 一一对应；`path` 是**相对实例目录**的
/// `/` 分隔路径，也是所有文件方法的寻址键。
class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.isLink,
    this.linkTarget,
    this.size = 0,
    this.modifiedMs,
  });

  final String name;
  final String path;
  final bool isDir;
  final bool isLink;

  /// 符号链接的目标（原样，可能是相对路径）；不是链接时为 null。
  final String? linkTarget;

  /// 文件字节数；目录为 0。
  final int size;

  final int? modifiedMs;

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
    isDir: json['is_dir'] as bool? ?? false,
    isLink: json['is_link'] as bool? ?? false,
    linkTarget: json['link_target'] as String?,
    size: (json['size'] as num?)?.toInt() ?? 0,
    modifiedMs: (json['modified_ms'] as num?)?.toInt(),
  );

  DateTime? get modified => modifiedMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(modifiedMs!);

  /// 「点一下行就直接进编辑器」的文本文件（按扩展名判断，
  /// 见 [`textExtensions`]）。白名单外的文件照样能从「更多」菜单里选编辑，只是不做直接打开。
  bool get isEditableText =>
      !isDir && textExtensions.contains(extensionOf(name));

  /// 能解压的归档（daemon 的 archive 模块认的格式，见 [`archiveSuffixes`]）。
  bool get isArchive => !isDir && hasArchiveSuffix(name);

  /// 能直接在 App 里预览的图片（点一下行就打开看图，按扩展名判断）。
  bool get isImage => !isDir && imageExtensions.contains(extensionOf(name));

  @override
  String toString() => 'FileEntry($path${isDir ? '/, dir' : ''})';
}

/// 内置编辑器认的文本扩展名（小写，含点）。
const Set<String> textExtensions = {
  '.txt',
  '.text',
  '.md',
  '.markdown',
  '.log',
  '.properties',
  '.conf',
  '.cfg',
  '.ini',
  '.toml',
  '.env',
  '.list',
  '.yml',
  '.yaml',
  '.json',
  '.json5',
  '.xml',
  '.html',
  '.htm',
  '.css',
  '.js',
  '.ts',
  '.sh',
  '.bat',
  '.cmd',
  '.py',
  '.lua',
  '.csv',
  '.tsv',
  '.lang',
  '.mcmeta',
  '.snbt',
};

/// 能解压的归档后缀（与 daemon 的 `instance/archive` 一一对应）。
///
/// **必须按长度降序**：`.tar.gz` 要排在 `.gz` 前面，否则复合后缀会被
/// 单流格式抢先认走、按「解成一个文件」处理。
const List<String> archiveSuffixes = [
  '.tar.bz2',
  '.tar.lz4',
  '.tar.zst',
  '.tar.gz',
  '.tar.xz',
  '.tbz2',
  '.tzst',
  '.tgz',
  '.txz',
  '.tar',
  '.zip',
  '.7z',
  '.rar',
  '.bz2',
  '.zst',
  '.lz4',
  '.gz',
  '.xz',
];

/// 名字是不是能解压的归档（大小写不敏感）。
bool hasArchiveSuffix(String name) {
  final lower = name.toLowerCase();
  return archiveSuffixes.any(lower.endsWith);
}

/// 能直接预览的图片扩展名（小写，含点）。
///
/// 全在 Flutter 的 `Image`/`instantiateImageCodec` 原生解码范围里 ——
/// **不引图片解码依赖**（与服务端图标同一条取舍）。`server-icon.png`、
/// 插件与材质包里的 png/webp 都在这张表里。
const Set<String> imageExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
};

/// `mods/jei.jar` → `.jar`；没有扩展名（或点开头）→ 空串。
String extensionOf(String name) {
  final at = name.lastIndexOf('.');
  return at > 0 ? name.substring(at).toLowerCase() : '';
}

/// 目录列表（`instance.files.list` 的返回值）。
class FileListing {
  const FileListing({required this.path, required this.entries});

  static const empty = FileListing(path: '', entries: []);

  /// 被列出的目录（相对实例目录，`''` = 根）。
  final String path;
  final List<FileEntry> entries;

  factory FileListing.fromJson(Map<String, dynamic> json) => FileListing(
    path: json['path'] as String? ?? '',
    entries: entriesOf(json['entries']),
  );
}

/// 搜索结果（`instance.files.search` 的返回值）。
class SearchOutcome {
  const SearchOutcome({
    required this.entries,
    this.truncated = false,
  });

  static const empty = SearchOutcome(entries: []);

  final List<FileEntry> entries;

  /// 结果被 daemon 的上限截断了（`search_max_results`）。
  final bool truncated;

  factory SearchOutcome.fromJson(Map<String, dynamic> json) => SearchOutcome(
    entries: entriesOf(json['entries']),
    truncated: json['truncated'] as bool? ?? false,
  );
}

/// 读文本文件的返回值（`instance.files.read`）。
class TextFile {
  const TextFile({
    required this.path,
    required this.name,
    required this.content,
    required this.encoding,
    required this.size,
  });

  final String path;
  final String name;
  final String content;

  /// `utf-8` 或 `latin1`（后者是「强制打开」走的路）。
  final String encoding;
  final int size;

  factory TextFile.fromJson(Map<String, dynamic> json) => TextFile(
    path: json['path'] as String? ?? '',
    name: json['name'] as String? ?? '',
    content: json['content'] as String? ?? '',
    encoding: json['encoding'] as String? ?? 'utf-8',
    size: (json['size'] as num?)?.toInt() ?? 0,
  );
}

List<FileEntry> entriesOf(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) FileEntry.fromJson(item.cast<String, dynamic>()),
  ];
}

/// `1536` → `1.5 KB`（1024 进位）。
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}

/// 去掉归档名的全部扩展名，作为解压子文件夹的缺省名
/// （`world.tar.gz` → `world`；与 daemon 的 `archive_base_name` 同规则）。
String archiveBaseName(String name) {
  final lower = name.toLowerCase();
  for (final ext in const [
    '.tar.gz',
    '.tar.xz',
    '.tar.bz2',
    '.tar.zst',
    '.tar.lz4',
  ]) {
    if (lower.endsWith(ext)) return name.substring(0, name.length - ext.length);
  }
  final at = name.lastIndexOf('.');
  return at > 0 ? name.substring(0, at) : name;
}

/// 把文件模块的错误翻成给用户看的一句话（UI 按 `code` 分支，见 `files.rs`）。
String describeFileError(Object error) {
  if (error is DaemonException) {
    return switch (error.code) {
      'file_not_found' => '条目不存在（可能已被删除）',
      'file_exists' => '目标位置已存在同名条目',
      'file_not_utf8' => '这个文件不是 UTF-8 文本，可以强制按 latin1 打开',
      'file_too_large' => '文件太大，超过服务端的编辑器上限',
      'file_archive' => '压缩包处理失败：${error.message}',
      'file_invalid_destination' => '不能把文件夹放进它自己里面',
      'file_io' => '文件操作失败：${error.message}',
      'disconnected' => '连接已断开',
      _ => error.message,
    };
  }
  return '$error';
}
