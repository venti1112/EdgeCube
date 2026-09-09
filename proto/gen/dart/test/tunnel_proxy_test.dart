import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for TunnelProxy
void main() {
  final instance = TunnelProxyBuilder();
  // TODO add properties to the builder and call build()

  group(TunnelProxy, () {
    // 代理名称(隧道内唯一)
    // String name
    test('to test the property `name`', () async {
      // TODO
    });

    // ProxyType type
    test('to test the property `type`', () async {
      // TODO
    });

    // 本地服务地址(如 127.0.0.1)
    // String localIp
    test('to test the property `localIp`', () async {
      // TODO
    });

    // int localPort
    test('to test the property `localPort`', () async {
      // TODO
    });

    // tcp/udp 必填;http/https 无需
    // int remotePort
    test('to test the property `remotePort`', () async {
      // TODO
    });

    // http/https 必填(至少一个域名);tcp/udp 忽略
    // BuiltList<String> customDomains
    test('to test the property `customDomains`', () async {
      // TODO
    });

  });
}
