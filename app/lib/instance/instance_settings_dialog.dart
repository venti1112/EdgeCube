import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'models.dart';
import 'providers.dart';

/// 编辑实例元数据的对话框。
///
/// 字段与顺序照 V1 的「实例设置」对话框：名称 → 运行环境 → 运行环境 ID /
/// 内存 → 服务端文件 → JVM 参数 → 兼容模式 → 关服自动重启 → 命令尾换行符。
///
/// 与 V1 的两处差别（都是因为对应的后端能力还没做）：
/// * JRE / rootfs 是**文本框**而不是下拉 —— daemon 还没有「已安装运行环境」列表；
/// * 服务端文件是**文本框**而不是"扫目录出来的下拉" —— 那属于文件模块。
///   等它们落地后换回下拉即可，这里的位置已经留好了。
Future<void> showInstanceSettingsDialog(
  BuildContext context,
  WidgetRef ref,
  Instance instance,
) => showDialog<void>(
  context: context,
  builder: (_) => _InstanceSettingsDialog(instance: instance),
);

class _InstanceSettingsDialog extends ConsumerStatefulWidget {
  const _InstanceSettingsDialog({required this.instance});

  final Instance instance;

  @override
  ConsumerState<_InstanceSettingsDialog> createState() =>
      _InstanceSettingsDialogState();
}

