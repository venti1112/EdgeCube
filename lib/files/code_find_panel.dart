import 'dart:math';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../i18n/locale_scope.dart';

/// re_editor 不自带查找/替换 UI，此组件根据官方 example 适配。
///
/// 通过 [CodeEditor.findBuilder] 注入，在编辑器顶部右侧弹出。
class CodeFindPanelView extends StatelessWidget implements PreferredSizeWidget {
  const CodeFindPanelView({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  final CodeFindController controller;
  final bool readOnly;

  static const _kMargin = EdgeInsets.only(right: 10);
  static const _kPanelWidth = 360.0;
  static const _kPanelHeight = 36.0;
  static const _kIconSize = 16.0;
  static const _kIconWidth = 30.0;
  static const _kIconHeight = 30.0;
  static const _kInputFontSize = 13.0;
  static const _kResultFontSize = 12.0;
  static const _kPadding = EdgeInsets.only(
    left: 5,
    right: 5,
    top: 2.5,
    bottom: 2.5,
  );
  static const _kInputContentPadding = EdgeInsets.only(left: 5, right: 5);

  @override
  Size get preferredSize {
    if (controller.value == null) return Size.zero;
    final height = controller.value!.replaceMode
        ? _kPanelHeight * 2
        : _kPanelHeight;
    return Size(double.infinity, height + _kMargin.vertical);
  }

  @override
  Widget build(BuildContext context) {
    if (controller.value == null) return const SizedBox.shrink();
    return Container(
      margin: _kMargin,
      alignment: Alignment.topRight,
      height: preferredSize.height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _kPanelWidth,
          child: Column(
            children: [
              _buildFindRow(context),
              if (controller.value!.replaceMode) _buildReplaceRow(context),
            ],
          ),
        ),
      ),
    );
  }

  // ── Find 行 ──────────────────────────────────────────────

  Widget _buildFindRow(BuildContext context) {
    final value = controller.value!;
    final result = value.result == null
        ? '-'
        : '${value.result!.index + 1}/${value.result!.matches.length}';

    return Row(
      children: [
        SizedBox(
          width: _kPanelWidth / 1.75,
          height: _kPanelHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _buildTextField(
                controller: controller.findInputController,
                focusNode: controller.findInputFocusNode,
                iconsWidth: _kIconWidth * 1.5,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildCheckText(
                    context: context,
                    text: 'Aa',
                    checked: value.option.caseSensitive,
                    onPressed: controller.toggleCaseSensitive,
                  ),
                  _buildCheckText(
                    context: context,
                    text: '.*',
                    checked: value.option.regex,
                    onPressed: controller.toggleRegex,
                  ),
                ],
              ),
            ],
          ),
        ),
        Text(result, style: const TextStyle(fontSize: _kResultFontSize)),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildIconButton(
                icon: Icons.arrow_upward,
                tooltip: context.tr('textEditor.previousMatch'),
                onPressed: value.result == null
                    ? null
                    : controller.previousMatch,
              ),
              _buildIconButton(
                icon: Icons.arrow_downward,
                tooltip: context.tr('textEditor.nextMatch'),
                onPressed: value.result == null ? null : controller.nextMatch,
              ),
              _buildIconButton(
                icon: value.replaceMode ? Icons.find_replace : Icons.swap_vert,
                tooltip: value.replaceMode
                    ? context.tr('textEditor.find')
                    : context.tr('textEditor.replace'),
                onPressed: controller.toggleMode,
              ),
              _buildIconButton(
                icon: Icons.close,
                tooltip: context.tr('common.close'),
                onPressed: controller.close,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Replace 行 ───────────────────────────────────────────

  Widget _buildReplaceRow(BuildContext context) {
    final value = controller.value!;
    return Row(
      children: [
        SizedBox(
          width: _kPanelWidth / 1.75,
          height: _kPanelHeight,
          child: _buildTextField(
            controller: controller.replaceInputController,
            focusNode: controller.replaceInputFocusNode,
          ),
        ),
        if (!readOnly) ...[
          _buildIconButton(
            icon: Icons.done,
            tooltip: context.tr('textEditor.replace'),
            onPressed: value.result == null ? null : controller.replaceMatch,
          ),
          _buildIconButton(
            icon: Icons.done_all,
            tooltip: context.tr('textEditor.replaceAll'),
            onPressed: value.result == null
                ? null
                : controller.replaceAllMatches,
          ),
        ],
      ],
    );
  }

  // ── 通用子组件 ───────────────────────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    double iconsWidth = 0,
  }) {
    return Padding(
      padding: _kPadding,
      child: TextField(
        maxLines: 1,
        controller: controller,
        focusNode: focusNode,
        style: const TextStyle(fontSize: _kInputFontSize),
        decoration:
            const InputDecoration(
              filled: true,
              contentPadding: _kInputContentPadding,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(0)),
                gapPadding: 0,
              ),
            ).copyWith(
              contentPadding: const EdgeInsets.only(
                left: 5,
                right: 5,
              ).add(EdgeInsets.only(right: iconsWidth)),
            ),
      ),
    );
  }

  Widget _buildCheckText({
    required BuildContext context,
    required String text,
    required bool checked,
    required VoidCallback onPressed,
  }) {
    final selectedColor = Theme.of(context).primaryColor;
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: _kIconWidth * 0.75,
          child: Text(
            text,
            style: TextStyle(
              color: checked ? selectedColor : null,
              fontSize: _kInputFontSize,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    VoidCallback? onPressed,
    String? tooltip,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: _kIconSize),
      constraints: const BoxConstraints(
        maxWidth: _kIconWidth,
        maxHeight: _kIconHeight,
      ),
      tooltip: tooltip,
      splashRadius: max(_kIconWidth, _kIconHeight) / 2,
    );
  }
}
