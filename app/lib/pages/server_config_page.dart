import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/config/allay_properties.dart';
import '../server/config/pnx_properties.dart';
import '../server/config/server_properties.dart';
import '../server/server_service.dart';
import 'api_error.dart';
import 'current_instance.dart';
import 'server_icon_crop_page.dart';

/// 通用服务器配置编辑页(移植自 V1 的 ServerPropertiesPage / PnxPropertiesPage /
/// AllayPropertiesPage,三页合一)。
///
/// 进入页面后自动检测实例目录下的配置文件(优先级:pnx.yml > server-settings.yml
/// > server.properties),选择对应的解析器与属性分组,以分组卡片可视化编辑,
/// 保存回写原文件(保留注释与格式)。Java 实例额外提供 `server-icon.png` 图标
/// 上传(相册选图 → 裁剪为 64×64 PNG → 分片上传覆盖)。
///
/// 文件读写复用 V2 `/fs/*` 沙箱接口:listFiles 探测配置文件存在性,
/// downloadFile 读取文本,writeFile 覆盖保存,分片上传三段式写图标。
class ServerConfigPage extends ConsumerStatefulWidget {
  const ServerConfigPage({super.key});

  @override
  ConsumerState<ServerConfigPage> createState() => _ServerConfigPageState();
}

// ---------------------------------------------------------------------------
// 属性元数据定义
// ---------------------------------------------------------------------------

/// 配置类型。
enum _ConfigKind { vanilla, pnx, allay }

/// 属性编辑器类型。
enum _PropKind { text, number, toggle, dropdown }

/// 单个属性的元数据,驱动 UI 渲染。
class _PropDef {
  const _PropDef({
    required this.key,
    required this.label,
    this.subtitle,
    required this.kind,
    this.options,
    this.min,
    this.max,
    this.boolFormat = BoolFormat.trueFalse,
  });

  /// 配置中的 key(vanilla 为 `key`;pnx 为 `section.key`;allay 为 `a.b.c`)。
  final String key;

  /// UI 显示名称。
  final String label;

  /// 辅助说明(可选)。
  final String? subtitle;

  /// 编辑器类型。
  final _PropKind kind;

  /// 下拉选项(kind == dropdown 时使用),格式为 value → 显示文本。
  final Map<String, String>? options;

  /// 数字最小值(kind == number 时使用)。
  final int? min;

  /// 数字最大值(kind == number 时使用)。
  final int? max;

  /// 布尔值序列化格式(kind == toggle 时使用)。
  final BoolFormat boolFormat;
}

/// 属性分组定义。
class _Section {
  const _Section(this.title, this.icon, this.props);

  final String title;
  final IconData icon;
  final List<_PropDef> props;
}

/// 配置文件解析结果的统一访问抽象(屏蔽三种解析器的差异)。
abstract class _PropsStore {
  String? get(String key);
  void set(String key, String value);
  bool containsKey(String key);
  String serialize();
}

class _ServerPropsStore implements _PropsStore {
  _ServerPropsStore(this._props);
  final ServerProperties _props;

  @override
  String? get(String key) => _props[key];

  @override
  void set(String key, String value) => _props[key] = value;

  @override
  bool containsKey(String key) => _props.containsKey(key);

  @override
  String serialize() => _props.toString();
}

class _PnxPropsStore implements _PropsStore {
  _PnxPropsStore(this._props);
  final PnxProperties _props;

  @override
  String? get(String key) => _props[key];

  @override
  void set(String key, String value) => _props[key] = value;

  @override
  bool containsKey(String key) => _props.containsKey(key);

  @override
  String serialize() => _props.toString();
}

class _AllayPropsStore implements _PropsStore {
  _AllayPropsStore(this._props);
  final AllayProperties _props;

  @override
  String? get(String key) => _props[key];

  @override
  void set(String key, String value) => _props[key] = value;

  @override
  bool containsKey(String key) => _props.containsKey(key);

  @override
  String serialize() => _props.toString();
}

// ---------------------------------------------------------------------------
// 下拉选项
// ---------------------------------------------------------------------------

const _gamemodeOptions = {
  'survival': '生存模式',
  'creative': '创造模式',
  'adventure': '冒险模式',
  'spectator': '旁观模式',
};

/// PMMP gamemode 用大写值。
const _gamemodeOptionsPmmp = {
  'SURVIVAL': '生存模式',
  'CREATIVE': '创造模式',
  'ADVENTURE': '冒险模式',
  'SPECTATOR': '旁观模式',
};

const _difficultyOptions = {
  'peaceful': '和平',
  'easy': '简单',
  'normal': '普通',
  'hard': '困难',
};

/// PMMP 难度用数字 0-3。
const _difficultyOptionsPmmp = {
  '0': '和平',
  '1': '简单',
  '2': '普通',
  '3': '困难',
};

const _languageOptionsPmmp = {
  'chs': '简体中文',
  'cht': '繁體中文',
  'eng': 'English',
  'jpn': '日本語',
  'kor': '한국어',
  'deu': 'Deutsch',
  'fra': 'Français',
  'rus': 'Русский',
  'spa': 'Español',
};

/// PMMP level-type 选项。
const _levelTypeOptionsPmmp = {
  'DEFAULT': '默认',
  'FLAT': '超平坦',
  'NETHER': '下界',
  'VOID': '虚空',
  'SKYBLOCK': '空岛',
};