class _InstanceSettingsDialogState
    extends ConsumerState<_InstanceSettingsDialog> {
  late final TextEditingController _name;
  late final TextEditingController _runtimeEnvId;
  late final TextEditingController _memory;
  late final TextEditingController _serverFile;
  late final TextEditingController _jvmArgs;
  late final TextEditingController _prootCommand;
  late String _runtime;
  late bool _compatMode;
  late bool _autoRestart;
  late String _lineEnding;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final instance = widget.instance;
    _name = TextEditingController(text: instance.name);
    _runtimeEnvId = TextEditingController(text: instance.runtimeEnvId ?? '');
    _memory = TextEditingController(text: instance.maxMemory?.toString() ?? '');
    _serverFile = TextEditingController(text: instance.serverFile ?? '');
    _jvmArgs = TextEditingController(text: instance.customJvmArgs ?? '');
    _prootCommand = TextEditingController(
      text: instance.prootStartupCommand ?? '',
    );
    _runtime = instance.runtime;
    _compatMode = instance.compatMode;
    _autoRestart = instance.autoRestartOnExit;
    _lineEnding = instance.lineEnding;
  }

  @override
  void dispose() {
    _name.dispose();
    _runtimeEnvId.dispose();
    _memory.dispose();
    _serverFile.dispose();
    _jvmArgs.dispose();
    _prootCommand.dispose();
    super.dispose();
  }

  /// 收集表单，组装成给 daemon 的补丁。
  ///
  /// **所有字段都发**（空 → `null`）：daemon 的语义是「给哪些改哪些，
  /// 传 null 表示清空」，所以清空输入框能真的清掉字段。
  Map<String, dynamic> _collectPatch() {
    String? optional(TextEditingController controller) {
      final text = controller.text.trim();
      return text.isEmpty ? null : text;
    }

    final memoryText = _memory.text.trim();
    return {
      'name': _name.text.trim(),
      'runtime': _runtime,
      'max_memory': memoryText.isEmpty ? null : int.tryParse(memoryText),
      'runtime_env_id': optional(_runtimeEnvId),
      'server_file': optional(_serverFile),
      'custom_jvm_args': optional(_jvmArgs),
      'compat_mode': _compatMode,
      'auto_restart_on_exit': _autoRestart,
      'line_ending': _lineEnding,
      // 只有 proot 才有启动命令；其它环境不碰这个字段
      if (_runtime == kRuntimeProot)
        'proot_startup_command': optional(_prootCommand),
    };
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      await _error('实例名称不能为空');
      return;
    }
    final memoryText = _memory.text.trim();
    if (memoryText.isNotEmpty && int.tryParse(memoryText) == null) {
      await _error('内存必须是数字（MB）');
      return;
    }

    final api = ref.read(instanceApiProvider);
    if (api == null) return;
    setState(() => _saving = true);
    try {
      await api.update(widget.instance.id, _collectPatch());
      ref.invalidate(instanceListProvider);
      ref.invalidate(selectedInstanceDetailProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await _error(describeInstanceError(e));
    }
  }

  Future<void> _error(String message) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('保存失败'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isJava = _runtime == kRuntimeJava;
    final isProot = _runtime == kRuntimeProot;

    return AlertDialog(
      title: const Text('实例设置'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('settings_instance_name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '实例名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // 运行环境
              DropdownButtonFormField<String>(
                key: const Key('settings_instance_runtime'),
                initialValue: _runtime,
                decoration: const InputDecoration(
                  labelText: '运行环境',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final runtime in kRuntimes)
                    DropdownMenuItem(
                      value: runtime,
                      child: Text(runtimeLabel(runtime)),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _runtime = value);
                      },
              ),
              const SizedBox(height: 16),

              // 运行环境相关的字段（Java 有 JRE 与内存；PHP 只有版本；
              // proot 是 rootfs + 启动命令）
              if (isProot) ...[
                TextField(
                  key: const Key('settings_instance_runtime_env'),
                  controller: _runtimeEnvId,
                  decoration: const InputDecoration(
                    labelText: 'rootfs ID',
                    hintText: '选择在哪个 Linux rootfs 内运行',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('settings_instance_proot_command'),
                  controller: _prootCommand,
                  maxLines: 4,
                  minLines: 2,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: '启动命令',
                    hintText: '/usr/bin/python3 /mnt/server/main.py',
                    helperText: '纯容器 rootfs 需要填写完整启动命令',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ] else if (isJava) ...[
                TextField(
                  key: const Key('settings_instance_runtime_env'),
                  controller: _runtimeEnvId,
                  decoration: const InputDecoration(
                    labelText: 'JRE 版本',
                    hintText: '例如 jre21',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('settings_instance_memory'),
                  controller: _memory,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '最大内存',
                    suffixText: 'MB',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ] else
                TextField(
                  key: const Key('settings_instance_runtime_env'),
                  controller: _runtimeEnvId,
                  decoration: const InputDecoration(
                    labelText: '运行环境版本',
                    hintText: '例如 php82',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              const SizedBox(height: 16),

              if (!isProot)
                TextField(
                  key: const Key('settings_instance_server_file'),
                  controller: _serverFile,
                  decoration: InputDecoration(
                    labelText: isJava ? '服务端 jar' : '服务端 phar',
                    hintText: isJava ? '例如 server.jar' : '例如 PocketMine.phar',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              const SizedBox(height: 16),

              if (isJava) ...[
                TextField(
                  key: const Key('settings_instance_jvm_args'),
                  controller: _jvmArgs,
                  maxLines: 4,
                  minLines: 2,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: '自定义 JVM 参数',
                    hintText: '-XX:+UseZGC',
                    helperText: '以空白分隔，原样追加在内置参数之后',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              SwitchListTile(
                key: const Key('settings_instance_compat'),
                contentPadding: EdgeInsets.zero,
                title: const Text('兼容模式'),
                subtitle: const Text('服务端不输出 Done 标志时，进程起来就视为运行中'),
                value: _compatMode,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _compatMode = value),
              ),
              SwitchListTile(
                key: const Key('settings_instance_autorestart'),
                contentPadding: EdgeInsets.zero,
                title: const Text('关服自动重启'),
                subtitle: const Text('服务端正常退出时自动用相同参数重新拉起'),
                value: _autoRestart,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _autoRestart = value),
              ),
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                key: const Key('settings_instance_line_ending'),
                initialValue: _lineEnding,
                decoration: const InputDecoration(
                  labelText: '命令尾换行符',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: kLineEndingLf, child: Text('Linux（\\n）')),
                  DropdownMenuItem(
                    value: kLineEndingCrlf,
                    child: Text('Windows（\\r\\n）'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _lineEnding = value);
                      },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('settings_instance_save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}
