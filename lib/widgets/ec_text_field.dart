import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

/// 具备完整 Material 输入能力的 Miuix 风格输入框。
///
/// [MiuixTextField] 的构造参数不支持 `inputFormatters` / `maxLength` /
/// `errorText` / 辅助文案，而本项目有十余处端口号、内存大小之类的数字约束依赖
/// `inputFormatters`。因此这里保留 Miuix 的视觉（超椭圆圆角 + secondaryContainer
/// 背景 + 聚焦时 primary 描边动效，取值与 [MiuixTextFieldDefaults] 一致），
/// 内部包一个 `InputDecoration.collapsed` 的原生 [TextField] 以拿回全部能力。
///
/// 无格式化需求的简单输入直接用 [MiuixTextField] 即可，不必用本组件。
class EcTextField extends StatefulWidget {
  const EcTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.suffixText,
    this.textStyle,
    this.cornerRadius = MiuixTextFieldDefaults.cornerRadius,
    this.insideMargin = MiuixTextFieldDefaults.insideMargin,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// 未输入内容时显示的占位文案（对应原 `InputDecoration.labelText`）。
  final String? label;

  /// 占位文案；[label] 为空时生效。
  final String? hint;

  /// 输入框下方的辅助说明（对应原 `InputDecoration.helperText`）。
  final String? helperText;

  /// 输入框下方的错误文案；非空时描边与文案转为错误色。
  final String? errorText;

  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? suffixText;

  /// 覆盖输入文本样式（如代码编辑场景用等宽字体）。
  final TextStyle? textStyle;
  final double cornerRadius;
  final EdgeInsets insideMargin;

  @override
  State<EcTextField> createState() => _EcTextFieldState();
}

class _EcTextFieldState extends State<EcTextField>
    with SingleTickerProviderStateMixin {
  FocusNode? _ownedFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  late final AnimationController _borderController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(EcTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      _ownedFocusNode?.removeListener(_onFocusChanged);
      _focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChanged);
    _ownedFocusNode?.dispose();
    _borderController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _borderController.forward();
    } else {
      _borderController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = MiuixTextFieldDefaults.textFieldColors(context);
    final hasError = widget.errorText != null;
    final focusColor = hasError ? theme.colors.error : colors.borderColor;
    final placeholder = widget.label ?? widget.hint;

    final field = AnimatedBuilder(
      animation: _borderController,
      builder: (context, _) {
        // 有错误时常驻描边；否则跟随聚焦进度淡入。
        final progress = hasError ? 1.0 : _borderController.value;
        final borderWidth = progress * MiuixTextFieldDefaults.borderWidth;
        final borderColor = Color.lerp(
          colors.backgroundColor,
          focusColor,
          progress,
        )!;

        return DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.backgroundColor,
            shape: MiuixSquircleBorder(
              cornerRadius: widget.cornerRadius,
              side: borderWidth > 0
                  ? BorderSide(color: borderColor, width: borderWidth)
                  : BorderSide.none,
            ),
          ),
          child: Padding(
            // insideMargin 语义为「每侧」边距，与 MiuixTextField 保持一致：
            // 取 .top/.left 等单侧值，不能用 .vertical/.horizontal（会翻倍）。
            padding: EdgeInsets.only(
              top: widget.insideMargin.top,
              bottom: widget.insideMargin.bottom,
              left: widget.prefixIcon != null ? 0 : widget.insideMargin.left,
              right: (widget.suffixIcon != null || widget.suffixText != null)
                  ? 0
                  : widget.insideMargin.right,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.prefixIcon != null) widget.prefixIcon!,
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    readOnly: widget.readOnly,
                    autofocus: widget.autofocus,
                    obscureText: widget.obscureText,
                    maxLines: widget.obscureText ? 1 : widget.maxLines,
                    minLines: widget.minLines,
                    maxLength: widget.maxLength,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    textCapitalization: widget.textCapitalization,
                    inputFormatters: widget.inputFormatters,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    cursorColor: focusColor,
                    style: (widget.textStyle ?? theme.textStyles.main).copyWith(
                      color: theme.colors.onBackground,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: placeholder,
                      hintStyle: theme.textStyles.main.copyWith(
                        color: colors.labelColor,
                      ),
                    ).copyWith(counterText: ''),
                  ),
                ),
                if (widget.suffixText != null)
                  Padding(
                    padding: EdgeInsets.only(right: widget.insideMargin.right),
                    child: MiuixText(
                      widget.suffixText!,
                      color: colors.labelColor,
                    ),
                  ),
                if (widget.suffixIcon != null) widget.suffixIcon!,
              ],
            ),
          ),
        );
      },
    );

    final footnote = widget.errorText ?? widget.helperText;
    if (footnote == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: MiuixText(
            footnote,
            style: theme.textStyles.footnote1,
            color: hasError
                ? theme.colors.error
                : theme.colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }
}
