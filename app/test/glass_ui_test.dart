import 'dart:convert';

import 'package:edgecube_app/app.dart';
import 'package:edgecube_app/settings/appearance.dart';
import 'package:edgecube_app/settings/appearance_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 造一个"已启动"的 ProviderContainer:与 main() 同样的预加载 + override 路径。
Future<ProviderContainer> _containerWith(Map<String, Object> saved) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();
  final appearance = await loadAppearanceSettings(prefs);
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(prefs),
      initialAppearanceProvider.overrideWithValue(appearance),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 已持久化的外观设置(用真实存储键写入,验证 fromJson 回读链路)
String _saved(AppearanceSettings s) =>
    jsonEncode(s.toJson());

Future<ProviderContainer> _pumpApp(
  WidgetTester tester,
  Map<String, Object> saved,
) async {
  final container = await _containerWith(saved);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const EdgeCubeApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('背景=无 时不磨砂,但内容照常渲染', (tester) async {
    await _pumpApp(tester, {});
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('服务器 列表项 1'), findsOneWidget);
  });

  testWidgets('背景=纯色 进入毛玻璃模式:导航栏 + 内容区各一层 BackdropFilter', (
    tester,
  ) async {
    await _pumpApp(tester, {
      AppearanceSettings.storageKey: _saved(
        const AppearanceSettings(backgroundType: BackgroundType.color),
      ),
    });
    // 测试窗口为横屏 → 侧栏(1) + 内容区(1)
    expect(find.byType(BackdropFilter), findsNWidgets(2));
  });

  testWidgets('关掉内容区模糊后只剩导航栏一层,内容不消失', (tester) async {
    final container = await _pumpApp(tester, {
      AppearanceSettings.storageKey: _saved(
        const AppearanceSettings(backgroundType: BackgroundType.color),
      ),
    });
    // 走单项 Provider,不再碰聚合状态
    await container.read(contentBlurEnabledProvider.notifier).set(false);
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('服务器 列表项 1'), findsOneWidget);

    await container.read(navBlurEnabledProvider.notifier).set(false);
    await tester.pumpAndSettle();
    // 全部关闭 → 完全降级为实心面板,但页面结构不变
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('服务器 列表项 1'), findsOneWidget);
  });

  testWidgets('模糊半径 = 0 等同关闭(只摘掉该处图层,不牵连另一处)', (tester) async {
    final container = await _pumpApp(tester, {
      AppearanceSettings.storageKey: _saved(
        const AppearanceSettings(
          backgroundType: BackgroundType.color,
          contentBlurSigma: 0,
        ),
      ),
    });
    // 内容区半径 0 → 摘掉内容区图层;侧栏半径仍为默认 15 → 保留
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(container.read(appearanceSettingsProvider).contentBlurSigma, 0);
    expect(find.text('服务器 列表项 1'), findsOneWidget);
  });

  testWidgets('外观页渲染出毛玻璃分区,拖动滑块写回 Provider', (tester) async {
    // 外观页很长,放大窗口让整页一次性挂载,避免 ListView 懒加载导致找不到控件
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(prefs),
        initialAppearanceProvider.overrideWithValue(const AppearanceSettings()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(colorScheme: const ColorScheme.light()),
          home: const AppearancePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('毛玻璃'), findsOneWidget);
    expect(find.text('内容区模糊半径'), findsOneWidget);

    // 最后一个滑块 = 内容表面不透明度,向左拖应降低不透明度
    final before = container.read(contentOpacityProvider);
    await tester.drag(find.byType(Slider).last, const Offset(-200, 0));
    await tester.pumpAndSettle();
    // 断言读单项 Provider;聚合状态里也应同步(单一真源)
    expect(container.read(contentOpacityProvider), lessThan(before));
    expect(
      container.read(appearanceSettingsProvider).contentOpacity,
      container.read(contentOpacityProvider),
    );
  });

  test('单项 Provider 写入会 clamp,并同步到聚合状态', () async {
    final container = await _containerWith({});

    await container.read(navBlurSigmaProvider.notifier).set(9999);
    await container.read(contentBlurSigmaProvider.notifier).set(-100);
    await container.read(navOpacityProvider.notifier).set(3);
    await container.read(contentOpacityProvider.notifier).set(-1);

    expect(container.read(navBlurSigmaProvider), AppearanceSettings.blurSigmaMax);
    expect(container.read(contentBlurSigmaProvider), AppearanceSettings.blurSigmaMin);
    expect(container.read(navOpacityProvider), AppearanceSettings.opacityMax);
    expect(container.read(contentOpacityProvider), AppearanceSettings.opacityMin);
  });

  test('改一项只通知该项的监听者,无关项不被打扰', () async {
    final container = await _containerWith({});
    var navHits = 0;
    var contentHits = 0;
    container.listen(navBlurSigmaProvider, (_, _) => navHits++);
    container.listen(contentBlurSigmaProvider, (_, _) => contentHits++);

    await container.read(contentBlurSigmaProvider.notifier).set(25);
    // Riverpod 的监听回调走调度队列,不是同步触发
    await Future<void>.delayed(Duration.zero);

    expect(contentHits, 1);
    expect(navHits, 0);
  });

  test('所有单项 Provider 都能从聚合状态读回同一个值', () async {
    final container = await _containerWith({
      AppearanceSettings.storageKey: _saved(
        const AppearanceSettings(
          themeMode: ThemeMode.dark,
          followSystemColor: false,
          seedColor: Color(0xFF00FF00),
          backgroundType: BackgroundType.image,
          backgroundColor: Color(0xFF010203),
          backgroundImage: '/tmp/x.png',
          navBlurEnabled: false,
          navBlurSigma: 7,
          navOpacity: 0.11,
          contentBlurEnabled: false,
          contentBlurSigma: 9,
          contentOpacity: 0.22,
        ),
      ),
    });
    final s = container.read(appearanceSettingsProvider);

    expect(container.read(themeModeProvider), s.themeMode);
    expect(container.read(followSystemColorProvider), s.followSystemColor);
    expect(container.read(seedColorProvider), s.seedColor);
    expect(container.read(backgroundTypeProvider), s.backgroundType);
    expect(container.read(backgroundColorProvider), s.backgroundColor);
    expect(container.read(backgroundImageProvider), s.backgroundImage);
    expect(container.read(navBlurEnabledProvider), s.navBlurEnabled);
    expect(container.read(navBlurSigmaProvider), s.navBlurSigma);
    expect(container.read(navOpacityProvider), s.navOpacity);
    expect(container.read(contentBlurEnabledProvider), s.contentBlurEnabled);
    expect(container.read(contentBlurSigmaProvider), s.contentBlurSigma);
    expect(container.read(contentOpacityProvider), s.contentOpacity);
    // 派生 Provider:图片背景 → 进入磨砂模式
    expect(container.read(glassModeEnabledProvider), isTrue);
  });

  test('改动落盘,下次启动能读回', () async {
    final container = await _containerWith({});

    await container.read(backgroundTypeProvider.notifier).set(BackgroundType.color);
    await container
        .read(backgroundColorProvider.notifier)
        .set(const Color(0xFF123456));
    await container.read(contentBlurSigmaProvider.notifier).set(30);
    await container.read(navOpacityProvider.notifier).set(0.42);
    await container.read(contentBlurEnabledProvider.notifier).set(false);
    await container.read(navBlurEnabledProvider.notifier).set(false);

    final restored = await loadAppearanceSettings(
      await SharedPreferences.getInstance(),
    );
    expect(restored.backgroundType, BackgroundType.color);
    expect(restored.backgroundColor, const Color(0xFF123456));
    expect(restored.contentBlurSigma, 30);
    expect(restored.navOpacity, 0.42);
    expect(restored.contentBlurEnabled, isFalse);
    expect(restored.navBlurEnabled, isFalse);
  });

  test('存储内容损坏时回退默认值', () async {
    final restored = await (() async {
      SharedPreferences.setMockInitialValues({
        AppearanceSettings.storageKey: '{ not json',
      });
      return loadAppearanceSettings(await SharedPreferences.getInstance());
    })();
    expect(restored.contentBlurSigma, AppearanceSettings.defaultContentBlurSigma);
  });
}
