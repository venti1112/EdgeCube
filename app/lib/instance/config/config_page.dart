import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../connection/client.dart';
import '../models.dart' show ServerPhase;
import '../providers.dart'
    show instanceApiProvider, selectedInstanceIdProvider;
import 'api.dart';
import 'draft.dart';
import 'icon_crop_page.dart';
import 'icon_image.dart';
import 'models.dart';
import 'providers.dart';

/// 「服务器配置」页：编辑当前实例的服务端配置文件。
///
/// * 入口只有**通用文案**；进来才问 daemon「这个实例有哪种配置」
/// * 一个通用页：按 daemon 回的 `kind` 选字段表
/// * 解析器合在 `parsers.dart`（两个，合掉了 pnx/allay 的重复）
/// * 字段表在 `sections.dart`（脚本生成）
/// * 配置种类判定走 daemon 的 `instance.config.get`
///
/// **刻意的偏离**：
///
/// * **判断哪种配置在后端**（用户要求）。V2 前端连「实例目录在哪」都不该知道，
///   而依据就是磁盘上的文件。
/// * **服务端图标（`server-icon.png` 预览 / 更换 / 裁剪）没做** —— V2 前端还没有
///   「选本机图片 → 传给 daemon」这条链路，属于独立的一块，这里留白。
/// * **保存后提示重启**（配置要重启才生效），但「立即重启」走
///   `instance.restart`，且只在实例确实在跑时才提示。
class InstanceConfigPage extends ConsumerWidget {
  const InstanceConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(selectedInstanceIdProvider);

    if (id == null) {
      return _Scaffold(child: const _NoticeView(message: '未选中任何实例'));
    }

    final config = ref.watch(instanceConfigProvider(id));
    return config.when(
      loading: () => const _Scaffold(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _Scaffold(
        child: _NoticeView(
          message: _describe(error),
          isError: true,
          onRetry: () => ref.invalidate(instanceConfigProvider(id)),
        ),
      ),
      data: (source) {
        // 一个配置文件都没有：这不是错误，是「服务端还没启动过」。
        // 文案是固定的那两句。
        if (!source.exists) {
          return _Scaffold(
            child: _NoticeView(
              message: '${source.file} 文件不存在\n请先启动一次服务器以生成配置文件',
              onRetry: () => ref.invalidate(instanceConfigProvider(id)),
            ),
          );
        }
        return _ConfigEditor(instanceId: id, source: source);
      },
    );
  }
}

/// 三个状态共用同一个壳（标题 + 透明底，别盖住外壳的毛玻璃）。
class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.child, this.actions});

  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('服务器配置'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: actions,
      ),
      body: child,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 编辑器
// ══════════════════════════════════════════════════════════════════════════

class _ConfigEditor extends ConsumerStatefulWidget {
  const _ConfigEditor({required this.instanceId, required this.source});

  final String instanceId;
  final InstanceConfigSource source;

  @override
  ConsumerState<_ConfigEditor> createState() => _ConfigEditorState();
}

class _ConfigEditorState extends ConsumerState<_ConfigEditor> {
  /// 草稿只建一次（`build` 会跑很多遍，重建草稿等于把用户的输入全扔掉）。
  late final ConfigDraft _draft = widget.source.toDraft()!;

  /// 文本 / 数字输入框的 controller，按 key 复用 —— 每帧重建 controller 会把
  /// 光标顶到行首。
  final Map<String, TextEditingController> _controllers = {};

  bool _saving = false;

  /// 这次进来保存过没有。用来决定退出时要不要提示「要重启才生效」。
  bool _savedOnce = false;

  /// 当前的服务端图标字节；`null` = 还没有图标。与上面的配置**分开**：
  /// 它是另一个文件（`server-icon.png`），也只有 Java 系服务端认它。
  Uint8List? _iconBytes;
  bool _iconBusy = false;

  /// 这个实例认不认 `server-icon.png`。
  ///
  /// 只有 Java 系（`server.properties`）有这东西 —— pnx / allay 是基岩系，
  /// 配置页没有图标卡。所以按 daemon 给的 `kind` 判断，
  /// 不在前端另立一套「哪些服务端支持图标」的表。
  bool get _supportsIcon =>
      _draft.kind == 'java' || _draft.kind == 'pmmp';

