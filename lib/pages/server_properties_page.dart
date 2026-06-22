import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../files/file_service.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../instance/instance_scope.dart';
import '../server/server_properties.dart';
import 'server_icon_crop_page.dart';

/// server.properties 可视化编辑页面。
///
/// 从当前选中实例的目录读取 server.properties，以分组卡片的形式展示各项配置，
/// 支持修改后保存回文件。
class ServerPropertiesPage extends StatefulWidget {
  const ServerPropertiesPage({super.key});

  @override
  State<ServerPropertiesPage> createState() => _ServerPropertiesPageState();
}

// ---------------------------------------------------------------------------
// 属性元数据定义
// ---------------------------------------------------------------------------

/// 属性编辑器类型。
enum _PropKind { text, number, toggle, dropdown }

/// 单个属性的元数据，驱动 UI 渲染。
class _PropDef {
  const _PropDef({
    required this.key,
    required this.label,
    this.subtitle,
    required this.kind,
    this.options,
    this.min,
    this.max,
  });

  /// server.properties 中的 key。
  final String key;

  /// UI 显示名称。
  final String label;

  /// 辅助说明（可选）。
  final String? subtitle;

  /// 编辑器类型。
  final _PropKind kind;

  /// 下拉选项（kind == dropdown 时使用），格式为 value → 显示文本。
  final Map<String, String>? options;

  /// 数字最小值（kind == number 时使用）。
  final int? min;

  /// 数字最大值（kind == number 时使用）。
  final int? max;
}

/// 属性分组定义。
class _Section {
  const _Section(this.title, this.icon, this.props);

  final String title;
  final IconData icon;
  final List<_PropDef> props;
}

// ---------------------------------------------------------------------------
// 所有属性分组
// ---------------------------------------------------------------------------

const _gamemodeOptions = {
  'survival': '生存模式',
  'creative': '创造模式',
  'adventure': '冒险模式',
  'spectator': '旁观模式',
};

const _difficultyOptions = {
  'peaceful': '和平',
  'easy': '简单',
  'normal': '普通',
  'hard': '困难',
};

