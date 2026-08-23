import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../settings/appearance.dart';
import 'bg_image.dart';

/// 全屏背景层:无背景时渲染主题 surface 色;纯色渲染所选颜色;
/// 图片模式渲染自定义图片(未设置或加载失败回退 surface)。
class BackgroundLayer extends ConsumerWidget {
  const BackgroundLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appearanceSettingsProvider);
    final cs = Theme.of(context).colorScheme;
    switch (s.backgroundType) {
      case BackgroundType.color:
        return ColoredBox(color: s.backgroundColor);
      case BackgroundType.image:
        final src = s.backgroundImage;
        if (src == null) return ColoredBox(color: cs.surface);
        return buildBackgroundImage(src, cs.surface);
      case BackgroundType.none:
        return ColoredBox(color: cs.surface);
    }
  }
}
