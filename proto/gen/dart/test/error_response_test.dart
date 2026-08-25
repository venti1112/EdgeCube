import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for ErrorResponse
void main() {
  final instance = ErrorResponseBuilder();
  // TODO add properties to the builder and call build()

  group(ErrorResponse, () {
    // 机器可读错误码,如 not_authenticated / invalid_credentials / instance_busy / not_found
    // String code
    test('to test the property `code`', () async {
      // TODO
    });

    // 人类可读错误信息(daemon 侧为英文,UI 按 code 本地化)
    // String message
    test('to test the property `message`', () async {
      // TODO
    });

    // BuiltMap<String, JsonObject> details
    test('to test the property `details`', () async {
      // TODO
    });

  });
}
