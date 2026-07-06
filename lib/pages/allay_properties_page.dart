import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../files/file_service.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance_scope.dart';
import '../server/allay_properties.dart';

/// server-settings.yml (Allay) 可视化编辑页面。
///
/// 从当前选中实例的目录读取 server-settings.yml，以分组卡片的形式展示各项配置，
/// 支持修改后保存回文件。
class AllayPropertiesPage extends StatefulWidget {
  const AllayPropertiesPage({super.key});

  @override
  State<AllayPropertiesPage> createState() => _AllayPropertiesPageState();
}

// ---------------------------------------------------------------------------
// 属性元数据定义
// ---------------------------------------------------------------------------

enum _PropKind { text, number, toggle, dropdown }

class _PropDef {
  const _PropDef({
    required this.path,
    required this.label,
    this.subtitle,
    required this.kind,
    this.options,
    this.min,
    this.max,
  });

  /// `a.b.c` 路径。
  final String path;
  final String label;
  final String? subtitle;
  final _PropKind kind;
  final Map<String, String>? options;
  final int? min;
  final int? max;
}

class _Section {
  const _Section(this.title, this.icon, this.props);

  final String title;
  final IconData icon;
  final List<_PropDef> props;
}

// ---------------------------------------------------------------------------
// 枚举选项
// ---------------------------------------------------------------------------

const _gamemodeOptions = {
  'SURVIVAL': '生存',
  'CREATIVE': '创造',
  'ADVENTURE': '冒险',
  'SPECTATOR': '旁观',
};

const _difficultyOptions = {
  'PEACEFUL': '和平',
  'EASY': '简单',
  'NORMAL': '普通',
  'HARD': '困难',
};

const _permissionOptions = {
  'VISITOR': '访客',
  'MEMBER': '成员',
  'OPERATOR': '管理员',
};

const _compressionOptions = {
  'ZLIB': 'ZLIB（高压缩比）',
  'SNAPPY': 'SNAPPY（高性能）',
};

const _chunkSendingStrategyOptions = {
  'ASYNC': '异步',
  'SYNC': '同步',
};