  @override
  void initState() {
    super.initState();
    if (_supportsIcon) {
      // 图标是另一个文件，进页面时顺手拉一次（拿不到就留着占位，不打断配置编辑）
      unawaited(_loadIcon());
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(ConfigFieldDef field) {
    return _controllers.putIfAbsent(
      field.key,
      () => TextEditingController(text: _draft.value(field.key)),
    );
  }

  Future<void> _save() async {
    final api = ref.read(instanceConfigApiProvider);
    if (api == null || _saving) return;

    setState(() => _saving = true);
    try {
      await api.save(widget.instanceId, _draft.kind, _draft.serialize());
      _savedOnce = true;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：${_describe(error)}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── 服务端图标 ──

  /// 拉一次图标。失败就留着占位 —— 图标拉不到不该挡住配置编辑。
  Future<void> _loadIcon() async {
    final api = ref.read(instanceConfigApiProvider);
    if (api == null) return;
    try {
      final icon = await api.iconGet(widget.instanceId);
      if (mounted) setState(() => _iconBytes = icon.bytes);
    } catch (_) {
      // 没有图标 / 读不到：两种情况界面上都是那个占位（不弹错）
    }
  }

  /// 选一张本机图片 → 裁剪 → 写回 daemon。
  ///
  /// **图标是立即保存的，与上面那个「保存」按钮无关**：配置的脏状态只
  /// 覆盖 `server.properties` 那份文本，图标是另一个文件、另一个动作。
  /// 揉在一起会让用户以为「图标还没生效」。
  Future<void> _pickAndCropIcon() async {
    if (_iconBusy) return;

    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return;
    final bytes = await picked.single.readAsBytes();
    if (!mounted) return;

    // 先确认能解码再进裁剪页 —— 选到损坏文件时在这里就报错，比让裁剪页
    // 黑屏一下再报错体验好。（尺寸不用管：裁剪页自己会再解一份来算缩放。）
    final decoded = await decodeImage(bytes);
    if (decoded == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法解码这张图片')));
      }
      return;
    }
    decoded.dispose();
    if (!mounted) return;

    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => IconCropPage(imageBytes: bytes),
      ),
    );
    if (cropped == null || !mounted) return;

    setState(() => _iconBusy = true);
    try {
      final api = ref.read(instanceConfigApiProvider);
      if (api == null) {
        throw const DaemonException('unavailable', '还没有连接到守护进程');
      }
      await api.iconSave(widget.instanceId, cropped);
      if (!mounted) return;
      setState(() {
        _iconBytes = cropped;
        _iconBusy = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图标已保存')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _iconBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存图标失败：${_describe(error)}')));
    }
  }

  /// 图标那张卡。
  Widget _buildIconCard() {
    final scheme = Theme.of(context).colorScheme;
    final icon = _iconBytes;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.image_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '服务器图标',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // 预览：64×64，与最终落盘的一致（所见即所得）
                  Container(
                    width: kIconSide.toDouble(),
                    height: kIconSide.toDouble(),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: scheme.outlineVariant),
                      color: scheme.surfaceContainerHighest,
                    ),
                    child: icon == null
                        ? Icon(
                            Icons.image_not_supported_outlined,
                            size: 32,
                            color: scheme.onSurfaceVariant,
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(
                              icon,
                              filterQuality: FilterQuality.medium,
                              fit: BoxFit.contain,
                              // 盘上那份要是坏了（手动塞进去的、写到一半崩了），
                              // 显示占位就行 —— 别把异常抛到界面上
                              errorBuilder: (_, _, _) => Icon(
                                Icons.broken_image_outlined,
                                size: 32,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'server-icon.png',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '64×64 像素，显示在服务器列表中',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('config_icon_pick'),
                    onPressed: _iconBusy ? null : _pickAndCropIcon,
                    icon: _iconBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            icon == null
                                ? Icons.add_photo_alternate_outlined
                                : Icons.edit_outlined,
                            size: 18,
                          ),
                    label: Text(icon == null ? '导入' : '更换'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 退出前要过两关：
  /// 1. 有未保存的改动 → 问「放弃吗」；
  /// 2. 这次改过且实例在跑 → 提示「要重启才生效」，可以顺手重启。
  Future<bool> _confirmLeave() async {
    if (_draft.hasChanges) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('未保存的更改'),
          content: const Text('有未保存的修改，是否放弃？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('放弃'),
            ),
          ],
        ),
      );
      if (discard != true) return false;
    }

