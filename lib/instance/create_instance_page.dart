import 'package:flutter/material.dart';

import '../files/storage_permission.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import 'create_download_edition_page.dart';
import 'create_import_archive_page.dart';
import 'create_import_server_page.dart';
import 'create_modpack_page.dart';
import 'download_session.dart';
import 'instance_controller.dart';
import 'instance_scope.dart';
import 'name_entry_step.dart';

/// 新建实例向导结果。
enum CreateInstanceResult { done, cancelled }

/// 新建实例向导根页：输入名称并选择创建方式。
///
/// 名称 + 方式磁贴同处本页；每种创建方式各自 push 独立页面（不再用 setState 在本页
/// 内注入切换步骤）：
/// - 下载服务端 → push 独立的下载流程（选类型 → 分类 → 服务端 → 版本 →
///   加载器版本 → 下载/安装，见 create_download_*.dart）。
/// - 导入服务端 → [ImportServerPage]（选 jar/phar 导入）。
/// - 导入压缩包 → [ImportArchivePage]（选压缩包解压）。
/// - 导入整合包 → [ModpackImportPage]（解析并安装）。
/// - 创建空实例 → 直接创建后完成。
///
/// 各方式页返回 [CreateInstanceResult.done] 时，本页随即关闭向导并回传 done；其创建的
/// 空实例由各自页面在中途退出时清理（见各页 dispose）。
class CreateInstancePage extends StatefulWidget {
  const CreateInstancePage({super.key});

  @override
  State<CreateInstancePage> createState() => _CreateInstancePageState();
}

class _CreateInstancePageState extends State<CreateInstancePage> {
  final _nameController = TextEditingController();

  late InstanceController _instanceController;

  /// 标记 [didChangeDependencies] 中的初始化是否已完成。
  /// [InstanceScope.of] / [context.tr] 依赖 inherited widget，不能在 initState 中调用。
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // 默认名称与 InstanceController 的获取移至 didChangeDependencies：
    // 它们依赖 inherited widget（LocaleScope / InstanceScope），
    // initState 中调用会触发 dependOnInheritedWidgetOfExactType 报错。
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _instanceController = InstanceScope.of(context);
    _nameController.text = context.tr('instance.defaultName');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // —— 名称校验 ——

  /// 校验名称：非空且不重名。空或重复时弹出提示对话框。
  Future<bool> _validateName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      await _showNameEmptyDialog();
      return false;
    }
    if (_instanceController.instances.any((i) => i.name == name)) {
      await _showDuplicateDialog(name);
      return false;
    }
    return _ensureInstanceStoragePermission();
  }

  Future<bool> _ensureInstanceStoragePermission() async {
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.storagePermissionTitle')),
        content: Text(ctx.tr('instance.createStoragePermissionMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('instance.goGrant')),
          ),
        ],
      ),
    );
    if (go != true) return false;
    await StoragePermission.request();
    return false;
  }

  // —— 进入下载服务端流程 ——

  /// 校验名称后进入独立的「下载服务端」流程（push 到「选择类型」页）。
  ///
  /// 该流程的实例创建/清理由各下载页自行负责；完成时通过 [finishDownloadFlow]
  /// 一次性弹回本页并返回 [CreateInstanceResult.done]，此处随即关闭向导。
  Future<void> _goToDownloadFlow() async {
    if (!await _validateName()) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    final session = DownloadSession(
      controller: _instanceController,
      name: _nameController.text.trim(),
    );
    final result = await Navigator.of(context).push<CreateInstanceResult>(
      MaterialPageRoute(
        settings: const RouteSettings(name: kDownloadFlowRootRouteName),
        builder: (_) => SelectEditionPage(session: session),
      ),
    );
    if (result == CreateInstanceResult.done && mounted) {
      _finishWizard();
    }
  }

  // —— 导入服务端（jar/phar）——

  Future<void> _goImportServer() async {
    final id = await _createInstanceForImport();
    if (id == null || !mounted) return;
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push<CreateInstanceResult>(
      MaterialPageRoute(
        builder: (_) => ImportServerPage(
          controller: _instanceController,
          instanceId: id,
        ),
      ),
    );
    if (result == CreateInstanceResult.done && mounted) _finishWizard();
  }

  // —— 导入压缩包 ——

  Future<void> _goImportArchive() async {
    final id = await _createInstanceForImport();
    if (id == null || !mounted) return;
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push<CreateInstanceResult>(
      MaterialPageRoute(
        builder: (_) => ImportArchivePage(
          controller: _instanceController,
          instanceId: id,
        ),
      ),
    );
    if (result == CreateInstanceResult.done && mounted) _finishWizard();
  }

  // —— 导入整合包 ——

  Future<void> _goModpack() async {
    final id = await _createInstanceForImport();
    if (id == null || !mounted) return;
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push<CreateInstanceResult>(
      MaterialPageRoute(
        builder: (_) => ModpackImportPage(
          controller: _instanceController,
          instanceId: id,
        ),
      ),
    );
    if (result == CreateInstanceResult.done && mounted) _finishWizard();
  }

  /// 导入类流程的公共前置：校验名称并创建空实例，返回其 id。
  ///
  /// 校验失败或重名时返回 null（并已弹出对应提示）。创建后若本页已卸载，回收该空实例
  /// 以免残留。实例的后续清理由对应的导入页在中途退出时负责（见各页 dispose）。
  Future<String?> _createInstanceForImport() async {
    if (!await _validateName()) return null;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) {
        _instanceController.deleteInstance(instance.id);
        return null;
      }
      return instance.id;
    } on DuplicateInstanceNameException {
      if (mounted) _showDuplicateDialog(name);
      return null;
    }
  }

  // —— 创建空实例 ——

  /// 创建空实例：不下载/导入任何 jar，直接完成向导。
  Future<void> _createEmptyInstance() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      await _instanceController.createInstance(name);
      _finishWizard();
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  // —— 对话框 ——

  Future<void> _showDuplicateDialog(String name) =>
      showErrorDialog(context, context.tr('instance.duplicateName', {'name': name}));

  Future<void> _showNameEmptyDialog() =>
      showErrorDialog(context, context.tr('instance.nameEmpty'));

  // —— 导航收尾 ——

  void _finishWizard() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(CreateInstanceResult.done);
    }
  }

  // —— UI 构建 ——

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('instance.titleNameEntry'))),
      body: SafeArea(
        child: NameEntryStep(
          controller: _nameController,
          showBungeeCordTile: false,
          onGoToServerType: _goToDownloadFlow,
          onStartImport: _goImportServer,
          onStartArchive: _goImportArchive,
          onStartModpack: _goModpack,
          onCreateBungeeCord: () {},
          onCreateEmpty: _createEmptyInstance,
        ),
      ),
    );
  }
}
