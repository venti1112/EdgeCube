// 本文件由 scripts/gen-config-sections.py 生成 —— **不要手改**。
//
// 字段表（每个字段叫什么、用什么控件、下拉有哪些选项）留在前端，
// 是因为它不是 daemon 该管的事：daemon 只回答「这个实例有哪种配置」
// （见 `daemon/src/module/builtin/instance/config.rs`），选哪张表在这里。
//
// 文案直接落中文（还没有 i18n）。
// 要改字段表：改脚本重跑，不要直接改这里。

import 'package:material_ui/material_ui.dart';

import 'models.dart';

const _javaSections = <ConfigSection>[
  ConfigSection(
    title: '基础设置',
    icon: Icons.settings_outlined,
    fields: [
      ConfigFieldDef(
        key: 'motd',
        label: '服务器描述 (MOTD)',
        subtitle: '在服务器列表中显示的描述文字',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'max-players',
        label: '最大玩家数',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 10000,
      ),
      ConfigFieldDef(
        key: 'gamemode',
        label: '默认游戏模式',
        kind: ConfigFieldKind.dropdown,
        options: {'survival': '生存模式', 'creative': '创造模式', 'adventure': '冒险模式', 'spectator': '旁观模式'},
      ),
      ConfigFieldDef(
        key: 'difficulty',
        label: '难度',
        kind: ConfigFieldKind.dropdown,
        options: {'peaceful': '和平', 'easy': '简单', 'normal': '普通', 'hard': '困难'},
      ),
      ConfigFieldDef(
        key: 'level-name',
        label: '世界名称',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'level-seed',
        label: '世界种子',
        subtitle: '留空则随机生成',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'level-type',
        label: '世界类型',
        kind: ConfigFieldKind.text,
      ),
    ],
  ),
  ConfigSection(
    title: '游戏玩法',
    icon: Icons.sports_esports_outlined,
    fields: [
      ConfigFieldDef(
        key: 'hardcore',
        label: '极限模式',
        subtitle: '启用后难度锁定为困难，死亡后变为旁观模式',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'allow-flight',
        label: '允许飞行',
        subtitle: '启用后生存模式下也可飞行（反作弊不踢出）',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'force-gamemode',
        label: '强制游戏模式',
        subtitle: '玩家每次加入时重置为默认游戏模式',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'generate-structures',
        label: '生成结构',
        subtitle: '是否生成村庄等自然结构',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'spawn-protection',
        label: '出生点保护范围',
        subtitle: '出生点周围禁止非 OP 操作的方块数（0 为禁用）',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'max-world-size',
        label: '最大世界大小',
        subtitle: '世界边界的最大半径（方块数）',
        kind: ConfigFieldKind.number,
        min: 1,
      ),
      ConfigFieldDef(
        key: 'player-idle-timeout',
        label: '玩家挂机超时',
        subtitle: '挂机多少分钟后踢出（0 为不踢出）',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'function-permission-level',
        label: '函数权限等级',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 4,
      ),
      ConfigFieldDef(
        key: 'op-permission-level',
        label: 'OP 权限等级',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 4,
      ),
      ConfigFieldDef(
        key: 'enforce-secure-profile',
        label: '强制安全档案',
        subtitle: '要求玩家拥有 Mojang 签名的聊天消息',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'enable-command-block',
        label: '启用命令方块',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'pvp',
        label: '启用 PvP',
        subtitle: '玩家之间是否允许互相攻击',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'pause-when-empty-seconds',
        label: '无人暂停延迟',
        subtitle: '服务器无玩家时多少秒后暂停游戏刻（0 为不暂停）',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
    ],
  ),
  ConfigSection(
    title: '网络设置',
    icon: Icons.wifi_outlined,
    fields: [
      ConfigFieldDef(
        key: 'server-ip',
        label: '绑定 IP',
        subtitle: '留空表示绑定所有接口',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'server-port',
        label: '服务器端口',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 65535,
      ),
      ConfigFieldDef(
        key: 'online-mode',
        label: '正版验证',
        subtitle: '验证玩家是否通过 Mojang 认证',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'prevent-proxy-connections',
        label: '阻止代理连接',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'network-compression-threshold',
        label: '网络压缩阈值',
        subtitle: '数据包大于此值时进行压缩（-1 为禁用）',
        kind: ConfigFieldKind.number,
        min: -1,
      ),
      ConfigFieldDef(
        key: 'enable-status',
        label: '启用状态查询',
        subtitle: '允许客户端查询服务器在线状态',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'hide-online-players',
        label: '隐藏在线玩家数',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'enforce-whitelist',
        label: '强制白名单',
        subtitle: '启用后非白名单玩家会被踢出',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'white-list',
        label: '启用白名单',
        kind: ConfigFieldKind.toggle,
      ),
    ],
  ),
  ConfigSection(
    title: '性能设置',
    icon: Icons.speed_outlined,
    fields: [
      ConfigFieldDef(
        key: 'view-distance',
        label: '视距',
        subtitle: '服务器发送给客户端的区块半径（3-32）',
        kind: ConfigFieldKind.number,
        min: 3,
        max: 32,
      ),
      ConfigFieldDef(
        key: 'simulation-distance',
        label: '模拟距离',
        subtitle: '实体和方块更新的区块半径',
        kind: ConfigFieldKind.number,
        min: 3,
        max: 32,
      ),
      ConfigFieldDef(
        key: 'max-tick-time',
        label: '最大 Tick 时间',
        subtitle: '单 tick 超过此毫秒数则看门狗终止服务器（-1 为禁用）',
        kind: ConfigFieldKind.number,
        min: -1,
      ),
      ConfigFieldDef(
        key: 'max-chained-neighbor-updates',
        label: '最大链式邻居更新',
        kind: ConfigFieldKind.number,
      ),
      ConfigFieldDef(
        key: 'sync-chunk-writes',
        label: '同步区块写入',
        subtitle: '启用后每次写入都同步到磁盘（影响性能但更安全）',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'use-native-transport',
        label: '使用原生传输',
        subtitle: 'Linux 上使用 epoll 优化网络（仅 Linux 有效）',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'entity-broadcast-range-percentage',
        label: '实体广播范围百分比',
        subtitle: '实体广播距离占视距的百分比（10-1000）',
        kind: ConfigFieldKind.number,
        min: 10,
        max: 1000,
      ),
      ConfigFieldDef(
        key: 'rate-limit',
        label: '速率限制',
        subtitle: '每秒每个连接最多处理的包数（0 为不限制）',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
    ],
  ),
  ConfigSection(
    title: 'Query 与 RCON',
    icon: Icons.terminal_outlined,
    fields: [
      ConfigFieldDef(
        key: 'enable-query',
        label: '启用 Query',
        subtitle: '启用 GameSpy4 协议查询',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'query.port',
        label: 'Query 端口',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 65535,
      ),
      ConfigFieldDef(
        key: 'enable-rcon',
        label: '启用 RCON',
        subtitle: '远程控制台协议',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'rcon.password',
        label: 'RCON 密码',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'rcon.port',
        label: 'RCON 端口',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 65535,
      ),
    ],
  ),
  ConfigSection(
    title: '资源包',
    icon: Icons.inventory_2_outlined,
    fields: [
      ConfigFieldDef(
        key: 'resource-pack',
        label: '资源包 URL',
        subtitle: '资源包下载地址',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'resource-pack-id',
        label: '资源包 ID',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'resource-pack-prompt',
        label: '资源包提示',
        subtitle: '资源包下载对话框中的提示文字',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'resource-pack-sha1',
        label: '资源包 SHA1',
        subtitle: '用于校验资源包完整性的哈希值',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'require-resource-pack',
        label: '强制使用资源包',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'initial-enabled-packs',
        label: '初始启用数据包',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'initial-disabled-packs',
        label: '初始禁用数据包',
        kind: ConfigFieldKind.text,
      ),
    ],
  ),
];

const _pmmpSections = <ConfigSection>[
  ConfigSection(
    title: '基础设置',
    icon: Icons.settings_outlined,
    fields: [
      ConfigFieldDef(
        key: 'motd',
        label: '服务器描述 (MOTD)',
        subtitle: '在服务器列表中显示的描述文字',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'max-players',
        label: '最大玩家数',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 10000,
      ),
      ConfigFieldDef(
        key: 'gamemode',
        label: '默认游戏模式',
        kind: ConfigFieldKind.dropdown,
        options: {'SURVIVAL': '生存模式', 'CREATIVE': '创造模式', 'ADVENTURE': '冒险模式', 'SPECTATOR': '旁观模式'},
      ),
      ConfigFieldDef(
        key: 'difficulty',
        label: '难度',
        kind: ConfigFieldKind.dropdown,
        options: {'0': '和平', '1': '简单', '2': '普通', '3': '困难'},
      ),
      ConfigFieldDef(
        key: 'level-name',
        label: '世界名称',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'level-seed',
        label: '世界种子',
        subtitle: '留空则随机生成',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'level-type',
        label: '世界类型',
        kind: ConfigFieldKind.dropdown,
        options: {'DEFAULT': '默认', 'FLAT': '超平坦', 'NETHER': '下界', 'VOID': '虚空', 'SKYBLOCK': '空岛'},
      ),
      ConfigFieldDef(
        key: 'generator-settings',
        label: '生成器设置',
        subtitle: '世界生成器的预设参数（一般留空）',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'language',
        label: '服务器语言',
        kind: ConfigFieldKind.dropdown,
        options: {'chs': 'chs', 'cht': 'cht', 'eng': 'eng', 'jpn': 'jpn', 'kor': 'kor', 'deu': 'deu', 'fra': 'fra', 'rus': 'rus', 'spa': 'spa'},
      ),
    ],
  ),
  ConfigSection(
    title: '游戏玩法',
    icon: Icons.sports_esports_outlined,
    fields: [
      ConfigFieldDef(
        key: 'hardcore',
        label: '极限模式',
        subtitle: '启用后难度锁定为困难，死亡后变为旁观模式',
        kind: ConfigFieldKind.toggle,
        boolFormat: BoolFormat.onOff,
      ),
      ConfigFieldDef(
        key: 'force-gamemode',
        label: '强制游戏模式',
        subtitle: '玩家每次加入时重置为默认游戏模式',
        kind: ConfigFieldKind.toggle,
        boolFormat: BoolFormat.onOff,
      ),
      ConfigFieldDef(
        key: 'pvp',
        label: '启用 PvP',
        subtitle: '玩家之间是否允许互相攻击',
        kind: ConfigFieldKind.toggle,
        boolFormat: BoolFormat.onOff,
      ),
      ConfigFieldDef(
        key: 'auto-save',
        label: '自动保存',
        subtitle: '启用后服务器会自动保存世界数据',
        kind: ConfigFieldKind.toggle,
        boolFormat: BoolFormat.onOff,
      ),
    ],
  ),
  ConfigSection(
    title: '网络设置',
    icon: Icons.wifi_outlined,
    fields: [
      ConfigFieldDef(
        key: 'server-port',
        label: '服务器端口',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 65535,
      ),
      ConfigFieldDef(
        key: 'server-portv6',
        label: 'IPv6 端口',
        subtitle: 'IPv6 服务器端口',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 65535,
      ),
      ConfigFieldDef(
        key: 'enable-ipv6',
        label: '启用 IPv6',
        kind: ConfigFieldKind.toggle,
        boolFormat: BoolFormat.onOff,
      ),
      ConfigFieldDef(
        key: 'xbox-auth',
        label: 'Xbox 认证',
        subtitle: '要求玩家通过 Xbox Live 认证（建议启用）',
        kind: ConfigFieldKind.toggle,
        boolFormat: BoolFormat.onOff,
      ),
      ConfigFieldDef(
        key: 'white-list',
        label: '启用白名单',
        kind: ConfigFieldKind.toggle,
        boolFormat: BoolFormat.onOff,
      ),
      ConfigFieldDef(
        key: 'enable-query',
        label: '启用 Query',
        subtitle: '启用 GameSpy4 协议查询',
        kind: ConfigFieldKind.toggle,
        boolFormat: BoolFormat.onOff,
      ),
    ],
  ),
  ConfigSection(
    title: '性能设置',
    icon: Icons.speed_outlined,
    fields: [
      ConfigFieldDef(
        key: 'view-distance',
        label: '视距',
        subtitle: '服务器发送给客户端的区块半径（3-32）',
        kind: ConfigFieldKind.number,
        min: 3,
        max: 32,
      ),
    ],
  ),
];

const _pnxSections = <ConfigSection>[
  ConfigSection(
    title: '基础设置',
    icon: Icons.settings_outlined,
    fields: [
      ConfigFieldDef(
        key: 'settings.motd',
        label: '服务器描述 (MOTD)',
        subtitle: '在服务器列表中显示的描述文字',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'settings.sub-motd',
        label: '副描述 (Sub-MOTD)',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'settings.port',
        label: '服务器端口',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 65535,
      ),
      ConfigFieldDef(
        key: 'settings.ip',
        label: '绑定 IP',
        subtitle: '留空表示绑定所有接口',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'settings.maxPlayers',
        label: '最大玩家数',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 10000,
      ),
      ConfigFieldDef(
        key: 'settings.language',
        label: '语言',
        kind: ConfigFieldKind.dropdown,
        options: {'chs': '简体中文', 'cht': '繁體中文', 'eng': 'English', 'jpn': '日本語', 'kor': '한국어', 'deu': 'Deutsch', 'fra': 'Français', 'rus': 'Русский', 'spa': 'Español'},
      ),
      ConfigFieldDef(
        key: 'settings.defaultLevelName',
        label: '默认世界名称',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'settings.allowList',
        label: '启用白名单',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'settings.xboxAuth',
        label: 'Xbox 认证',
        subtitle: '验证玩家的 Xbox 账号',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'settings.autoSave',
        label: '自动保存',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'settings.autosaveDelay',
        label: '自动保存周期 (tick)',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
    ],
  ),
  ConfigSection(
    title: '游戏玩法',
    icon: Icons.sports_esports_outlined,
    fields: [
      ConfigFieldDef(
        key: 'gameplay-settings.gamemode',
        label: '默认游戏模式',
        kind: ConfigFieldKind.dropdown,
        options: {'0': '生存模式', '1': '创造模式', '2': '冒险模式', '3': '旁观模式'},
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.difficulty',
        label: '难度',
        kind: ConfigFieldKind.dropdown,
        options: {'0': '和平', '1': '简单', '2': '普通', '3': '困难'},
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.hardcore',
        label: '极限模式',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.pvp',
        label: '启用 PvP',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.achievements',
        label: '启用成就',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.enableRedstone',
        label: '启用红石',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.tickRedstone',
        label: '红石更新',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.enableCommandBlocks',
        label: '启用命令方块',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.allowNether',
        label: '允许下界',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.allowTheEnd',
        label: '允许末地',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.forceGamemode',
        label: '强制游戏模式',
        subtitle: '玩家每次加入时重置为默认游戏模式',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.spawnProtection',
        label: '出生点保护范围',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.viewDistance',
        label: '视距',
        kind: ConfigFieldKind.number,
        min: 2,
        max: 64,
      ),
      ConfigFieldDef(
        key: 'gameplay-settings.enableMobAi',
        label: '启用生物 AI',
        kind: ConfigFieldKind.toggle,
      ),
    ],
  ),
  ConfigSection(
    title: '玩家设置',
    icon: Icons.person_outlined,
    fields: [
      ConfigFieldDef(
        key: 'player-settings.savePlayerData',
        label: '保存玩家数据',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'player-settings.checkMovement',
        label: '检测移动',
        subtitle: '反作弊：检查玩家移动是否合法',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'player-settings.spawnRadius',
        label: '出生半径',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'player-settings.skinChangeCooldown',
        label: '换肤冷却 (秒)',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'player-settings.forceSkinTrusted',
        label: '强制信任皮肤',
        subtitle: '允许玩家自由使用第三方皮肤',
        kind: ConfigFieldKind.toggle,
      ),
    ],
  ),
  ConfigSection(
    title: '网络设置',
    icon: Icons.wifi_outlined,
    fields: [
      ConfigFieldDef(
        key: 'network-settings.compressionLevel',
        label: '压缩等级',
        kind: ConfigFieldKind.number,
        min: 0,
        max: 9,
      ),
      ConfigFieldDef(
        key: 'network-settings.enableQuery',
        label: '启用 Query',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'network-settings.networkEncryption',
        label: '网络加密',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'network-settings.packetLimit',
        label: '每秒最大包数',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'network-settings.compressionBufferSize',
        label: '压缩缓冲区大小',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
    ],
  ),
  ConfigSection(
    title: '区块设置',
    icon: Icons.grid_on_outlined,
    fields: [
      ConfigFieldDef(
        key: 'chunk-settings.spawnLimit',
        label: '每区块生物上限',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'chunk-settings.perTickSend',
        label: '每 tick 发送区块数',
        kind: ConfigFieldKind.number,
        min: 1,
      ),
      ConfigFieldDef(
        key: 'chunk-settings.chunksPerTicks',
        label: '每 tick 处理区块数',
        kind: ConfigFieldKind.number,
        min: 1,
      ),
      ConfigFieldDef(
        key: 'chunk-settings.tickRadius',
        label: 'tick 区块半径',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'chunk-settings.lightUpdates',
        label: '光照更新',
        kind: ConfigFieldKind.toggle,
      ),
    ],
  ),
];

const _allaySections = <ConfigSection>[
  ConfigSection(
    title: '基础设置',
    icon: Icons.settings_outlined,
    fields: [
      ConfigFieldDef(
        key: 'generic-settings.motd',
        label: '服务器描述 (MOTD)',
        subtitle: '在服务器列表中显示的描述文字',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'generic-settings.sub-motd',
        label: '副描述 (Sub-MOTD)',
        subtitle: '通常仅在局域网界面可见',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'generic-settings.max-player-count',
        label: '最大玩家数',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 10000,
      ),
      ConfigFieldDef(
        key: 'generic-settings.default-game-mode',
        label: '默认游戏模式',
        subtitle: '创建世界时的默认游戏模式',
        kind: ConfigFieldKind.dropdown,
        options: {'SURVIVAL': '生存', 'CREATIVE': '创造', 'ADVENTURE': '冒险', 'SPECTATOR': '旁观'},
      ),
      ConfigFieldDef(
        key: 'generic-settings.default-difficulty',
        label: '默认难度',
        subtitle: '创建世界时的默认难度',
        kind: ConfigFieldKind.dropdown,
        options: {'PEACEFUL': '和平', 'EASY': '简单', 'NORMAL': '普通', 'HARD': '困难'},
      ),
      ConfigFieldDef(
        key: 'generic-settings.default-permission',
        label: '默认权限',
        kind: ConfigFieldKind.dropdown,
        options: {'VISITOR': '访客', 'MEMBER': '成员', 'OPERATOR': '管理员'},
      ),
      ConfigFieldDef(
        key: 'generic-settings.language',
        label: '控制台语言',
        kind: ConfigFieldKind.dropdown,
        options: {'en_US': 'en_US', 'zh_CN': 'zh_CN', 'ja_JP': 'ja_JP', 'ru_RU': 'ru_RU', 'es_ES': 'es_ES', 'de_DE': 'de_DE', 'fr_FR': 'fr_FR', 'pt_BR': 'pt_BR', 'ko_KR': 'ko_KR'},
      ),
      ConfigFieldDef(
        key: 'generic-settings.debug',
        label: '调试模式',
        subtitle: '启用后控制台会输出更详细的信息',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'generic-settings.enable-whitelist',
        label: '启用白名单',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'generic-settings.enable-gui',
        label: '启用 GUI',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'generic-settings.max-compute-thread-count',
        label: '计算线程池上限',
        subtitle: '≤0 时与可用处理器数量相同',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'generic-settings.force-enable-sentry',
        label: '强制启用 Sentry',
        subtitle: '错误跟踪与性能监控',
        kind: ConfigFieldKind.toggle,
      ),
    ],
  ),
  ConfigSection(
    title: '网络设置',
    icon: Icons.wifi_outlined,
    fields: [
      ConfigFieldDef(
        key: 'network-settings.ip',
        label: '绑定 IPv4 地址',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'network-settings.port',
        label: 'IPv4 端口',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 65535,
      ),
      ConfigFieldDef(
        key: 'network-settings.enablev6',
        label: '启用 IPv6',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'network-settings.ipv6',
        label: '绑定 IPv6 地址',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'network-settings.portv6',
        label: 'IPv6 端口',
        kind: ConfigFieldKind.number,
        min: 1,
        max: 65535,
      ),
      ConfigFieldDef(
        key: 'network-settings.xbox-auth',
        label: 'Xbox 认证',
        subtitle: '验证玩家的 Xbox 账号',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'network-settings.enable-network-encryption',
        label: '网络加密',
        subtitle: '出于安全原因强烈建议开启',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'network-settings.compression-algorithm',
        label: '压缩算法',
        kind: ConfigFieldKind.dropdown,
        options: {'ZLIB': 'ZLIB（高压缩比）', 'SNAPPY': 'SNAPPY（高性能）'},
      ),
      ConfigFieldDef(
        key: 'network-settings.network-thread-number',
        label: '网络线程数',
        subtitle: '0 时由服务端自动决定',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'network-settings.raknet-packet-limit',
        label: 'RakNet 包速率限制',
        subtitle: '每个地址每 RakNet tick (10ms) 最大数据报数',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'network-settings.raknet-max-mtu',
        label: 'RakNet 最大 MTU',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'network-settings.max-login-time',
        label: '登录阶段最大时长 (gt)',
        subtitle: '≤0 时禁用',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'network-settings.enable-encoding-protection',
        label: '编码保护',
        subtitle: '防止客户端发送大量垃圾数据',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'network-settings.netease-client-support',
        label: '网易客户端支持',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'network-settings.only-allow-netease-client',
        label: '仅允许网易客户端',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'network-settings.enable-client-chunk-cache',
        label: '客户端区块缓存',
        subtitle: '需关闭编码保护方可生效',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'network-settings.max-chunk-cache-blobs',
        label: '最大区块缓存块数',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
    ],
  ),
  ConfigSection(
    title: '世界设置',
    icon: Icons.public_outlined,
    fields: [
      ConfigFieldDef(
        key: 'world-settings.tick-radius',
        label: 'Tick 半径',
        subtitle: '区块加载器周围进行 tick 的区块半径',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'world-settings.view-distance',
        label: '视距',
        subtitle: '区块加载器周围加载并发送的区块半径',
        kind: ConfigFieldKind.number,
        min: 2,
        max: 64,
      ),
      ConfigFieldDef(
        key: 'world-settings.chunk-max-send-count-per-tick',
        label: '每 tick 最大发送区块数',
        kind: ConfigFieldKind.number,
        min: 1,
      ),
      ConfigFieldDef(
        key: 'world-settings.use-sub-chunk-sending-system',
        label: '子区块发送系统',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'world-settings.chunk-sending-strategy',
        label: '区块发送策略',
        kind: ConfigFieldKind.dropdown,
        options: {'ASYNC': '异步', 'SYNC': '同步'},
      ),
      ConfigFieldDef(
        key: 'world-settings.fully-join-chunk-threshold',
        label: '完全加入区块阈值',
        subtitle: '玩家加入时需发送的最小区块数',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'world-settings.remove-unused-full-chunk-cycle',
        label: '移除无用完整区块周期 (gt)',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'world-settings.remove-unused-proto-chunk-cycle',
        label: '移除原型区块周期 (gt)',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'world-settings.load-spawn-point-chunks',
        label: '加载出生点区块',
        subtitle: '会增加内存占用但减少加入耗时',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'world-settings.spawn-point-chunk-radius',
        label: '出生点区块半径',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'world-settings.tick-dimension-in-parallel',
        label: '维度并行 Tick',
        subtitle: '同一世界的维度并行 tick',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'world-settings.max-light-update-count',
        label: '最大光照更新数',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
    ],
  ),
  ConfigSection(
    title: '实体设置',
    icon: Icons.pets_outlined,
    fields: [
      ConfigFieldDef(
        key: 'entity-settings.physics-engine-settings.motion-threshold',
        label: '运动阈值',
        subtitle: '低于该值时运动归零',
        kind: ConfigFieldKind.text,
      ),
      ConfigFieldDef(
        key: 'entity-settings.physics-engine-settings.block-collision-motion',
        label: '方块碰撞运动量',
        subtitle: '实体物品卡在方块中时的移动速度',
        kind: ConfigFieldKind.text,
      ),
    ],
  ),
  ConfigSection(
    title: '存储设置',
    icon: Icons.save_outlined,
    fields: [
      ConfigFieldDef(
        key: 'storage-settings.save-player-data',
        label: '保存玩家数据',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'storage-settings.player-data-auto-save-cycle',
        label: '玩家数据自动保存周期 (gt)',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'storage-settings.chunk-auto-save-cycle',
        label: '区块自动保存周期 (gt)',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
      ConfigFieldDef(
        key: 'storage-settings.entity-auto-save-cycle',
        label: '实体自动保存周期 (gt)',
        kind: ConfigFieldKind.number,
        min: 0,
      ),
    ],
  ),
  ConfigSection(
    title: '资源包设置',
    icon: Icons.inventory_2_outlined,
    fields: [
      ConfigFieldDef(
        key: 'resource-pack-settings.auto-encrypt-packs',
        label: '自动加密资源包',
        subtitle: '启用后会禁用 Vibrant Visuals',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'resource-pack-settings.max-chunk-size',
        label: '资源包分块大小上限 (KB)',
        kind: ConfigFieldKind.number,
        min: 1,
      ),
      ConfigFieldDef(
        key: 'resource-pack-settings.force-resource-packs',
        label: '强制资源包',
        subtitle: '玩家必须接受资源包才能进入',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'resource-pack-settings.allow-client-resource-packs',
        label: '允许客户端资源包',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'resource-pack-settings.trust-all-skins',
        label: '信任所有皮肤',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'resource-pack-settings.disable-vibrant-visuals',
        label: '禁用 Vibrant Visuals',
        kind: ConfigFieldKind.toggle,
      ),
    ],
  ),
  ConfigSection(
    title: 'bStats 设置',
    icon: Icons.analytics_outlined,
    fields: [
      ConfigFieldDef(
        key: 'bstats-settings.enable',
        label: '启用 bStats',
        subtitle: '匿名统计，建议保持开启',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'bstats-settings.log-failed-requests',
        label: '记录失败请求',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'bstats-settings.log-sent-data',
        label: '记录发送数据',
        kind: ConfigFieldKind.toggle,
      ),
      ConfigFieldDef(
        key: 'bstats-settings.log-response-status-text',
        label: '记录响应状态文本',
        kind: ConfigFieldKind.toggle,
      ),
    ],
  ),
];

/// 按 daemon 认出来的类型取字段表。
///
/// `kind` 是 `instance.config.get` 回的字符串（`pnx` / `allay` / `java` /
/// `pmmp`）。Java 与 PocketMine 共用 `server.properties`，但字段取值集合
/// （布尔写法、gamemode 的取值）不同，所以是两张表。
List<ConfigSection> sectionsForKind(String kind) => switch (kind) {
  'pnx' => _pnxSections,
  'allay' => _allaySections,
  'pmmp' => _pmmpSections,
  _ => _javaSections,
};

/// 同上，但要的是「所有字段」而不是分组（存盘时按字段遍历）。
Iterable<ConfigFieldDef> fieldsOfKind(String kind) =>
    sectionsForKind(kind).expand((section) => section.fields);
