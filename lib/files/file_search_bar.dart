import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';
import '../widgets/ec_text_field.dart';

/// 文件/目录搜索栏，供文件管理器、文件选择器、文件夹选择器共用。
///
/// 单行布局：关闭按钮 + 搜索输入框 + 「包含子目录」开关。开关默认关闭
/// （仅搜索当前目录直接子项），由调用方通过 [recursive] 传入当前值、
/// [onRecursiveChanged] 接收变更。输入内容由 [controller] 托管，实时搜索由
/// 调用方监听 [controller] 实现；[onClose] 用于退出搜索。
class FileSearchBar extends StatelessWidget {
  const FileSearchBar({
    super.key,
    required this.controller,
    required this.recursive,
    required this.onRecursiveChanged,
    required this.onClose,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final bool recursive;
  final ValueChanged<bool> onRecursiveChanged;
  final VoidCallback onClose;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          MiuixIconButton(
            onPressed: onClose,
            child: MiuixIcon(icon: Icons.arrow_back),
          ),
          Expanded(
            child: EcTextField(
              controller: controller,
              hint: context.tr('fileSearch.hint'),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : MiuixIconButton(
                        onPressed: () => controller.clear(),
                        child: MiuixIcon(icon: Icons.clear, size: 18),
                      ),
              ),
              autofocus: autofocus,
              textInputAction: TextInputAction.search,
            ),
          ),
          // 选中态原先靠 IconButton.isSelected 表达；Miuix 无此参数，
          // 改用图标本身的实心/描边切换 + 主色着色来体现。
          MiuixIconButton(
            onPressed: () => onRecursiveChanged(!recursive),
            child: MiuixIcon(
              icon: recursive
                  ? Icons.account_tree
                  : Icons.account_tree_outlined,
              tint: recursive ? theme.colors.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
