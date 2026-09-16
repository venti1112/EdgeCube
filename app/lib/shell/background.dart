import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../settings/appearance.dart';
import 'bg_image.dart';

/// 全屏背景层:无背景时渲染主题 surface 色;纯色渲染所选颜色;
/// 图片模式渲染自定义图片(未设置或加载失败回退 surface)。
///
/// 只订阅背景相关的三个全局 Provider,毛玻璃参数变化不会让它重建。
class BackgroundLayer extends ConsumerWidget {
  const BackgroundLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(backgroundTypeProvider);
    final color = ref.watch(backgroundColorProvider);
    final image = ref.watch(backgroundImageProvider);
    final cs = Theme.of(context).colorScheme;
    switch (type) {
      case BackgroundType.color:
        return ColoredBox(color: color);
      case BackgroundType.image:
        if (image == null) return ColoredBox(color: cs.surface);
        return buildBackgroundImage(image, cs.surface);
      case BackgroundType.none:
        return ColoredBox(color: cs.surface);
    }
  }
}
