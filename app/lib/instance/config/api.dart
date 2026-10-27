import 'dart:convert';
import 'dart:typed_data';

import '../../connection/client.dart';
import 'draft.dart';
import 'parsers.dart';

/// 「服务器配置」接口。
///
/// daemon 那两个方法刻意做得很小（见 `daemon/src/module/builtin/instance/config.rs`）：
/// 「有哪种配置」的**判断在后端**，前端只拿结果。所以这里没有「问一下 pnx.yml
/// 在不在」这种调用，只有「读这份配置」与「写这份配置」。
class InstanceConfigApi {
  const InstanceConfigApi(this._client);

  final DaemonClient _client;

  /// 读配置：daemon 认类型 + 回内容。
  ///
  /// 一个实例都没有配置时 `kind` 是 `null`（`exists: false`），调用方给
  /// 「先启动一次服务端」那句话 —— 这不是错误，所以不抛。
  Future<InstanceConfigSource> get(String id) async {
    final result = await _client.callObject(
      'instance.config.get',
      params: {'id': id},
    );
    return InstanceConfigSource.fromJson(result);
  }

  /// 写回配置。
  ///
  /// 只传 `kind` 与整份文本：**写哪个文件由 daemon 按 `kind` 算**，前端给不了
  /// 路径（那会是个「按 id 写任意文件」的洞）。
  Future<void> save(String id, String kind, String content) async {
    await _client.callObject(
      'instance.config.save',
      params: {'id': id, 'kind': kind, 'content': content},
    );
  }

  /// 读服务端图标（`server-icon.png`）。**没有图标不是错误**。
  Future<ServerIcon> iconGet(String id) async {
    final result = await _client.callObject(
      'instance.config.icon.get',
      params: {'id': id},
    );
    return ServerIcon.fromJson(result);
  }

  /// 写服务端图标。
  ///
  /// [png] 必须是 **64×64 的 PNG** —— daemon 会校验（Minecraft 对尺寸不符的图标
  /// 是静默忽略，那种「改了没反应」最难查）。尺寸不对会抛
  /// `instance_icon_invalid`。
  Future<void> iconSave(String id, Uint8List png) async {
    await _client.callObject(
      'instance.config.icon.save',
      params: {'id': id, 'data': base64Encode(png)},
    );
  }
}

/// 服务端图标的读取结果。
class ServerIcon {
  const ServerIcon({required this.file, required this.exists, this.bytes});

  /// 文件名（daemon 给的，界面直接显示）。
  final String file;

  final bool exists;

  /// 原样字节；没有图标时为 `null`。
  final Uint8List? bytes;

  factory ServerIcon.fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    return ServerIcon(
      file: json['file']?.toString() ?? 'server-icon.png',
      exists: json['exists'] == true,
      bytes: raw is String ? base64Decode(raw) : null,
    );
  }
}

/// 一次读取的结果。
class InstanceConfigSource {
  const InstanceConfigSource({
    required this.kind,
    required this.file,
    required this.exists,
    required this.content,
  });

  /// `pnx` / `allay` / `java` / `pmmp`；`null` = 这个实例还没有配置文件。
  final String? kind;

  /// 文件名（`server.properties` 等）。没有配置时是默认那个，用于拼提示语。
  final String file;

  final bool exists;

  /// 文件原文。
  final String content;

  factory InstanceConfigSource.fromJson(Map<String, dynamic> json) {
    return InstanceConfigSource(
      kind: json['kind'] as String?,
      file: json['file']?.toString() ?? 'server.properties',
      exists: json['exists'] == true,
      content: json['content']?.toString() ?? '',
    );
  }

  /// 解析成可编辑的草稿。没有配置时返回 `null`。
  ConfigDraft? toDraft() {
    final kind = this.kind;
    if (kind == null) return null;
    return ConfigDraft(
      kind: kind,
      file: file,
      document: ConfigDocument.parse(kind, content),
    );
  }
}
