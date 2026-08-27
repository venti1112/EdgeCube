import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_entry.dart';
import '../server/server_service.dart';

/// 添加服务器页。
///
/// [setupMode] 为 true 时作为首启引导页(`/setup`,无返回按钮,
/// 没有配置且本机无 local.key 时由 redirect 引导至此):
/// 新增本地服务器走本机免密登录,新增远程服务器走用户名密码登录。
class AddServerPage extends ConsumerStatefulWidget {
  const AddServerPage({super.key, this.setupMode = false});

  final bool setupMode;

  @override
  ConsumerState<AddServerPage> createState() => _AddServerPageState();
}

class _AddServerPageState extends ConsumerState<AddServerPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  ServerType _type = ServerType.local;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _hostController.text = '127.0.0.1';
    _portController.text = '${ServerEntry.defaultPort}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_connecting) return;
    if (!_formKey.currentState!.validate()) return;

    final remote = _type == ServerType.remote;
    final entry = ServerEntry(
      id: remote ? ServerEntry.newId() : ServerEntry.localId,
      name: _nameController.text.trim().isEmpty
          ? (remote ? '远程服务器' : '本地服务器')
          : _nameController.text.trim(),
      type: _type,
      host: remote ? _hostController.text.trim() : '127.0.0.1',
      port: int.parse(_portController.text.trim()),
      username: remote ? _usernameController.text.trim() : null,
    );

    setState(() => _connecting = true);
    final toast = ScaffoldMessenger.of(context);
    try {
      // 先连接登录,成功后才保存条目,失败不落库、不跳转
      await ref
          .read(serverServiceProvider)
          .connectTo(entry, password: _passwordController.text.trim());
      await ref.read(serverListProvider.notifier).add(entry);
      await ref.read(currentServerIdProvider.notifier).set(entry.id);
      if (!mounted) return;
      toast.showSnackBar(const SnackBar(content: Text('已添加并连接服务器')));
      context.go('/servers');
    } on ServerException catch (e) {
      if (!mounted) return;
      toast.showSnackBar(SnackBar(content: Text('连接失败:${e.message}')));
      // 连接失败留在本页重试,不保存、不进入应用
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('添加服务器'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: !widget.setupMode,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如:家中主机',
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<ServerType>(
              segments: const [
                ButtonSegment(
                  value: ServerType.local,
                  label: Text('本地'),
                  icon: Icon(Icons.computer),
                ),
                ButtonSegment(
                  value: ServerType.remote,
                  label: Text('远程'),
                  icon: Icon(Icons.dns_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) {
                setState(() {
                  _type = selection.first;
                  // 本地服务器 host 固定本机回环
                  if (_type == ServerType.local) {
                    _hostController.text = '127.0.0.1';
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hostController,
                    enabled: _type == ServerType.remote,
                    validator: _type == ServerType.remote
                        ? (v) =>
                            (v == null || v.trim().isEmpty) ? '请输入服务器地址' : null
                        : null,
                    decoration: InputDecoration(
                      labelText: '服务器地址',
                      hintText: _type == ServerType.local
                          ? '127.0.0.1'
                          : 'IP 或域名',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final port = int.tryParse(v ?? '');
                      if (port == null || port < 1 || port > 65535) {
                        return '端口无效';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(labelText: '端口'),
                  ),
                ),
              ],
            ),
            if (_type == ServerType.remote) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                validator: (v) =>
                    (v == null || v.isEmpty) ? '请输入密码' : null,
                decoration: const InputDecoration(labelText: '密码'),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _connecting ? null : _save,
              icon: _connecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(_connecting ? '连接中…' : '保存并连接'),
            ),
            const SizedBox(height: 8),
            Text(
              '本地服务器将读取本机 daemon 数据目录中的 local.key 免密登录;\n'
              '远程服务器使用用户名密码登录。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}