/// PNX gamemode 用数字 0-3。
const _pnxGamemodeOptions = {
  '0': '生存模式',
  '1': '创造模式',
  '2': '冒险模式',
  '3': '旁观模式',
};

const _pnxDifficultyOptions = {
  '0': '和平',
  '1': '简单',
  '2': '普通',
  '3': '困难',
};

const _pnxLanguageOptions = {
  'chs': '简体中文',
  'cht': '繁體中文',
  'eng': 'English',
  'jpn': '日本語',
  'kor': '한국어',
  'deu': 'Deutsch',
  'fra': 'Français',
  'rus': 'Русский',
  'spa': 'Español',
};

const _allayGamemodeOptions = {
  'SURVIVAL': '生存',
  'CREATIVE': '创造',
  'ADVENTURE': '冒险',
  'SPECTATOR': '旁观',
};

const _allayDifficultyOptions = {
  'PEACEFUL': '和平',
  'EASY': '简单',
  'NORMAL': '普通',
  'HARD': '困难',
};

const _allayPermissionOptions = {
  'VISITOR': '访客',
  'MEMBER': '成员',
  'OPERATOR': '管理员',
};

const _allayCompressionOptions = {
  'ZLIB': 'ZLIB(高压缩比)',
  'SNAPPY': 'SNAPPY(高性能)',
};

const _allayChunkSendingOptions = {
  'ASYNC': '异步',
  'SYNC': '同步',
};

const _allayLanguageOptions = {
  'en_US': 'English',
  'zh_CN': '简体中文',
  'ja_JP': '日本語',
  'ru_RU': 'Русский',
  'es_ES': 'Español',
  'de_DE': 'Deutsch',
  'fr_FR': 'Français',
  'pt_BR': 'Português',
  'ko_KR': '한국어',
};

// ---------------------------------------------------------------------------
// Java server.properties 属性分组
// ---------------------------------------------------------------------------

