import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../files/file_service.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance_scope.dart';
import '../server/pnx_properties.dart';

/// pnx.yml (PowerNukkitX) 可视化编辑页面。
///
/// 从当前选中实例的目录读取 pnx.yml，以分组卡片的形式展示各项配置，
/// 支持修改后保存回文件。
class PnxPropertiesPage extends StatefulWidget {
  const PnxPropertiesPage({super.key});

  @override
  State<PnxPropertiesPage> createState() => _PnxPropertiesPageState();
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

  /// `section.key` 路径。
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
// 属性分组
// ---------------------------------------------------------------------------

const _languageOptions = {
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

const _gamemodeOptions = {
  '0': 'survival',
  '1': 'creative',
  '2': 'adventure',
  '3': 'spectator',
};

const _difficultyOptions = {
  '0': 'peaceful',
  '1': 'easy',
  '2': 'normal',
  '3': 'hard',
};

final _sections = <_Section>[
  _Section('基础设置', Icons.settings_outlined, [
    _PropDef(
      path: 'settings.motd',
      label: '服务器描述 (MOTD)',
      subtitle: '在服务器列表中显示的描述文字',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'settings.sub-motd',
      label: '副描述 (Sub-MOTD)',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'settings.port',
      label: '服务器端口',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      path: 'settings.ip',
      label: '绑定 IP',
      subtitle: '留空表示绑定所有接口',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'settings.maxPlayers',
      label: '最大玩家数',
      kind: _PropKind.number,
      min: 1,
      max: 10000,
    ),
    _PropDef(
      path: 'settings.language',
      label: '语言',
      kind: _PropKind.dropdown,
      options: _languageOptions,
    ),
    _PropDef(
      path: 'settings.defaultLevelName',
      label: '默认世界名称',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'settings.allowList',
      label: '启用白名单',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'settings.xboxAuth',
      label: 'Xbox 认证',
      subtitle: '验证玩家的 Xbox 账号',
      kind: _PropKind.toggle,
    ),
    _PropDef(path: 'settings.autoSave', label: '自动保存', kind: _PropKind.toggle),
    _PropDef(
      path: 'settings.autosaveDelay',
      label: '自动保存周期 (tick)',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('游戏玩法', Icons.sports_esports_outlined, [
    _PropDef(
      path: 'gameplay-settings.gamemode',
      label: '默认游戏模式',
      kind: _PropKind.dropdown,
      options: _gamemodeOptions,
    ),
    _PropDef(
      path: 'gameplay-settings.difficulty',
      label: '难度',
      kind: _PropKind.dropdown,
      options: _difficultyOptions,
    ),
    _PropDef(
      path: 'gameplay-settings.hardcore',
      label: '极限模式',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.pvp',
      label: '启用 PvP',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.achievements',
      label: '启用成就',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.enableRedstone',
      label: '启用红石',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.tickRedstone',
      label: '红石更新',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.enableCommandBlocks',
      label: '启用命令方块',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.allowNether',
      label: '允许下界',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.allowTheEnd',
      label: '允许末地',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.forceGamemode',
      label: '强制游戏模式',
      subtitle: '玩家每次加入时重置为默认游戏模式',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.spawnProtection',
      label: '出生点保护范围',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'gameplay-settings.viewDistance',
      label: '视距',
      kind: _PropKind.number,
      min: 2,
      max: 64,
    ),
    _PropDef(
      path: 'gameplay-settings.enableMobAi',
      label: '启用生物 AI',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('玩家设置', Icons.person_outlined, [
    _PropDef(
      path: 'player-settings.savePlayerData',
      label: '保存玩家数据',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'player-settings.checkMovement',
      label: '检测移动',
      subtitle: '反作弊：检查玩家移动是否合法',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'player-settings.spawnRadius',
      label: '出生半径',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'player-settings.skinChangeCooldown',
      label: '换肤冷却 (秒)',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'player-settings.forceSkinTrusted',
      label: '强制信任皮肤',
      subtitle: '允许玩家自由使用第三方皮肤',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('网络设置', Icons.wifi_outlined, [
    _PropDef(
      path: 'network-settings.compressionLevel',
      label: '压缩等级',
      kind: _PropKind.number,
      min: 0,
      max: 9,
    ),
    _PropDef(
      path: 'network-settings.enableQuery',
      label: '启用 Query',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.networkEncryption',
      label: '网络加密',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.packetLimit',
      label: '每秒最大包数',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'network-settings.compressionBufferSize',
      label: '压缩缓冲区大小',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('区块设置', Icons.grid_on_outlined, [
    _PropDef(
      path: 'chunk-settings.spawnLimit',
      label: '每区块生物上限',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'chunk-settings.perTickSend',
      label: '每 tick 发送区块数',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      path: 'chunk-settings.chunksPerTicks',
      label: '每 tick 处理区块数',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      path: 'chunk-settings.tickRadius',
      label: 'tick 区块半径',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'chunk-settings.lightUpdates',
      label: '光照更新',
      kind: _PropKind.toggle,
    ),
  ]),
];

// ---------------------------------------------------------------------------
// 页面状态
// ---------------------------------------------------------------------------

class _PnxPropertiesPageState extends State<PnxPropertiesPage> {
  static const _fileService = FileService();

  PnxProperties? _props;
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
      final filePath = p.join(dir.path, 'pnx.yml');
      final file = File(filePath);
      if (!await file.exists()) {
        setState(() {
          _loading = false;
          _error = context.tr('pnxProps.fileNotFound');
        });
        return;
      }
      final content = await _fileService.readText(filePath);
      final parsed = PnxProperties.parse(content);
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
      final filePath = p.join(dir.path, 'pnx.yml');
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
          title: Text(context.tr('pnxProps.title')),
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
