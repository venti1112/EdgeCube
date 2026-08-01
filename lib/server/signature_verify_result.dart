/// 运行环境包签名验证结果。
///
/// 由原生层通过 MethodChannel 返回，Dart 层封装为此类型。
///
/// - [hasSignature] 为 `false`：包中无签名条目。
/// - [hasSignature] 为 `true` 且 [valid] 为 `false`：有签名但验证失败
///   （签名不匹配或格式错误）。
/// - [hasSignature] 为 `true` 且 [valid] 为 `true`：验证通过。
class SignatureVerifyResult {
  const SignatureVerifyResult({
    required this.hasSignature,
    required this.valid,
  });

  /// 包中是否存在签名条目。
  final bool hasSignature;

  /// 签名是否验证通过。
  final bool valid;

  /// 是否为可信包（有签名且验证通过）。
  bool get isTrusted => hasSignature && valid;

  factory SignatureVerifyResult.fromMap(Map<dynamic, dynamic> m) {
    return SignatureVerifyResult(
      hasSignature: m['hasSignature'] as bool? ?? false,
      valid: m['valid'] as bool? ?? false,
    );
  }
}
