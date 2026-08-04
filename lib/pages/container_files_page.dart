import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../files/file_browser.dart';
import '../i18n/locale_scope.dart';
import '../server/proot_service.dart';
import '../widgets/ec_preference.dart';

/// 直接管理某个 proot 容器（rootfs）内文件的页面。
///
/// 复用通用的 [FileBrowser]，根目录设为 rootfs 在 Android 文件系统中的绝对路径
/// （[ProotRootfsInfo.dir]，即容器视角的 `/`）。因此浏览、增删改、导入导出、
/// 压缩解压、文本编辑等能力与实例文件管理完全一致。
///
/// 与常驻文件页不同，本页通过 [Navigator] push 打开，故自行用 [PopScope]
/// 处理返回键：先退出多选，其次逐级返回上级目录，最后才关闭页面。
class ContainerFilesPage extends StatelessWidget {
  const ContainerFilesPage({super.key, required this.rootfs});

  final ProotRootfsInfo rootfs;

  @override
  Widget build(BuildContext context) {
    final title = rootfs.envName.isNotEmpty
        ? '${rootfs.envName} (${rootfs.id})'
        : rootfs.id;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 依次：退出搜索 → 退出多选 → 返回上级目录 → 关闭本页。
        if (FileBrowser.isSearching) {
          FileBrowser.exitSearch();
          return;
        }
        if (FileBrowser.isSelecting) {
          FileBrowser.exitSelection();
          return;
        }
        if (FileBrowser.canNavigateUp) {
          FileBrowser.navigateUp();
          return;
        }
        Navigator.of(context).pop();
      },
      child: MiuixScaffold(
        topBar: MiuixSmallTopAppBar(
          title: context.tr('containerFiles.title', {'name': title}),
          navigationIcon: const EcBackButton(),
        ),
        content: (padding) => Padding(
          padding: padding,
          child: FileBrowser(rootDir: Directory(rootfs.dir)),
        ),
      ),
    );
  }
}