const _sections = <_Section>[
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
    _PropDef(
      key: 'level-name',
      label: '世界名称',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'level-seed',
      label: '世界种子',
      subtitle: '留空则随机生成',
      kind: _PropKind.text,
    ),
    _PropDef(
      key: 'level-type',
      label: '世界类型',
      kind: _PropKind.text,
    ),
  ]),
  _Section('游戏玩法', Icons.sports_esports_outlined, [
    _PropDef(
      key: 'hardcore',
      label: '极限模式',
      subtitle: '启用后难度锁定为困难，死亡后变为旁观模式',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'allow-flight',
      label: '允许飞行',
      subtitle: '启用后生存模式下也可飞行（反作弊不踢出）',
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
      subtitle: '出生点周围禁止非 OP 操作的方块数（0 为禁用）',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      key: 'max-world-size',
      label: '最大世界大小',
      subtitle: '世界边界的最大半径（方块数）',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      key: 'player-idle-timeout',
      label: '玩家挂机超时',
      subtitle: '挂机多少分钟后踢出（0 为不踢出）',
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
      subtitle: '服务器无玩家时多少秒后暂停游戏刻（0 为不暂停）',
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
      subtitle: '数据包大于此值时进行压缩（-1 为禁用）',
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
    _PropDef(
      key: 'white-list',
      label: '启用白名单',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('性能设置', Icons.speed_outlined, [
    _PropDef(
      key: 'view-distance',
      label: '视距',
      subtitle: '服务器发送给客户端的区块半径（3-32）',
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
      subtitle: '单 tick 超过此毫秒数则看门狗终止服务器（-1 为禁用）',
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
      subtitle: '启用后每次写入都同步到磁盘（影响性能但更安全）',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'use-native-transport',
      label: '使用原生传输',
      subtitle: 'Linux 上使用 epoll 优化网络（仅 Linux 有效）',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      key: 'entity-broadcast-range-percentage',
      label: '实体广播范围百分比',
      subtitle: '实体广播距离占视距的百分比（10-1000）',
      kind: _PropKind.number,
      min: 10,
      max: 1000,
    ),
    _PropDef(
      key: 'rate-limit',
      label: '速率限制',
      subtitle: '每秒每个连接最多处理的包数（0 为不限制）',
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
    _PropDef(
      key: 'rcon.password',
      label: 'RCON 密码',
      kind: _PropKind.text,
    ),
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
    _PropDef(
      key: 'resource-pack-id',
      label: '资源包 ID',
      kind: _PropKind.text,
    ),
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
// 页面状态
// ---------------------------------------------------------------------------

class _ServerPropertiesPageState extends State<ServerPropertiesPage> {
  final _fileService = const FileService();

  ServerProperties? _props;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// 每个 _PropDef.key 对应的当前值（在内存中编辑）。
  final Map<String, String> _values = {};

  /// 跟踪哪些 key 被修改过（用于脏状态判定）。
  final Set<String> _dirtyKeys = {};

  /// 实例目录路径（加载时缓存）。
  String? _instanceDir;

  /// 当前 server-icon.png 的字节数据（用于预览）。
  Uint8List? _iconBytes;

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
          _error = '未选中任何实例';
        });
        return;
      }
      final dir = await instanceCtrl.directoryFor(instance);
      _instanceDir = dir.path;
      final filePath = p.join(dir.path, 'server.properties');
      final file = File(filePath);
      if (!await file.exists()) {
        setState(() {
          _loading = false;
          _error = 'server.properties 文件不存在\n请先启动一次服务器以生成配置文件';
        });
        return;
      }
      final content = await _fileService.readText(filePath);
      final parsed = ServerProperties.parse(content);
      // 初始化 _values：从解析结果中读取每个已定义 key 的值。
      for (final section in _sections) {
        for (final prop in section.props) {
          final v = parsed[prop.key];
          if (v != null) {
            _values[prop.key] = v;
          }
        }
      }
      setState(() {
        _props = parsed;
        _loading = false;
      });
      // 加载服务器图标预览
      _loadIconPreview(dir.path);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  Future<void> _save() async {
    if (_props == null || _saving) return;
    setState(() => _saving = true);
    try {
      // 将内存中的编辑值写回 _props。
      for (final entry in _dirtyKeys) {
        _props![entry] = _values[entry]!;
      }
      final instanceCtrl = InstanceScope.of(context);
      final instance = instanceCtrl.selected!;
      final dir = await instanceCtrl.directoryFor(instance);
      final filePath = p.join(dir.path, 'server.properties');
      await _fileService.writeText(filePath, _props.toString());
      _dirtyKeys.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存'), duration: Duration(seconds: 2)),
        );
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  // —— 脏值管理 ——

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

  // —— 退出确认 ——

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('有未保存的修改，是否放弃？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // 构建 UI
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
          title: const Text('服务器配置'),
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
                tooltip: '保存',
                onPressed: _isDirty && !_saving ? _save : null,
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
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
        _buildServerIconCard(),
        for (final section in _sections) _buildSection(section),
      ],
    );
  }

  Widget _buildSection(_Section section) {
    // 过滤掉文件中不存在的属性（toggle 类型默认展示为 false）。
    final props = section.props.where((p) {
      if (p.kind == _PropKind.toggle) return true;
      return _props?.containsKey(p.key) ?? false;
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
                    Icon(section.icon, size: 20,
                        color: Theme.of(context).colorScheme.primary),
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

  // —— Toggle ——

  Widget _buildToggle(_PropDef prop) {
    final value = _getValue(prop.key) == 'true';
    return SwitchListTile(
      title: Text(prop.label),
      subtitle: prop.subtitle != null ? Text(prop.subtitle!) : null,
      value: value,
      onChanged: (v) => _setValue(prop.key, v.toString()),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  // —— Number ——

  Widget _buildNumber(_PropDef prop) {
    final controller = _controllerFor(prop.key, prop);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
        ],
        decoration: InputDecoration(
          labelText: prop.label,
          helperText: prop.subtitle,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _isDirtyKey(prop.key)
              ? Icon(Icons.edit_note,
                  color: Theme.of(context).colorScheme.primary, size: 20)
              : null,
        ),
        onChanged: (v) => _setValue(prop.key, v),
      ),
    );
  }

  // —— Text ——

  Widget _buildText(_PropDef prop) {
    final controller = _controllerFor(prop.key, prop);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: prop.label,
          helperText: prop.subtitle,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _isDirtyKey(prop.key)
              ? Icon(Icons.edit_note,
                  color: Theme.of(context).colorScheme.primary, size: 20)
              : null,
        ),
        onChanged: (v) => _setValue(prop.key, v),
      ),
    );
  }

  // —— Dropdown ——

  Widget _buildDropdown(_PropDef prop) {
    final options = prop.options!;
    final currentValue = _getValue(prop.key);
    // 如果当前值不在选项中，保留原值作为额外选项。
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
          if (v != null) _setValue(prop.key, v);
        },
        decoration: InputDecoration(
          labelText: prop.label,
          helperText: prop.subtitle,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _isDirtyKey(prop.key)
              ? Icon(Icons.edit_note,
                  color: Theme.of(context).colorScheme.primary, size: 20)
              : null,
        ),
      ),
    );
  }

  // —— 工具方法 ——

  bool _isDirtyKey(String key) => _dirtyKeys.contains(key);

  /// 为文本输入框创建或复用 TextEditingController，初始值取自 _values。
  final Map<String, TextEditingController> _controllers = {};

  TextEditingController _controllerFor(String key, _PropDef prop) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: _getValue(key)),
    );
  }

  // —— 服务器图标 ——

  /// 确保已获得「管理全部文件」权限；已授权直接返回 true，
  /// 未授权则弹窗引导用户去系统设置开启，与文件导入的体验一致。
  Future<bool> _ensureStoragePermission() async {
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要文件访问权'),
        content: const Text('需要「所有文件访问权限」才能选择图片'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (go == true) {
      await StoragePermission.request();
    }
    return false;
  }

  Future<void> _loadIconPreview(String dirPath) async {
    final iconFile = File(p.join(dirPath, 'server-icon.png'));
    if (await iconFile.exists()) {
      final bytes = await iconFile.readAsBytes();
      if (mounted) setState(() => _iconBytes = bytes);
    }
  }

  Future<void> _pickAndCropIcon() async {
    final dir = _instanceDir;
    if (dir == null) return;
    // 确保存储权限（已授权则跳过）
    if (!await _ensureStoragePermission()) return;
    if (!mounted) return;
    // 从系统选择图片
    final sourcePath = await pickFromSystem(context, mode: SystemPickMode.file);
    if (sourcePath == null) return;
    if (!mounted) return;
    // 跳转到裁剪页面
    final outputPath = p.join(dir, 'server-icon.png');
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ServerIconCropPage(
          imagePath: sourcePath,
          outputPath: outputPath,
        ),
      ),
    );
    if (result == true && mounted) {
      // 重新加载图标预览
      final iconFile = File(outputPath);
      if (await iconFile.exists()) {
        final bytes = await iconFile.readAsBytes();
        if (mounted) {
          setState(() => _iconBytes = bytes);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('图标已保存'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Widget _buildServerIconCard() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.image_outlined,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '服务器图标',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
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
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: _iconBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(
                              _iconBytes!,
                              filterQuality: FilterQuality.none,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Icon(
                            Icons.image_not_supported_outlined,
                            size: 32,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'server-icon.png',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '64×64 像素，显示在服务器列表中',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _pickAndCropIcon,
                    icon: Icon(
                      _iconBytes != null
                          ? Icons.edit_outlined
                          : Icons.add_photo_alternate_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _iconBytes != null ? '更换' : '导入',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
