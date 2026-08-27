/// Web 平台:无本机文件访问能力,不存在 local.key。
Future<String?> loadLocalKey() async => null;

Future<bool> hasLocalKey() async => false;

/// Web 平台不参与本机免密登录。
String signLocalChallenge(String localKey, String challenge) =>
    throw UnsupportedError('web platform has no local.key');