import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../files/file_service.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import '../instance/instance_scope.dart';
import '../server/pnx_properties.dart';
import '../widgets/ec_preference.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/miuix_snackbar.dart';
import '../widgets/miuix_dialog.dart';

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
  'chs': 'pnx.language.simplifiedChinese',
  'cht': 'pnx.language.traditionalChinese',
  'eng': 'pnx.language.english',
  'jpn': 'pnx.language.japanese',
  'kor': 'pnx.language.korean',
  'deu': 'pnx.language.german',
  'fra': 'pnx.language.french',
  'rus': 'pnx.language.russian',
  'spa': 'pnx.language.spanish',
};

const _gamemodeOptions = {
  '0': 'pnx.gamemode.survival',
  '1': 'pnx.gamemode.creative',
  '2': 'pnx.gamemode.adventure',
  '3': 'pnx.gamemode.spectator',
};

const _difficultyOptions = {
  '0': 'pnx.difficulty.peaceful',
  '1': 'pnx.difficulty.easy',
  '2': 'pnx.difficulty.normal',
  '3': 'pnx.difficulty.hard',
};

final _sections = <_Section>[
  _Section('pnx.section.basic', Icons.settings_outlined, [
    _PropDef(
      path: 'settings.motd',
      label: 'pnx.label.motd',
      subtitle: 'pnx.subtitle.motd',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'settings.sub-motd',
      label: 'pnx.label.subMotd',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'settings.port',
      label: 'pnx.label.port',
      kind: _PropKind.number,
      min: 1,
      max: 65535,
    ),
    _PropDef(
      path: 'settings.ip',
      label: 'pnx.label.ip',
      subtitle: 'pnx.subtitle.ip',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'settings.maxPlayers',
      label: 'pnx.label.maxPlayers',
      kind: _PropKind.number,
      min: 1,
      max: 10000,
    ),
    _PropDef(
      path: 'settings.language',
      label: 'pnx.label.language',
      kind: _PropKind.dropdown,
      options: _languageOptions,
    ),
    _PropDef(
      path: 'settings.defaultLevelName',
      label: 'pnx.label.defaultLevelName',
      kind: _PropKind.text,
    ),
    _PropDef(
      path: 'settings.allowList',
      label: 'pnx.label.allowList',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'settings.xboxAuth',
      label: 'pnx.label.xboxAuth',
      subtitle: 'pnx.subtitle.xboxAuth',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'settings.autoSave',
      label: 'pnx.label.autoSave',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'settings.autosaveDelay',
      label: 'pnx.label.autosaveDelay',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('pnx.section.gameplay', Icons.sports_esports_outlined, [
    _PropDef(
      path: 'gameplay-settings.gamemode',
      label: 'pnx.label.gamemode',
      kind: _PropKind.dropdown,
      options: _gamemodeOptions,
    ),
    _PropDef(
      path: 'gameplay-settings.difficulty',
      label: 'pnx.label.difficulty',
      kind: _PropKind.dropdown,
      options: _difficultyOptions,
    ),
    _PropDef(
      path: 'gameplay-settings.hardcore',
      label: 'pnx.label.hardcore',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.pvp',
      label: 'pnx.label.pvp',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.achievements',
      label: 'pnx.label.achievements',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.enableRedstone',
      label: 'pnx.label.enableRedstone',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.tickRedstone',
      label: 'pnx.label.tickRedstone',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.enableCommandBlocks',
      label: 'pnx.label.enableCommandBlocks',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.allowNether',
      label: 'pnx.label.allowNether',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.allowTheEnd',
      label: 'pnx.label.allowTheEnd',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.forceGamemode',
      label: 'pnx.label.forceGamemode',
      subtitle: 'pnx.subtitle.forceGamemode',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'gameplay-settings.spawnProtection',
      label: 'pnx.label.spawnProtection',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'gameplay-settings.viewDistance',
      label: 'pnx.label.viewDistance',
      kind: _PropKind.number,
      min: 2,
      max: 64,
    ),
    _PropDef(
      path: 'gameplay-settings.enableMobAi',
      label: 'pnx.label.enableMobAi',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('pnx.section.player', Icons.person_outlined, [
    _PropDef(
      path: 'player-settings.savePlayerData',
      label: 'pnx.label.savePlayerData',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'player-settings.checkMovement',
      label: 'pnx.label.checkMovement',
      subtitle: 'pnx.subtitle.checkMovement',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'player-settings.spawnRadius',
      label: 'pnx.label.spawnRadius',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'player-settings.skinChangeCooldown',
      label: 'pnx.label.skinChangeCooldown',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'player-settings.forceSkinTrusted',
      label: 'pnx.label.forceSkinTrusted',
      subtitle: 'pnx.subtitle.forceSkinTrusted',
      kind: _PropKind.toggle,
    ),
  ]),
  _Section('pnx.section.network', Icons.wifi_outlined, [
    _PropDef(
      path: 'network-settings.compressionLevel',
      label: 'pnx.label.compressionLevel',
      kind: _PropKind.number,
      min: 0,
      max: 9,
    ),
    _PropDef(
      path: 'network-settings.enableQuery',
      label: 'pnx.label.enableQuery',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.networkEncryption',
      label: 'pnx.label.networkEncryption',
      kind: _PropKind.toggle,
    ),
    _PropDef(
      path: 'network-settings.packetLimit',
      label: 'pnx.label.packetLimit',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'network-settings.compressionBufferSize',
      label: 'pnx.label.compressionBufferSize',
      kind: _PropKind.number,
      min: 0,
    ),
  ]),
  _Section('pnx.section.chunk', Icons.grid_on_outlined, [
    _PropDef(
      path: 'chunk-settings.spawnLimit',
      label: 'pnx.label.spawnLimit',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'chunk-settings.perTickSend',
      label: 'pnx.label.perTickSend',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      path: 'chunk-settings.chunksPerTicks',
      label: 'pnx.label.chunksPerTicks',
      kind: _PropKind.number,
      min: 1,
    ),
    _PropDef(
      path: 'chunk-settings.tickRadius',
      label: 'pnx.label.tickRadius',
      kind: _PropKind.number,
      min: 0,
    ),
    _PropDef(
      path: 'chunk-settings.lightUpdates',
      label: 'pnx.label.lightUpdates',
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
        topBar: EcTopAppBar(
          title: context.tr('pnxProps.title'),

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