const _javaSections = <_Section>[
  _Section('基础设置', Icons.settings_outlined, [
    _PropDef(
      key: 'motd',
      label: '服务器描述 (MOTD)',
      subtitle: '在服务器列表中显示的描述文字',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'max-players',
      label: '最大玩家数',
      kind: _PropKind.number,
      min: 1,
      max: 10000,
    ),
    _PropDef(
      key: 'gamemode',
      label: '默认游戏模式',
      kind: _PropKind.dropdown,
      options: _gamemodeOptions,
    ),
    _PropDef(
      key: 'difficulty',
      label: '难度',
      kind: _PropKind.dropdown,
      options: _difficultyOptions,
    ),
    _PropDef(key: 'level-name', label: '世界名称', kind: _PropKind.text),
    _PropDef(
      key: 'level-seed',
      label: '世界种子',
      subtitle: '留空则随机生成',
      kind: _PropKind.text,
    ),
    _PropDef(key: 'level-type', label: '世界类型', kind: _PropKind.text),
  ]),
  _Section('游戏玩法', Icons.sports_esports_outlined, [
    _PropDef(
      key: 'hardcore',
      label: '极限模式',
      subtitle: '启用后难度锁定为困难,死亡后变为旁观模式',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'allow-flight',
      label: '允许飞行',
      subtitle: '启用后生存模式下也可飞行(反作弊不踢出)',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'force-gamemode',
      label: '强制游戏模式',
      subtitle: '玩家每次加入时重置为默认游戏模式',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'generate-structures',
      label: '生成结构',
      subtitle: '是否生成村庄等自然结构',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'spawn-protection',
      label: '出生点保护范围',
      subtitle: '出生点周围禁止非 OP 操作的方块数(0 为禁用)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'max-world-size',
      label: '最大世界大小',
      subtitle: '世界边界的最大半径(方块数)',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      key: 'player-idle-timeout',
      label: '玩家挂机超时',
      subtitle: '挂机多少分钟后踢出(0 为不踢出)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'function-permission-level',
      label: '函数权限等级',
      kind: _PropKind.number,
      min: 1,
      max: 4,
    ),
    _PropDef(
      key: 'op-permission-level',
      label: 'OP 权限等级',
      kind: _PropKind.number,
      min: 1,
      max: 4,
    ),
    _PropDef(
      key: 'enforce-secure-profile',
      label: '强制安全档案',
      subtitle: '要求玩家拥有 Mojang 签名的聊天消息',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'enable-command-block',
      label: '启用命令方块',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'pvp',
      label: '启用 PvP',
      subtitle: '玩家之间是否允许互相攻击',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'pause-when-empty-seconds',
      label: '无人暂停延迟',
      subtitle: '服务器无玩家时多少秒后暂停游戏刻(0 为不暂停)',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('网络设置', Icons.wifi_outlined, [
    _PropDef(
      key: 'server-ip',
      label: '绑定 IP',
      subtitle: '留空表示绑定所有接口',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'server-port',
      label: '服务器端口',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      key: 'online-mode',
      label: '正版验证',
      subtitle: '验证玩家是否通过 Mojang 认证',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'prevent-proxy-connections',
      label: '阻止代理连接',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'network-compression-threshold',
      label: '网络压缩阈值',
      subtitle: '数据包大于此值时进行压缩(-1 为禁用)',
      kind: _PropKind.number,
      min: -1,
    ),
    _PropDef(
      key: 'enable-status',
      label: '启用状态查询',
      subtitle: '允许客户端查询服务器在线状态',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'hide-online-players',
      label: '隐藏在线玩家数',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'enforce-whitelist',
      label: '强制白名单',
      subtitle: '启用后非白名单玩家会被踢出',
      kind: _PropKind.toggle,
    ),
    _PropDef(key: 'white-list', label: '启用白名单', kind: _PropKind.toggle),
  ]),
  _Section('性能设置', Icons.speed_outlined, [
    _PropDef(
      key: 'view-distance',
      label: '视距',
      subtitle: '服务器发送给客户端的区块半径(3-32)',
      kind: _PropKind.number,
      min: 3,
      max: 32,
    ),
    _PropDef(
      key: 'simulation-distance',
      label: '模拟距离',
      subtitle: '实体和方块更新的区块半径',
      kind: _PropKind.number,
      min: 3,
      max: 32,
    ),
    _PropDef(
      key: 'max-tick-time',
      label: '最大 Tick 时间',
      subtitle: '单 tick 超过此毫秒数则看门狗终止服务器(-1 为禁用)',
      kind: _PropKind.number,
      min: -1,
    ),
    _PropDef(
      key: 'max-chained-neighbor-updates',
      label: '最大链式邻居更新',
      kind: _PropKind.number,
    ),
    _PropDef(
      key: 'sync-chunk-writes',
      label: '同步区块写入',
      subtitle: '启用后每次写入都同步到磁盘(影响性能但更安全)',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'use-native-transport',
      label: '使用原生传输',
      subtitle: 'Linux 上使用 epoll 优化网络(仅 Linux 有效)',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'entity-broadcast-range-percentage',
      label: '实体广播范围百分比',
      subtitle: '实体广播距离占视距的百分比(10-1000)',
      kind: _PropKind.number,
      min: 10,
      max: 1000,
    ),
    _PropDef(
      key: 'rate-limit',
      label: '速率限制',
      subtitle: '每秒每个连接最多处理的包数(0 为不限制)',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('Query 与 RCON', Icons.terminal_outlined, [
    _PropDef(
      key: 'enable-query',
      label: '启用 Query',
      subtitle: '启用 GameSpy4 协议查询',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'query.port',
      label: 'Query 端口',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      key: 'enable-rcon',
      label: '启用 RCON',
      subtitle: '远程控制台协议',
      kind: _PropKind.toggle,
    ),
    _PropDef(key: 'rcon.password', label: 'RCON 密码', kind: _PropKind.text),
    _PropDef(
      key: 'rcon.port',
      label: 'RCON 端口',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
  ]),
  _Section('资源包', Icons.inventory_2_outlined, [
    _PropDef(
      key: 'resource-pack',
      label: '资源包 URL',
      subtitle: '资源包下载地址',
      kind: _PropKind.text,
    ),
    _PropDef(key: 'resource-pack-id', label: '资源包 ID', kind: _PropKind.text),
    _PropDef(
      key: 'resource-pack-prompt',
      label: '资源包提示',
      subtitle: '资源包下载对话框中的提示文字',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'resource-pack-sha1',
      label: '资源包 SHA1',
      subtitle: '用于校验资源包完整性的哈希值',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'require-resource-pack',
      label: '强制使用资源包',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'initial-enabled-packs',
      label: '初始启用数据包',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'initial-disabled-packs',
      label: '初始禁用数据包',
      kind: _PropKind.text,
    ),
  ]),
];

// ---------------------------------------------------------------------------
// PocketMine-MP server.properties 属性分组(PMMP 用 on/off、数字难度、大写
// gamemode,独有 xbox-auth / server-portv6 / auto-save / language 等)
// ---------------------------------------------------------------------------

const _pmmpSections = <_Section>[
  _Section('基础设置', Icons.settings_outlined, [
    _PropDef(
      key: 'motd',
      label: '服务器描述 (MOTD)',
      subtitle: '在服务器列表中显示的描述文字',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'max-players',
      label: '最大玩家数',
      kind: _PropKind.number,
      min: 1,
      max: 10000,
    ),
    _PropDef(
      key: 'gamemode',
      label: '默认游戏模式',
      kind: _PropKind.dropdown,
      options: _gamemodeOptionsPmmp,
    ),
    _PropDef(
      key: 'difficulty',
      label: '难度',
      kind: _PropKind.dropdown,
      options: _difficultyOptionsPmmp,
    ),
    _PropDef(key: 'level-name', label: '世界名称', kind: _PropKind.text),
    _PropDef(
      key: 'level-seed',
      label: '世界种子',
      subtitle: '留空则随机生成',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'level-type',
      label: '世界类型',
      kind: _PropKind.dropdown,
      options: _levelTypeOptionsPmmp,
    ),
    _PropDef(
      key: 'generator-settings',
      label: '生成器设置',
      subtitle: '世界生成器的预设参数(一般留空)',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'language',
      label: '服务器语言',
      kind: _PropKind.dropdown,
      options: _languageOptionsPmmp,
    ),
  ]),
  _Section('游戏玩法', Icons.sports_esports_outlined, [
    _PropDef(
      key: 'hardcore',
      label: '极限模式',
      subtitle: '启用后难度锁定为困难,死亡后变为旁观模式',
      kind: _PropKind.toggle,
      boolFormat: BoolFormat.onOff,
    ),
    _PropDef(
      key: 'force-gamemode',
      label: '强制游戏模式',
      subtitle: '玩家每次加入时重置为默认游戏模式',
      kind: _PropKind.toggle,
      boolFormat: BoolFormat.onOff,
    ),
    _PropDef(
      key: 'pvp',
      label: '启用 PvP',
      subtitle: '玩家之间是否允许互相攻击',
      kind: _PropKind.toggle,
      boolFormat: BoolFormat.onOff,
    ),
    _PropDef(
      key: 'auto-save',
      label: '自动保存',
      subtitle: '启用后服务器会定期自动保存世界数据',
      kind: _PropKind.toggle,
      boolFormat: BoolFormat.onOff,
    ),
  ]),
  _Section('网络设置', Icons.wifi_outlined, [
    _PropDef(
      key: 'server-port',
      label: '服务器端口 (IPv4)',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      key: 'server-portv6',
      label: '服务器端口 (IPv6)',
      subtitle: 'IPv6 监听端口',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      key: 'enable-ipv6',
      label: '启用 IPv6',
      kind: _PropKind.toggle,
      boolFormat: BoolFormat.onOff,
    ),
    _PropDef(
      key: 'xbox-auth',
      label: 'Xbox 认证',
      subtitle: '要求玩家通过 Xbox Live 认证(建议启用)',
      kind: _PropKind.toggle,
      boolFormat: BoolFormat.onOff,
    ),
    _PropDef(
      key: 'white-list',
      label: '启用白名单',
      kind: _PropKind.toggle,
      boolFormat: BoolFormat.onOff,
    ),
    _PropDef(
      key: 'enable-query',
      label: '启用 Query',
      subtitle: '启用 GameSpy4 协议查询',
      kind: _PropKind.toggle,
      boolFormat: BoolFormat.onOff,
    ),
  ]),
  _Section('性能设置', Icons.speed_outlined, [
    _PropDef(
      key: 'view-distance',
      label: '视距',
      subtitle: '服务器发送给客户端的区块半径(3-32)',
      kind: _PropKind.number,
      min: 3,
      max: 32,
    ),
  ]),
];

// ---------------------------------------------------------------------------
// PNX pnx.yml 属性分组
// ---------------------------------------------------------------------------

const _pnxSections = <_Section>[
  _Section('基础设置', Icons.settings_outlined, [
    _PropDef(
      key: 'settings.motd',
      label: '服务器描述 (MOTD)',
      subtitle: '在服务器列表中显示的描述文字',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'settings.sub-motd',
      label: '副描述 (Sub-MOTD)',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'settings.port',
      label: '服务器端口',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      key: 'settings.ip',
      label: '绑定 IP',
      subtitle: '留空表示绑定所有接口',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'settings.maxPlayers',
      label: '最大玩家数',
      kind: _PropKind.number,
      min: 1,
      max: 10000,
    ),
    _PropDef(
      key: 'settings.language',
      label: '语言',
      kind: _PropKind.dropdown,
      options: _pnxLanguageOptions,
    ),
    _PropDef(
      key: 'settings.defaultLevelName',
      label: '默认世界名称',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'settings.allowList',
      label: '启用白名单',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'settings.xboxAuth',
      label: 'Xbox 认证',
      subtitle: '验证玩家的 Xbox 账号',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'settings.autoSave',
      label: '自动保存',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'settings.autosaveDelay',
      label: '自动保存周期 (tick)',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('游戏玩法', Icons.sports_esports_outlined, [
    _PropDef(
      key: 'gameplay-settings.gamemode',
      label: '默认游戏模式',
      kind: _PropKind.dropdown,
      options: _pnxGamemodeOptions,
    ),
    _PropDef(
      key: 'gameplay-settings.difficulty',
      label: '难度',
      kind: _PropKind.dropdown,
      options: _pnxDifficultyOptions,
    ),
    _PropDef(
      key: 'gameplay-settings.hardcore',
      label: '极限模式',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'gameplay-settings.pvp',
      label: '启用 PvP',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'gameplay-settings.achievements',
      label: '启用成就',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'gameplay-settings.enableRedstone',
      label: '启用红石',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'gameplay-settings.tickRedstone',
      label: '红石更新',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'gameplay-settings.enableCommandBlocks',
      label: '启用命令方块',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'gameplay-settings.allowNether',
      label: '允许下界',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'gameplay-settings.allowTheEnd',
      label: '允许末地',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'gameplay-settings.forceGamemode',
      label: '强制游戏模式',
      subtitle: '玩家每次加入时重置为默认游戏模式',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'gameplay-settings.spawnProtection',
      label: '出生点保护范围',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'gameplay-settings.viewDistance',
      label: '视距',
      kind: _PropKind.number,
      min: 2,
      max: 64,
    ),
    _PropDef(
      key: 'gameplay-settings.enableMobAi',
      label: '启用生物 AI',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('玩家设置', Icons.person_outlined, [
    _PropDef(
      key: 'player-settings.savePlayerData',
      label: '保存玩家数据',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'player-settings.checkMovement',
      label: '检测移动',
      subtitle: '反作弊:检查玩家移动是否合法',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'player-settings.spawnRadius',
      label: '出生半径',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'player-settings.skinChangeCooldown',
      label: '换肤冷却 (秒)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'player-settings.forceSkinTrusted',
      label: '强制信任皮肤',
      subtitle: '允许玩家自由使用第三方皮肤',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('网络设置', Icons.wifi_outlined, [
    _PropDef(
      key: 'network-settings.compressionLevel',
      label: '压缩等级',
      kind: _PropKind.number,
      min: 0,
      max: 9,
    ),
    _PropDef(
      key: 'network-settings.enableQuery',
      label: '启用 Query',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'network-settings.networkEncryption',
      label: '网络加密',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'network-settings.packetLimit',
      label: '每秒最大包数',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'network-settings.compressionBufferSize',
      label: '压缩缓冲区大小',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('区块设置', Icons.grid_on_outlined, [
    _PropDef(
      key: 'chunk-settings.spawnLimit',
      label: '每区块生物上限',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'chunk-settings.perTickSend',
      label: '每 tick 发送区块数',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      key: 'chunk-settings.chunksPerTicks',
      label: '每 tick 处理区块数',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      key: 'chunk-settings.tickRadius',
      label: 'tick 区块半径',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'chunk-settings.lightUpdates',
      label: '光照更新',
      kind: _PropKind.toggle,
    ),
  ]),
];

// ---------------------------------------------------------------------------
// Allay server-settings.yml 属性分组
// ---------------------------------------------------------------------------

const _allaySections = <_Section>[
  _Section('基础设置', Icons.settings_outlined, [
    _PropDef(
      key: 'generic-settings.motd',
      label: '服务器描述 (MOTD)',
      subtitle: '在服务器列表中显示的描述文字',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'generic-settings.sub-motd',
      label: '副描述 (Sub-MOTD)',
      subtitle: '通常仅在局域网界面可见',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'generic-settings.max-player-count',
      label: '最大玩家数',
      kind: _PropKind.number,
      min: 1,
      max: 10000,
    ),
    _PropDef(
      key: 'generic-settings.default-game-mode',
      label: '默认游戏模式',
      subtitle: '创建世界时的默认游戏模式',
      kind: _PropKind.dropdown,
      options: _allayGamemodeOptions,
    ),
    _PropDef(
      key: 'generic-settings.default-difficulty',
      label: '默认难度',
      subtitle: '创建世界时的默认难度',
      kind: _PropKind.dropdown,
      options: _allayDifficultyOptions,
    ),
    _PropDef(
      key: 'generic-settings.default-permission',
      label: '默认权限',
      kind: _PropKind.dropdown,
      options: _allayPermissionOptions,
    ),
    _PropDef(
      key: 'generic-settings.language',
      label: '控制台语言',
      kind: _PropKind.dropdown,
      options: _allayLanguageOptions,
    ),
    _PropDef(
      key: 'generic-settings.debug',
      label: '调试模式',
      subtitle: '启用后控制台会输出更详细的信息',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'generic-settings.enable-whitelist',
      label: '启用白名单',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'generic-settings.enable-gui',
      label: '启用 GUI',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'generic-settings.max-compute-thread-count',
      label: '计算线程池上限',
      subtitle: '≤0 时与可用处理器数量相同',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'generic-settings.force-enable-sentry',
      label: '强制启用 Sentry',
      subtitle: '错误跟踪与性能监控',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('网络设置', Icons.wifi_outlined, [
    _PropDef(
      key: 'network-settings.ip',
      label: '绑定 IPv4 地址',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'network-settings.port',
      label: 'IPv4 端口',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      key: 'network-settings.enablev6',
      label: '启用 IPv6',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'network-settings.ipv6',
      label: '绑定 IPv6 地址',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'network-settings.portv6',
      label: 'IPv6 端口',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      key: 'network-settings.xbox-auth',
      label: 'Xbox 认证',
      subtitle: '验证玩家的 Xbox 账号',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'network-settings.enable-network-encryption',
      label: '网络加密',
      subtitle: '出于安全原因强烈建议开启',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'network-settings.compression-algorithm',
      label: '压缩算法',
      kind: _PropKind.dropdown,
      options: _allayCompressionOptions,
    ),
    _PropDef(
      key: 'network-settings.network-thread-number',
      label: '网络线程数',
      subtitle: '0 时由服务端自动决定',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'network-settings.raknet-packet-limit',
      label: 'RakNet 包速率限制',
      subtitle: '每个地址每 RakNet tick (10ms) 最大数据报数',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'network-settings.raknet-max-mtu',
      label: 'RakNet 最大 MTU',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'network-settings.max-login-time',
      label: '登录阶段最大时长 (gt)',
      subtitle: '≤0 时禁用',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'network-settings.enable-encoding-protection',
      label: '编码保护',
      subtitle: '防止客户端发送大量垃圾数据',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'network-settings.netease-client-support',
      label: '网易客户端支持',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'network-settings.only-allow-netease-client',
      label: '仅允许网易客户端',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'network-settings.enable-client-chunk-cache',
      label: '客户端区块缓存',
      subtitle: '需关闭编码保护方可生效',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'network-settings.max-chunk-cache-blobs',
      label: '最大区块缓存块数',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('世界设置', Icons.public_outlined, [
    _PropDef(
      key: 'world-settings.tick-radius',
      label: 'Tick 半径',
      subtitle: '区块加载器周围进行 tick 的区块半径',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'world-settings.view-distance',
      label: '视距',
      subtitle: '区块加载器周围加载并发送的区块半径',
      kind: _PropKind.number,
      min: 2,
      max: 64,
    ),
    _PropDef(
      key: 'world-settings.chunk-max-send-count-per-tick',
      label: '每 tick 最大发送区块数',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      key: 'world-settings.use-sub-chunk-sending-system',
      label: '子区块发送系统',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'world-settings.chunk-sending-strategy',
      label: '区块发送策略',
      kind: _PropKind.dropdown,
      options: _allayChunkSendingOptions,
    ),
    _PropDef(
      key: 'world-settings.fully-join-chunk-threshold',
      label: '完全加入区块阈值',
      subtitle: '玩家加入时需发送的最小区块数',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'world-settings.remove-unused-full-chunk-cycle',
      label: '移除无用完整区块周期 (gt)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'world-settings.remove-unused-proto-chunk-cycle',
      label: '移除原型区块周期 (gt)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'world-settings.load-spawn-point-chunks',
      label: '加载出生点区块',
      subtitle: '会增加内存占用但减少加入耗时',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'world-settings.spawn-point-chunk-radius',
      label: '出生点区块半径',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'world-settings.tick-dimension-in-parallel',
      label: '维度并行 Tick',
      subtitle: '同一世界的维度并行 tick',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'world-settings.max-light-update-count',
      label: '最大光照更新数',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('实体设置', Icons.pets_outlined, [
    _PropDef(
      key: 'entity-settings.physics-engine-settings.motion-threshold',
      label: '运动阈值',
      subtitle: '低于该值时运动归零',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'entity-settings.physics-engine-settings.block-collision-motion',
      label: '方块碰撞运动量',
      subtitle: '实体物品卡在方块中时的移动速度',
      kind: _PropKind.text,
    ),
  ]),
  _Section('存储设置', Icons.save_outlined, [
    _PropDef(
      key: 'storage-settings.save-player-data',
      label: '保存玩家数据',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'storage-settings.player-data-auto-save-cycle',
      label: '玩家数据自动保存周期 (gt)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'storage-settings.chunk-auto-save-cycle',
      label: '区块自动保存周期 (gt)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'storage-settings.entity-auto-save-cycle',
      label: '实体自动保存周期 (gt)',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('资源包设置', Icons.inventory_2_outlined, [
    _PropDef(
      key: 'resource-pack-settings.auto-encrypt-packs',
      label: '自动加密资源包',
      subtitle: '启用后会禁用 Vibrant Visuals',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'resource-pack-settings.max-chunk-size',
      label: '资源包分块大小上限 (KB)',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      key: 'resource-pack-settings.force-resource-packs',
      label: '强制资源包',
      subtitle: '玩家必须接受资源包才能进入',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'resource-pack-settings.allow-client-resource-packs',
      label: '允许客户端资源包',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'resource-pack-settings.trust-all-skins',
      label: '信任所有皮肤',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'resource-pack-settings.disable-vibrant-visuals',
      label: '禁用 Vibrant Visuals',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('bStats 设置', Icons.analytics_outlined, [
    _PropDef(
      key: 'bstats-settings.enable',
      label: '启用 bStats',
      subtitle: '匿名统计,建议保持开启',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'bstats-settings.log-failed-requests',
      label: '记录失败请求',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'bstats-settings.log-sent-data',
      label: '记录发送数据',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'bstats-settings.log-response-status-text',
      label: '记录响应状态文本',
      kind: _PropKind.toggle,
    ),
  ]),
];

// ---------------------------------------------------------------------------
// 页面状态
// ---------------------------------------------------------------------------

class _ServerConfigPageState extends ConsumerState<ServerConfigPage> {
  _ConfigKind? _kind;
  List<_Section> _sections = const [];

  _PropsStore? _store;
  String? _configFile;
  String? _instanceId;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// 每个 _PropDef.key 对应的当前值(内存中编辑)。
  final Map<String, String> _values = {};

  /// 被修改过的 key(脏状态判定)。
  final Set<String> _dirtyKeys = {};

  /// 文本输入框控制器(按 key 复用)。
  final Map<String, TextEditingController> _controllers = {};

  /// 当前 server-icon.png 是否存在(决定上传前是否先删除旧文件)。
  bool _hasIcon = false;

  /// 当前 server-icon.png 的字节(预览)。
  Uint8List? _iconBytes;

  /// 图标上传中。
  bool _iconUploading = false;

  bool get _isDirty => _dirtyKeys.isNotEmpty;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当前实例变化时重新检测配置文件类型
    ref.listen(currentInstanceProvider, (previous, next) {
      if (previous?.id != next?.id) _reload();
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reload() async {
    _values.clear();
    _dirtyKeys.clear();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _iconBytes = null;
    _hasIcon = false;
    _store = null;
    _configFile = null;
    _kind = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    await _load();
  }

  /// 核心加载流程:列出实例根目录 → 按优先级检测配置文件 → 读取并解析 → 初始化值。
  Future<void> _load() async {
    final client = _client;
    final instance = ref.read(currentInstanceProvider);
    if (client == null || instance == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '未选中任何实例';
        });
      }
      return;
    }
    try {
      _instanceId = instance.id;
      final pocketmine = instance.type == InstanceType.pocketmine;
      // 列出实例根目录,按优先级检测配置文件:pnx.yml > server-settings.yml > server.properties
      final list = (await client
              .getFilesApi()
              .listFiles(instanceId: instance.id, path: ''))
          .data!;
      final names = list.entries.map((e) => e.name).toSet();

      _ConfigKind kind;
      if (names.contains('pnx.yml')) {
        kind = _ConfigKind.pnx;
      } else if (names.contains('server-settings.yml')) {
        kind = _ConfigKind.allay;
      } else {
        kind = _ConfigKind.vanilla;
      }
      final fileName = switch (kind) {
        _ConfigKind.pnx => 'pnx.yml',
        _ConfigKind.allay => 'server-settings.yml',
        _ConfigKind.vanilla => 'server.properties',
      };
      // vanilla 回退:文件不存在时给出明确提示(对齐 V1 各页 fileNotFound)
      if (kind == _ConfigKind.vanilla && !names.contains('server.properties')) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'server.properties 文件不存在\n请先启动一次服务器以生成配置文件';
          });
        }
        return;
      }

      final bytes = (await client
              .getFilesApi()
              .downloadFile(instanceId: instance.id, path: fileName))
          .data!;
      final content = utf8.decode(bytes);
      final store = _parseStore(kind, content);

      final sections = _sectionsFor(kind, pocketmine);
      // 初始化 _values:从解析结果中读取每个已定义 key 的值。
      for (final section in sections) {
        for (final prop in section.props) {
          final v = store.get(prop.key);
          if (v != null) _values[prop.key] = v;
        }
      }

      final hasIcon = names.contains('server-icon.png');
      if (!mounted) return;
      setState(() {
        _kind = kind;
        _sections = sections;
        _store = store;
        _configFile = fileName;
        _hasIcon = hasIcon;
        _loading = false;
        _error = null;
      });
      if (hasIcon) await _loadIconPreview();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败:${apiErrorMessage(e)}';
        });
      }
    }
  }

  static _PropsStore _parseStore(_ConfigKind kind, String content) {
    return switch (kind) {
      _ConfigKind.pnx => _PnxPropsStore(PnxProperties.parse(content)),
      _ConfigKind.allay => _AllayPropsStore(AllayProperties.parse(content)),
      _ConfigKind.vanilla =>
        _ServerPropsStore(ServerProperties.parse(content)),
    };
  }

  static List<_Section> _sectionsFor(_ConfigKind kind, bool pocketmine) {
    return switch (kind) {
      _ConfigKind.pnx => _pnxSections,
      _ConfigKind.allay => _allaySections,
      _ConfigKind.vanilla => pocketmine ? _pmmpSections : _javaSections,
    };
  }

  String get _title => switch (_kind) {
        _ConfigKind.pnx => 'PowerNukkitX 配置',
        _ConfigKind.allay => 'Allay 配置',
        _ConfigKind.vanilla => '服务器配置',
        null => '服务器配置',
      };

  // —— 保存 ——

  Future<void> _save() async {
    final client = _client;
    final store = _store;
    final file = _configFile;
    final instanceId = _instanceId;
    if (client == null || store == null || file == null || instanceId == null) {
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      for (final key in _dirtyKeys) {
        final v = _values[key];
        if (v != null) store.set(key, v);
      }
      await client.getFilesApi().writeFile(
            fsWriteRequest: FsWriteRequest((b) => b
              ..instanceId = instanceId
              ..path = file
              ..content = store.serialize()),
          );
      _dirtyKeys.clear();
      if (mounted) {
        _snack('已保存');
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        _snack('保存失败:${apiErrorMessage(e)}');
        setState(() => _saving = false);
      }
    }
  }

  // —— 脏值管理 ——

  void _setValue(String key, String value) {
    final original = _store?.get(key);
    setState(() {
      _values[key] = value;
      if (value == original) {
        _dirtyKeys.remove(key);
      } else {
        _dirtyKeys.add(key);
      }
    });
  }

  String _getValue(String key) => _values[key] ?? '';

  /// 读取内存中的当前编辑值并解析为布尔(兼容 true/false 与 on/off)。
  bool _getBool(String key) {
    final v = (_values[key] ?? _store?.get(key))?.toLowerCase();
    return v == 'true' || v == 'on';
  }

  bool _isDirtyKey(String key) => _dirtyKeys.contains(key);

  TextEditingController _controllerFor(String key) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: _getValue(key)),
    );
  }

  // —— 退出确认 ——

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('有未保存的修改,是否放弃?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  // —— 服务器图标 ——

  Future<void> _loadIconPreview() async {
    final client = _client;
    final instanceId = _instanceId;
    if (client == null || instanceId == null) return;
    try {
      final bytes = (await client
              .getFilesApi()
              .downloadFile(instanceId: instanceId, path: 'server-icon.png'))
          .data;
      if (bytes != null && mounted) setState(() => _iconBytes = bytes);
    } catch (_) {
      // 图标读取失败不影响配置编辑
    }
  }

  Future<void> _pickAndCropIcon() async {
    final client = _client;
    final instanceId = _instanceId;
    if (client == null || instanceId == null || _iconUploading) return;
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty || !mounted) return;
    final file = result.single;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      _snack('读取图片失败:${apiErrorMessage(e)}');
      return;
    }
    if (!mounted) return;
    // 跳转到裁剪页面,返回 64×64 PNG 字节
    final png = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => ServerIconCropPage(imageBytes: bytes)),
    );
    if (png == null || !mounted) return;
    await _uploadIcon(client, instanceId, png);
  }

  /// 三段式分片上传 server-icon.png:先删旧文件,再 init → piece → complete。
  Future<void> _uploadIcon(
    EdgecubeApiClient client,
    String instanceId,
    Uint8List png,
  ) async {
    setState(() => _iconUploading = true);
    try {
      if (_hasIcon) {
        await client.getFilesApi().deleteFile(
              fsPathRequest: FsPathRequest((b) => b
                ..instanceId = instanceId
                ..path = 'server-icon.png'),
            );
      }
      final session = (await client.getFilesApi().initFileUpload(
            uploadInitRequest: UploadInitRequest((b) => b
              ..instanceId = instanceId
              ..path = ''
              ..fileName = 'server-icon.png'
              ..sizeBytes = png.length),
          ))
          .data!;
      final uploadId = session.uploadId;
      var offset = session.receivedBytes; // 断点续传:已有部分跳过
      while (offset < png.length) {
        if (!mounted) return;
        final len = _min(png.length - offset, 8 * 1024 * 1024);
        final chunk = Uint8List.sublistView(png, offset, offset + len);
        final prog = (await client.getFilesApi().uploadFilePiece(
              uploadId: uploadId,
              offset: offset,
              body: MultipartFile.fromBytes(
                chunk,
                contentType: DioMediaType('application', 'octet-stream'),
              ),
            ))
            .data!;
        offset = prog.receivedBytes;
      }
      await client.getFilesApi().completeFileUpload(
            uploadCompleteRequest:
                UploadCompleteRequest((b) => b..uploadId = uploadId),
          );
      if (!mounted) return;
      setState(() {
        _hasIcon = true;
        _iconBytes = png;
      });
      _snack('图标已保存');
    } catch (e) {
      if (mounted) _snack('图标上传失败:${apiErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _iconUploading = false);
    }
  }

  static int _min(int a, int b) => a < b ? a : b;

  // —— UI ——

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscard();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_title),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          actions: [
            if (!_loading && _error == null)
              IconButton(
                tooltip: '保存',
                onPressed: _isDirty && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_isDirty ? Icons.save : Icons.save_outlined),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (_kind == _ConfigKind.vanilla) _buildServerIconCard(),
        for (final section in _sections) _buildSection(section),
      ],
    );
  }

  Widget _buildSection(_Section section) {
    final store = _store;
    // 过滤掉文件中不存在的属性(toggle 类型默认展示为 false)。
    final props = section.props.where((p) {
      if (p.kind == _PropKind.toggle) return true;
      return store?.containsKey(p.key) ?? false;
    }).toList();
    if (props.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(section.icon, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    section.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: cs.primary),
                  ),
                ],
              ),
            ),
            for (final prop in props) _buildProp(prop),
          ],
        ),
      ),
    );
  }

  Widget _buildProp(_PropDef prop) {
    switch (prop.kind) {
      case _PropKind.toggle:
        return _buildToggle(prop);
      case _PropKind.number:
        return _buildNumber(prop);
      case _PropKind.text:
        return _buildText(prop);
      case _PropKind.dropdown:
        return _buildDropdown(prop);
    }
  }

  Widget _buildToggle(_PropDef prop) {
    final value = _getBool(prop.key);
    return SwitchListTile(
      title: Text(prop.label),
      subtitle: prop.subtitle != null ? Text(prop.subtitle!) : null,
      value: value,
      onChanged: (v) {
        final str = switch (prop.boolFormat) {
          BoolFormat.trueFalse => v.toString(),
          BoolFormat.onOff => v ? 'on' : 'off',
        };
        _setValue(prop.key, str);
      },
    );
  }

  Widget _buildNumber(_PropDef prop) {
    final controller = _controllerFor(prop.key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
        decoration: _inputDecoration(prop),
        onChanged: (v) => _setValue(prop.key, v),
      ),
    );
  }

  Widget _buildText(_PropDef prop) {
    final controller = _controllerFor(prop.key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: controller,
        decoration: _inputDecoration(prop),
        onChanged: (v) => _setValue(prop.key, v),
      ),
    );
  }

  Widget _buildDropdown(_PropDef prop) {
    final options = prop.options!;
    final currentValue = _getValue(prop.key);
    // 如果当前值不在选项中,保留原值作为额外选项。
    final values = <String>[
      ...options.keys,
      if (!options.containsKey(currentValue) && currentValue.isNotEmpty)
        currentValue,
    ];
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InputDecorator(
        decoration: _inputDecoration(prop),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: currentValue.isEmpty ? null : currentValue,
            hint: const Text('请选择'),
            items: [
              for (final v in values)
                DropdownMenuItem(
                  value: v,
                  child: Text(
                    options[v] ?? v,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) _setValue(prop.key, v);
            },
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(_PropDef prop) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: prop.label,
      helperText: prop.subtitle,
      border: const OutlineInputBorder(),
      isDense: true,
      suffixIcon: _isDirtyKey(prop.key)
          ? Icon(Icons.edit_note, color: cs.primary, size: 20)
          : null,
    );
  }

  Widget _buildServerIconCard() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.image_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    '服务器图标',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: cs.primary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // 图标预览
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: cs.outlineVariant),
                      color: cs.surfaceContainerHighest,
                    ),
                    child: _iconBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(
                              _iconBytes!,
                              filterQuality: FilterQuality.medium,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Icon(
                            Icons.image_not_supported_outlined,
                            size: 32,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'server-icon.png',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '64×64 像素,显示在服务器列表中',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (_iconUploading)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: _pickAndCropIcon,
                      icon: Icon(
                        _iconBytes != null
                            ? Icons.edit_outlined
                            : Icons.add_photo_alternate_outlined,
                        size: 18,
                      ),
                      label: Text(_iconBytes != null ? '更换' : '导入'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
