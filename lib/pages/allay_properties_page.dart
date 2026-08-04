import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../files/file_service.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import '../instance/instance_scope.dart';
import '../server/allay_properties.dart';
import '../widgets/ec_preference.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/miuix_snackbar.dart';
import '../widgets/miuix_dialog.dart';

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
  'SURVIVAL': 'allay.gamemode.survival',
  'CREATIVE': 'allay.gamemode.creative',
  'ADVENTURE': 'allay.gamemode.adventure',
  'SPECTATOR': 'allay.gamemode.spectator',
};

const _difficultyOptions = {
  'PEACEFUL': 'allay.difficulty.peaceful',
  'EASY': 'allay.difficulty.easy',
  'NORMAL': 'allay.difficulty.normal',
  'HARD': 'allay.difficulty.hard',
};

const _permissionOptions = {
  'VISITOR': 'allay.permission.visitor',
  'MEMBER': 'allay.permission.member',
  'OPERATOR': 'allay.permission.operator',
};

const _compressionOptions = {
  'ZLIB': 'allay.compression.zlib',
  'SNAPPY': 'allay.compression.snappy',
};

const _chunkSendingStrategyOptions = {
  'ASYNC': 'allay.chunkSending.async',
  'SYNC': 'allay.chunkSending.sync',
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
  _Section('allay.section.basicSettings', Icons.settings_outlined, [
    _PropDef(
      path: 'generic-settings.motd',
      label: 'allay.genericSettings.motd',
      subtitle: 'allay.genericSettings.motdSubtitle',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'generic-settings.sub-motd',
      label: 'allay.genericSettings.subMotd',
      subtitle: 'allay.genericSettings.subMotdSubtitle',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'generic-settings.max-player-count',
      label: 'allay.genericSettings.maxPlayerCount',
      kind: _PropKind.number,
      min: 1,
      max: 10000,
    ),
    _PropDef(
      path: 'generic-settings.default-game-mode',
      label: 'allay.genericSettings.defaultGameMode',
      subtitle: 'allay.genericSettings.defaultGameModeSubtitle',
      kind: _PropKind.dropdown,
      options: _gamemodeOptions,
    ),
    _PropDef(
      path: 'generic-settings.default-difficulty',
      label: 'allay.genericSettings.defaultDifficulty',
      subtitle: 'allay.genericSettings.defaultDifficultySubtitle',
      kind: _PropKind.dropdown,
      options: _difficultyOptions,
    ),
    _PropDef(
      path: 'generic-settings.default-permission',
      label: 'allay.genericSettings.defaultPermission',
      kind: _PropKind.dropdown,
      options: _permissionOptions,
    ),
    _PropDef(
      path: 'generic-settings.language',
      label: 'allay.genericSettings.language',
      kind: _PropKind.dropdown,
      options: _languageOptions,
    ),
    _PropDef(
      path: 'generic-settings.debug',
      label: 'allay.genericSettings.debug',
      subtitle: 'allay.genericSettings.debugSubtitle',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'generic-settings.enable-whitelist',
      label: 'allay.genericSettings.enableWhitelist',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'generic-settings.enable-gui',
      label: 'allay.genericSettings.enableGui',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'generic-settings.max-compute-thread-count',
      label: 'allay.genericSettings.maxComputeThreadCount',
      subtitle: 'allay.genericSettings.maxComputeThreadCountSubtitle',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'generic-settings.force-enable-sentry',
      label: 'allay.genericSettings.forceEnableSentry',
      subtitle: 'allay.genericSettings.forceEnableSentrySubtitle',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('allay.section.networkSettings', Icons.wifi_outlined, [
    _PropDef(
      path: 'network-settings.ip',
      label: 'allay.networkSettings.ip',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'network-settings.port',
      label: 'allay.networkSettings.port',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      path: 'network-settings.enablev6',
      label: 'allay.networkSettings.enablev6',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.ipv6',
      label: 'allay.networkSettings.ipv6',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'network-settings.portv6',
      label: 'allay.networkSettings.portv6',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      path: 'network-settings.xbox-auth',
      label: 'allay.networkSettings.xboxAuth',
      subtitle: 'allay.networkSettings.xboxAuthSubtitle',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.enable-network-encryption',
      label: 'allay.networkSettings.enableNetworkEncryption',
      subtitle: 'allay.networkSettings.enableNetworkEncryptionSubtitle',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.compression-algorithm',
      label: 'allay.networkSettings.compressionAlgorithm',
      kind: _PropKind.dropdown,
      options: _compressionOptions,
    ),
    _PropDef(
      path: 'network-settings.network-thread-number',
      label: 'allay.networkSettings.networkThreadNumber',
      subtitle: 'allay.networkSettings.networkThreadNumberSubtitle',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'network-settings.raknet-packet-limit',
      label: 'allay.networkSettings.raknetPacketLimit',
      subtitle: 'allay.networkSettings.raknetPacketLimitSubtitle',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'network-settings.raknet-max-mtu',
      label: 'allay.networkSettings.raknetMaxMtu',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'network-settings.max-login-time',
      label: 'allay.networkSettings.maxLoginTime',
      subtitle: 'allay.networkSettings.maxLoginTimeSubtitle',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'network-settings.enable-encoding-protection',
      label: 'allay.networkSettings.enableEncodingProtection',
      subtitle: 'allay.networkSettings.enableEncodingProtectionSubtitle',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.netease-client-support',
      label: 'allay.networkSettings.neteaseClientSupport',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.only-allow-netease-client',
      label: 'allay.networkSettings.onlyAllowNeteaseClient',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.enable-client-chunk-cache',
      label: 'allay.networkSettings.enableClientChunkCache',
      subtitle: 'allay.networkSettings.enableClientChunkCacheSubtitle',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.max-chunk-cache-blobs',
      label: 'allay.networkSettings.maxChunkCacheBlobs',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('allay.section.worldSettings', Icons.public_outlined, [
    _PropDef(
      path: 'world-settings.tick-radius',
      label: 'allay.worldSettings.tickRadius',
      subtitle: 'allay.worldSettings.tickRadiusSubtitle',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'world-settings.view-distance',
      label: 'allay.worldSettings.viewDistance',
      subtitle: 'allay.worldSettings.viewDistanceSubtitle',
      kind: _PropKind.number,
      min: 2,
      max: 64,
    ),
    _PropDef(
      path: 'world-settings.chunk-max-send-count-per-tick',
      label: 'allay.worldSettings.chunkMaxSendCountPerTick',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      path: 'world-settings.use-sub-chunk-sending-system',
      label: 'allay.worldSettings.useSubChunkSendingSystem',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'world-settings.chunk-sending-strategy',
      label: 'allay.worldSettings.chunkSendingStrategy',
      kind: _PropKind.dropdown,
      options: _chunkSendingStrategyOptions,
    ),
    _PropDef(
      path: 'world-settings.fully-join-chunk-threshold',
      label: 'allay.worldSettings.fullyJoinChunkThreshold',
      subtitle: 'allay.worldSettings.fullyJoinChunkThresholdSubtitle',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'world-settings.remove-unused-full-chunk-cycle',
      label: 'allay.worldSettings.removeUnusedFullChunkCycle',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'world-settings.remove-unused-proto-chunk-cycle',
      label: 'allay.worldSettings.removeUnusedProtoChunkCycle',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'world-settings.load-spawn-point-chunks',
      label: 'allay.worldSettings.loadSpawnPointChunks',
      subtitle: 'allay.worldSettings.loadSpawnPointChunksSubtitle',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'world-settings.spawn-point-chunk-radius',
      label: 'allay.worldSettings.spawnPointChunkRadius',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'world-settings.tick-dimension-in-parallel',
      label: 'allay.worldSettings.tickDimensionInParallel',
      subtitle: 'allay.worldSettings.tickDimensionInParallelSubtitle',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'world-settings.max-light-update-count',
      label: 'allay.worldSettings.maxLightUpdateCount',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('allay.section.entitySettings', Icons.pets_outlined, [
    _PropDef(
      path: 'entity-settings.physics-engine-settings.motion-threshold',
      label: 'allay.entitySettings.motionThreshold',
      subtitle: 'allay.entitySettings.motionThresholdSubtitle',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'entity-settings.physics-engine-settings.block-collision-motion',
      label: 'allay.entitySettings.blockCollisionMotion',
      subtitle: 'allay.entitySettings.blockCollisionMotionSubtitle',
      kind: _PropKind.text,
    ),
  ]),
  _Section('allay.section.storageSettings', Icons.save_outlined, [
    _PropDef(
      path: 'storage-settings.save-player-data',
      label: 'allay.storageSettings.savePlayerData',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'storage-settings.player-data-auto-save-cycle',
      label: 'allay.storageSettings.playerDataAutoSaveCycle',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'storage-settings.chunk-auto-save-cycle',
      label: 'allay.storageSettings.chunkAutoSaveCycle',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'storage-settings.entity-auto-save-cycle',
      label: 'allay.storageSettings.entityAutoSaveCycle',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('allay.section.resourcePackSettings', Icons.inventory_2_outlined, [
    _PropDef(
      path: 'resource-pack-settings.auto-encrypt-packs',
      label: 'allay.resourcePackSettings.autoEncryptPacks',
      subtitle: 'allay.resourcePackSettings.autoEncryptPacksSubtitle',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'resource-pack-settings.max-chunk-size',
      label: 'allay.resourcePackSettings.maxChunkSize',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      path: 'resource-pack-settings.force-resource-packs',
      label: 'allay.resourcePackSettings.forceResourcePacks',
      subtitle: 'allay.resourcePackSettings.forceResourcePacksSubtitle',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'resource-pack-settings.allow-client-resource-packs',
      label: 'allay.resourcePackSettings.allowClientResourcePacks',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'resource-pack-settings.trust-all-skins',
      label: 'allay.resourcePackSettings.trustAllSkins',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'resource-pack-settings.disable-vibrant-visuals',
      label: 'allay.resourcePackSettings.disableVibrantVisuals',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('allay.section.bStatsSettings', Icons.analytics_outlined, [
    _PropDef(
      path: 'bstats-settings.enable',
      label: 'allay.bStatsSettings.enable',
      subtitle: 'allay.bStatsSettings.enableSubtitle',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'bstats-settings.log-failed-requests',
      label: 'allay.bStatsSettings.logFailedRequests',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'bstats-settings.log-sent-data',
      label: 'allay.bStatsSettings.logSentData',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'bstats-settings.log-response-status-text',
      label: 'allay.bStatsSettings.logResponseStatusText',
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
        showMiuixSnackbar(context.tr('serverProps.saved'));
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          context.tr('serverProps.saveFailed', {'error': e.toString()}),
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
    final result = await showMiuixDialog<bool>(
      context: context,
      title: context.tr('serverProps.unsavedChanges'),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('serverProps.unsavedChangesMsg')),
          const SizedBox(height: 20),
          MiuixDialogActions(
            children: [
              MiuixTextButton(
                ctx.tr('common.cancel'),
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
              MiuixButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: MiuixText(context.tr('serverProps.discard')),
              ),
            ],
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
      child: MiuixScaffold(
        topBar: MiuixSmallTopAppBar(
          title: context.tr('allayProps.title'),
          navigationIcon: const EcBackButton(),
          actions: [
            if (!_loading && _error == null)
              IconButton(
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: MiuixInfiniteProgressIndicator(size: 20),
                      )
                    : Icon(_isDirty ? Icons.save : Icons.save_outlined),
                tooltip: context.tr('common.save'),
                onPressed: _isDirty && !_saving ? _save : null,
              ),
          ],
        ),
        content: (padding) => Padding(padding: padding, child: _buildBody()),
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
                color: MiuixTheme.of(context).colors.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              MiuixButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: MiuixText(context.tr('common.retry')),
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
      child: MiuixCard(
        insideMargin: const EdgeInsets.only(bottom: 8),
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
                    color: MiuixTheme.of(context).colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr(section.title),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: MiuixTheme.of(context).colors.primary,
                    ),
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
    final value = _getValue(prop.path) == 'true';
    return MiuixSwitchPreference(
      title: context.tr(prop.label),
      value: value,
      onChanged: (v) => _setValue(prop.path, v.toString()),
    );
  }

  Widget _buildNumber(_PropDef prop) {
    final controller = _controllerFor(prop.path);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: EcTextField(
        controller: controller,
        label: context.tr(prop.label),
        helperText: prop.subtitle != null ? context.tr(prop.subtitle!) : null,
        suffixIcon: _isDirtyKey(prop.path)
            ? Icon(
                Icons.edit_note,
                color: MiuixTheme.of(context).colors.primary,
                size: 20,
              )
            : null,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
        onChanged: (v) => _setValue(prop.path, v),
      ),
    );
  }

  Widget _buildText(_PropDef prop) {
    final controller = _controllerFor(prop.path);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: EcTextField(
        controller: controller,
        label: context.tr(prop.label),
        helperText: prop.subtitle != null ? context.tr(prop.subtitle!) : null,
        suffixIcon: _isDirtyKey(prop.path)
            ? Icon(
                Icons.edit_note,
                color: MiuixTheme.of(context).colors.primary,
                size: 20,
              )
            : null,
        onChanged: (v) => _setValue(prop.path, v),
      ),
    );
  }

  Widget _buildDropdown(_PropDef prop) {
    final options = prop.options!;
    final currentValue = _getValue(prop.path);
    // 值与展示文案分离：values 是写回配置的原始值，labels 是给用户看的译文。
    final values = <String>[
      ...options.keys,
      if (!options.containsKey(currentValue) && currentValue.isNotEmpty)
        currentValue,
    ];
    final labels = <String>[
      for (final entry in options.entries) context.tr(entry.value),
      if (!options.containsKey(currentValue) && currentValue.isNotEmpty)
        currentValue,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: EcDropdownField(
        items: labels,
        selectedIndex: values.indexOf(currentValue),
        onSelected: (i) => _setValue(prop.path, values[i]),
        label: context.tr(prop.label),
        helperText: prop.subtitle != null ? context.tr(prop.subtitle!) : null,
        suffixIcon: _isDirtyKey(prop.path)
            ? MiuixIcon(
                icon: Icons.edit_note,
                tint: MiuixTheme.of(context).colors.primary,
                size: 20,
              )
            : null,
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
