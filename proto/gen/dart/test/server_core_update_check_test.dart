import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for ServerCoreUpdateCheck
void main() {
  final instance = ServerCoreUpdateCheckBuilder();
  // TODO add properties to the builder and call build()

  group(ServerCoreUpdateCheck, () {
    // 该实例是否支持服务端核心更新(当前仅 Paper 系 java 实例)
    // bool supported
    test('to test the property `supported`', () async {
      // TODO
    });

    // 检测到的更新源(paper = PaperMC 官方 API)
    // String source_
    test('to test the property `source_`', () async {
      // TODO
    });

    // 当前服务端核心版本(如 1.21.4);未知时为空串
    // String currentVersion
    test('to test the property `currentVersion`', () async {
      // TODO
    });

    // 当前核心构建号(如 214);未知时为空串
    // String currentBuild
    test('to test the property `currentBuild`', () async {
      // TODO
    });

    // 最新可用版本(如 1.21.4)
    // String latestVersion
    test('to test the property `latestVersion`', () async {
      // TODO
    });

    // 最新构建号(如 214)
    // String latestBuild
    test('to test the property `latestBuild`', () async {
      // TODO
    });

    // 最新版核心 jar 下载地址
    // String downloadUrl
    test('to test the property `downloadUrl`', () async {
      // TODO
    });

    // 下载文件 sha256(64 位 hex)
    // String sha256
    test('to test the property `sha256`', () async {
      // TODO
    });

    // 当前是否有可用更新(版本/构建与已装核心不一致)
    // bool updateAvailable
    test('to test the property `updateAvailable`', () async {
      // TODO
    });

  });
}