const _languageOptions = {
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
// 属性分组
// ---------------------------------------------------------------------------

final _sections = <_Section>[
  _Section('基础设置', Icons.settings_outlined, [
    _PropDef(
      path: 'generic-settings.motd',
      label: '服务器描述 (MOTD)',
      subtitle: '在服务器列表中显示的描述文字',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'generic-settings.sub-motd',
      label: '副描述 (Sub-MOTD)',
      subtitle: '通常仅在局域网界面可见',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'generic-settings.max-player-count',
      label: '最大玩家数',
      kind: _PropKind.number,
      min: 1,
      max: 10000,
    ),
    _PropDef(
      path: 'generic-settings.default-game-mode',
      label: '默认游戏模式',
      subtitle: '创建世界时的默认游戏模式',
      kind: _PropKind.dropdown,
      options: _gamemodeOptions,
    ),
    _PropDef(
      path: 'generic-settings.default-difficulty',
      label: '默认难度',
      subtitle: '创建世界时的默认难度',
      kind: _PropKind.dropdown,
      options: _difficultyOptions,
    ),
    _PropDef(
      path: 'generic-settings.default-permission',
      label: '默认权限',
      kind: _PropKind.dropdown,
      options: _permissionOptions,
    ),
    _PropDef(
      path: 'generic-settings.language',
      label: '控制台语言',
      kind: _PropKind.dropdown,
      options: _languageOptions,
    ),
    _PropDef(
      path: 'generic-settings.debug',
      label: '调试模式',
      subtitle: '启用后控制台会输出更详细的信息',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'generic-settings.enable-whitelist',
      label: '启用白名单',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'generic-settings.enable-gui',
      label: '启用 GUI',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'generic-settings.max-compute-thread-count',
      label: '计算线程池上限',
      subtitle: '≤0 时与可用处理器数量相同',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'generic-settings.force-enable-sentry',
      label: '强制启用 Sentry',
      subtitle: '错误跟踪与性能监控',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('网络设置', Icons.wifi_outlined, [
    _PropDef(
      path: 'network-settings.ip',
      label: '绑定 IPv4 地址',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'network-settings.port',
      label: 'IPv4 端口',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      path: 'network-settings.enablev6',
      label: '启用 IPv6',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.ipv6',
      label: '绑定 IPv6 地址',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'network-settings.portv6',
      label: 'IPv6 端口',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      path: 'network-settings.xbox-auth',
      label: 'Xbox 认证',
      subtitle: '验证玩家的 Xbox 账号',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.enable-network-encryption',
      label: '网络加密',
      subtitle: '出于安全原因强烈建议开启',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.compression-algorithm',
      label: '压缩算法',
      kind: _PropKind.dropdown,
      options: _compressionOptions,
    ),
    _PropDef(
      path: 'network-settings.network-thread-number',
      label: '网络线程数',
      subtitle: '0 时由服务端自动决定',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'network-settings.raknet-packet-limit',
      label: 'RakNet 包速率限制',
      subtitle: '每个地址每 RakNet tick (10ms) 最大数据报数',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'network-settings.raknet-max-mtu',
      label: 'RakNet 最大 MTU',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'network-settings.max-login-time',
      label: '登录阶段最大时长 (gt)',
      subtitle: '≤0 时禁用',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'network-settings.enable-encoding-protection',
      label: '编码保护',
      subtitle: '防止客户端发送大量垃圾数据',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.netease-client-support',
      label: '网易客户端支持',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.only-allow-netease-client',
      label: '仅允许网易客户端',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.enable-client-chunk-cache',
      label: '客户端区块缓存',
      subtitle: '需关闭编码保护方可生效',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.max-chunk-cache-blobs',
      label: '最大区块缓存块数',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('世界设置', Icons.public_outlined, [
    _PropDef(
      path: 'world-settings.tick-radius',
      label: 'Tick 半径',
      subtitle: '区块加载器周围进行 tick 的区块半径',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'world-settings.view-distance',
      label: '视距',
      subtitle: '区块加载器周围加载并发送的区块半径',
      kind: _PropKind.number,
      min: 2,
      max: 64,
    ),
    _PropDef(
      path: 'world-settings.chunk-max-send-count-per-tick',
      label: '每 tick 最大发送区块数',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      path: 'world-settings.use-sub-chunk-sending-system',
      label: '子区块发送系统',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'world-settings.chunk-sending-strategy',
      label: '区块发送策略',
      kind: _PropKind.dropdown,
      options: _chunkSendingStrategyOptions,
    ),
    _PropDef(
      path: 'world-settings.fully-join-chunk-threshold',
      label: '完全加入区块阈值',
      subtitle: '玩家加入时需发送的最小区块数',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'world-settings.remove-unused-full-chunk-cycle',
      label: '移除无用完整区块周期 (gt)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'world-settings.remove-unused-proto-chunk-cycle',
      label: '移除原型区块周期 (gt)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'world-settings.load-spawn-point-chunks',
      label: '加载出生点区块',
      subtitle: '会增加内存占用但减少加入耗时',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'world-settings.spawn-point-chunk-radius',
      label: '出生点区块半径',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'world-settings.tick-dimension-in-parallel',
      label: '维度并行 Tick',
      subtitle: '同一世界的维度并行 tick',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'world-settings.max-light-update-count',
      label: '最大光照更新数',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('实体设置', Icons.pets_outlined, [
    _PropDef(
      path: 'entity-settings.physics-engine-settings.motion-threshold',
      label: '运动阈值',
      subtitle: '低于该值时运动归零',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'entity-settings.physics-engine-settings.block-collision-motion',
      label: '方块碰撞运动量',
      subtitle: '实体物品卡在方块中时的移动速度',
      kind: _PropKind.text,
    ),
  ]),
  _Section('存储设置', Icons.save_outlined, [
    _PropDef(
      path: 'storage-settings.save-player-data',
      label: '保存玩家数据',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'storage-settings.player-data-auto-save-cycle',
      label: '玩家数据自动保存周期 (gt)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'storage-settings.chunk-auto-save-cycle',
      label: '区块自动保存周期 (gt)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'storage-settings.entity-auto-save-cycle',
      label: '实体自动保存周期 (gt)',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('资源包设置', Icons.inventory_2_outlined, [
    _PropDef(
      path: 'resource-pack-settings.auto-encrypt-packs',
      label: '自动加密资源包',
      subtitle: '启用后会禁用 Vibrant Visuals',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'resource-pack-settings.max-chunk-size',
      label: '资源包分块大小上限 (KB)',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      path: 'resource-pack-settings.force-resource-packs',
      label: '强制资源包',
      subtitle: '玩家必须接受资源包才能进入',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'resource-pack-settings.allow-client-resource-packs',
      label: '允许客户端资源包',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'resource-pack-settings.trust-all-skins',
      label: '信任所有皮肤',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'resource-pack-settings.disable-vibrant-visuals',
      label: '禁用 Vibrant Visuals',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('bStats 设置', Icons.analytics_outlined, [
    _PropDef(
      path: 'bstats-settings.enable',
      label: '启用 bStats',
      subtitle: '匿名统计，建议保持开启',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'bstats-settings.log-failed-requests',
      label: '记录失败请求',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'bstats-settings.log-sent-data',
      label: '记录发送数据',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'bstats-settings.log-response-status-text',
      label: '记录响应状态文本',
      kind: _PropKind.toggle,
    ),
  ]),
];

// ---------------------------------------------------------------------------
// 页面状态
// ---------------------------------------------------------------------------

class _AllayPropertiesPageState extends State<AllayPropertiesPage> {
  static const _fileService = FileService();

  AllayProperties? _props;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final Map<String, String> _values = {};
  final Set<String> _dirtyKeys = {};

  bool get _isDirty => _dirtyKeys.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final instanceCtrl = InstanceScope.of(context);
      final instance = instanceCtrl.selected;
      if (instance == null) {
        setState(() {
          _loading = false;
          _error = context.tr('serverProps.noInstance');
        });
        return;
      }
      final dir = await instanceCtrl.directoryFor(instance);
      final filePath = p.join(dir.path, 'server-settings.yml');
      final file = File(filePath);
      if (!await file.exists()) {
        setState(() {
          _loading = false;
          _error = context.tr('allayProps.fileNotFound');
        });
        return;
      }
      final content = await _fileService.readText(filePath);
      final parsed = AllayProperties.parse(content);
      for (final section in _sections) {
        for (final prop in section.props) {
          final v = parsed[prop.path];
          if (v != null) _values[prop.path] = v;
        }
      }
      setState(() {
        _props = parsed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = context.tr('serverProps.loadFailed', {'error': e.toString()});
      });
    }
  }

  Future<void> _save() async {
    if (_props == null || _saving) return;
    setState(() => _saving = true);
    try {
      for (final key in _dirtyKeys) {
        _props![key] = _values[key]!;
      }
      final instanceCtrl = InstanceScope.of(context);
      final instance = instanceCtrl.selected!;
      final dir = await instanceCtrl.directoryFor(instance);
      final filePath = p.join(dir.path, 'server-settings.yml');
      await _fileService.writeText(filePath, _props.toString());
      _dirtyKeys.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('serverProps.saved')),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('serverProps.saveFailed', {'error': e.toString()}),
            ),
          ),
        );
        setState(() => _saving = false);
      }
    }
  }

  void _setValue(String key, String value) {
    final original = _props?[key];
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

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('serverProps.unsavedChanges')),
        content: Text(context.tr('serverProps.unsavedChangesMsg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('serverProps.discard')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('allayProps.title')),
          actions: [
            if (!_loading && _error == null)
              IconButton(
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_isDirty ? Icons.save : Icons.save_outlined),
                tooltip: context.tr('common.save'),
                onPressed: _isDirty && !_saving ? _save : null,
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: Text(context.tr('common.retry')),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [for (final section in _sections) _buildSection(section)],
    );
  }

  Widget _buildSection(_Section section) {
    final props = section.props.where((prop) {
      if (prop.kind == _PropKind.toggle) return true;
      return _props?.containsKey(prop.path) ?? false;
    }).toList();
    if (props.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      section.icon,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      section.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              for (final prop in props) _buildProp(prop),
            ],
          ),
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
    final value = _getValue(prop.path) == 'true';
    return SwitchListTile(
      title: Text(prop.label),
      subtitle: prop.subtitle != null ? Text(prop.subtitle!) : null,
      value: value,
      onChanged: (v) => _setValue(prop.path, v.toString()),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildNumber(_PropDef prop) {
    final controller = _controllerFor(prop.path);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
        decoration: InputDecoration(
          labelText: prop.label,
          helperText: prop.subtitle,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _isDirtyKey(prop.path)
              ? Icon(
                  Icons.edit_note,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                )
              : null,
        ),
        onChanged: (v) => _setValue(prop.path, v),
      ),
    );
  }

  Widget _buildText(_PropDef prop) {
    final controller = _controllerFor(prop.path);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: prop.label,
          helperText: prop.subtitle,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _isDirtyKey(prop.path)
              ? Icon(
                  Icons.edit_note,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                )
              : null,
        ),
        onChanged: (v) => _setValue(prop.path, v),
      ),
    );
  }

  Widget _buildDropdown(_PropDef prop) {
    final options = prop.options!;
    final currentValue = _getValue(prop.path);
    final items = <DropdownMenuItem<String>>[
      for (final entry in options.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      if (!options.containsKey(currentValue) && currentValue.isNotEmpty)
        DropdownMenuItem(value: currentValue, child: Text(currentValue)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: DropdownButtonFormField<String>(
        initialValue: currentValue.isNotEmpty ? currentValue : null,
        items: items,
        onChanged: (v) {
          if (v != null) _setValue(prop.path, v);
        },
        decoration: InputDecoration(
          labelText: prop.label,
          helperText: prop.subtitle,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _isDirtyKey(prop.path)
              ? Icon(
                  Icons.edit_note,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                )
              : null,
        ),
      ),
    );
  }

  bool _isDirtyKey(String key) => _dirtyKeys.contains(key);

  final Map<String, TextEditingController> _controllers = {};

  TextEditingController _controllerFor(String key) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: _getValue(key)),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
