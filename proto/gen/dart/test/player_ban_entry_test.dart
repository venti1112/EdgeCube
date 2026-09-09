import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for PlayerBanEntry
void main() {
  final instance = PlayerBanEntryBuilder();
  // TODO add properties to the builder and call build()

  group(PlayerBanEntry, () {
    // String name
    test('to test the property `name`', () async {
      // TODO
    });

    // String uuid
    test('to test the property `uuid`', () async {
      // TODO
    });

    // 封禁原因;文本名单为空串
    // String reason
    test('to test the property `reason`', () async {
      // TODO
    });

    // 封禁来源(执行人);文本名单为空串
    // String source_
    test('to test the property `source_`', () async {
      // TODO
    });

    // 过期时间(Java 用 expires,PNX 用 expireDate,已归一化);文本名单为空串
    // String expires
    test('to test the property `expires`', () async {
      // TODO
    });

    // 创建时间(Java 用 created,PNX 用 creationDate,已归一化);文本名单为空串
    // String created
    test('to test the property `created`', () async {
      // TODO
    });

  });
}
