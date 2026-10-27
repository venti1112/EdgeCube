import 'platform_base.dart';
// Web 没有 dart:io,固定走「不支持」实现;其余平台按需换实现。
import 'platform_stub.dart' if (dart.library.io) 'platform_native.dart' as impl;

export 'model.dart';
export 'platform_base.dart';

LocalServicePlatform createLocalServicePlatform() =>
    impl.createLocalServicePlatform();