    if (_savedOnce && mounted && await _isRunning()) {
      if (!mounted) return true;
      final restartNow = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('需要重启服务器'),
          content: const Text('配置已保存，但需要重启服务器后新设置才能生效。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('稍后重启'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('立即重启'),
            ),
          ],
        ),
      );
      if (restartNow == true) {
        final api = ref.read(instanceApiProvider);
        try {
          await api?.restart(widget.instanceId);
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('重启失败：${_describe(error)}')),
            );
          }
        }
      }
    }
    return true;
  }

  /// 这个实例现在在跑吗（进程起来过、还没停）。
  Future<bool> _isRunning() async {
    final api = ref.read(instanceApiProvider);
    if (api == null) return false;
    try {
      final status = await api.status(widget.instanceId);
      return switch (status.phase) {
        ServerPhase.preparing ||
        ServerPhase.starting ||
        ServerPhase.running ||
        ServerPhase.stopping => true,
        ServerPhase.stopped || ServerPhase.crashed => false,
      };
    } catch (_) {
      // 问不到就别打扰用户 —— 这只是个提示，不是必须成功的动作
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dirty = _draft.hasChanges;

    return PopScope(
      canPop: !dirty && !_savedOnce,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: _Scaffold(
        actions: [
          IconButton(
            tooltip: '保存',
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(dirty ? Icons.save : Icons.save_outlined),
            onPressed: dirty && !_saving ? _save : null,
          ),
        ],
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // 说明「在改哪个文件」—— 入口文案是通用的，具体文件在这里说清楚
            Text(
              '编辑 ${_draft.file}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            // 服务端图标：与那份配置文件**分开**的一块（另一个文件、另一个动作）。
            // 只有 Java 系服务端认它，pnx / allay 不画这张卡。
            if (_supportsIcon) _buildIconCard(),
            for (final section in _draft.sections) ..._buildSection(section),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSection(ConfigSection section) {
    // 文件里没有的字段不显示（开关除外 —— 缺省即关，得让用户能打开）。
    // 一段里一个都没剩下就整段不画。
    final fields = section.fields
        .where(
          (field) =>
              field.kind == ConfigFieldKind.toggle ||
              _draft.present(field.key),
        )
        .toList();
    if (fields.isEmpty) return const [];

    final scheme = Theme.of(context).colorScheme;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Card(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Icon(section.icon, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      section.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              for (final field in fields) _buildField(field),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildField(ConfigFieldDef field) {
    return switch (field.kind) {
      ConfigFieldKind.toggle => _buildToggle(field),
      ConfigFieldKind.dropdown => _buildDropdown(field),
      ConfigFieldKind.number => _buildInput(field, numeric: true),
      ConfigFieldKind.text => _buildInput(field, numeric: false),
    };
  }

  Widget _buildToggle(ConfigFieldDef field) {
    return SwitchListTile(
      key: Key('config_${field.key}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(field.label),
      subtitle: field.subtitle == null ? null : Text(field.subtitle!),
      value: _draft.boolValue(field.key),
      onChanged: (value) => setState(() => _draft.setBool(field.key, value)),
    );
  }

  Widget _buildInput(ConfigFieldDef field, {required bool numeric}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        key: Key('config_${field.key}'),
        controller: _controllerFor(field),
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        inputFormatters: numeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))]
            : null,
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.subtitle,
          border: const OutlineInputBorder(),
          isDense: true,
          // 改过的字段挂个记号，用户一眼扫得出自己动了哪些
          suffixIcon: _draft.dirty(field.key)
              ? Icon(Icons.edit_note, size: 20, color: scheme.primary)
              : null,
        ),
        onChanged: (value) => setState(() => _draft.setValue(field.key, value)),
      ),
    );
  }

  Widget _buildDropdown(ConfigFieldDef field) {
    final scheme = Theme.of(context).colorScheme;
    final options = field.options ?? const <String, String>{};
    final current = _draft.value(field.key);

    // 文件里的值不在选项表里（服务端加过取值、用户手改过）就**把它补进去**，
    // 不能让下拉静默把它改掉。
    final values = <String>[
      ...options.keys,
      if (current.isNotEmpty && !options.containsKey(current)) current,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: DropdownButtonFormField<String>(
        key: Key('config_${field.key}'),
        // 值必须是 items 里的一个，否则 Flutter 断言会拦下
        initialValue: values.contains(current) ? current : null,
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.subtitle,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _draft.dirty(field.key)
              ? Icon(Icons.edit_note, size: 20, color: scheme.primary)
              : null,
        ),
        items: [
          for (final value in values)
            DropdownMenuItem(
              value: value,
              child: Text(options[value] ?? value),
            ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _draft.setValue(field.key, value));
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 小部件
// ══════════════════════════════════════════════════════════════════════════

/// 一句话 + 可选的「重试」。
class _NoticeView extends StatelessWidget {
  const _NoticeView({
    required this.message,
    this.isError = false,
    this.onRetry,
  });

  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.description_outlined,
              size: 48,
              color: isError ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误 → 一句话。`DaemonException` 的 `message` 本来就是给人看的，直接用；
/// 别的错误退回 `toString`。
String _describe(Object error) {
  if (error is DaemonException) return error.message;
  return error.toString();
}
