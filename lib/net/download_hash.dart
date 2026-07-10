import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// 在独立 isolate 中计算文件哈希，避免大文件同步 CPU 密集操作阻塞 UI 线程。
///
/// 与 `ModrinthService.computeSha1` 相同的 `compute` 模式；参数与返回均为
/// [String]，可安全跨 isolate 传递。

/// 计算文件的 SHA-1（小写十六进制）。
Future<String> computeFileSha1(String filePath) => compute(_sha1Sync, filePath);

/// 计算文件的 SHA-256（小写十六进制）。
Future<String> computeFileSha256(String filePath) =>
    compute(_sha256Sync, filePath);

String _sha1Sync(String filePath) =>
    sha1.convert(File(filePath).readAsBytesSync()).toString();

String _sha256Sync(String filePath) =>
    sha256.convert(File(filePath).readAsBytesSync()).toString();
