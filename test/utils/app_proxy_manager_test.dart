import 'package:flutter_test/flutter_test.dart';
import 'package:proxy_getter/proxy_getter.dart';
import 'package:vynody/utils/app_proxy_manager.dart';

void main() {
  group('AppProxyManager', () {
    late AppProxyManager manager;

    setUp(() {
      manager = AppProxyManager.instance;
      manager.updateSettings(
        mode: AppProxyMode.system,
        customHost: '127.0.0.1',
        customPort: 7890,
        customBypass: 'localhost, 127.0.0.1, <local>',
      );
    });

    test('AppProxyMode.fromString parses correctly', () {
      expect(AppProxyMode.fromString('direct'), equals(AppProxyMode.direct));
      expect(AppProxyMode.fromString('custom'), equals(AppProxyMode.custom));
      expect(AppProxyMode.fromString('system'), equals(AppProxyMode.system));
      expect(AppProxyMode.fromString('unknown'), equals(AppProxyMode.system));
      expect(AppProxyMode.fromString(null), equals(AppProxyMode.system));
    });

    test('Direct mode always returns DIRECT', () {
      manager.updateSettings(mode: AppProxyMode.direct);

      expect(
        manager.resolveProxyRuleSync(Uri.parse('https://api.musicbrainz.org')),
        equals('DIRECT'),
      );
      expect(
        manager.resolveProxyRuleSync(Uri.parse('http://example.com/test.mp3')),
        equals('DIRECT'),
      );
    });

    test('Custom mode returns formatted proxy rule', () {
      manager.updateSettings(
        mode: AppProxyMode.custom,
        customHost: '127.0.0.1',
        customPort: 7890,
        customBypass: '',
      );

      final rule = manager.resolveProxyRuleSync(
        Uri.parse('https://api.musicbrainz.org'),
      );
      expect(rule, equals('PROXY 127.0.0.1:7890; DIRECT'));
    });

    test('Custom mode normalizes proxy address input', () {
      manager.updateSettings(
        mode: AppProxyMode.custom,
        customHost: 'http://192.168.1.100/',
        customPort: 8888,
        customBypass: '',
      );

      final rule = manager.resolveProxyRuleSync(
        Uri.parse('https://api.musicbrainz.org'),
      );
      expect(rule, equals('PROXY 192.168.1.100:8888; DIRECT'));
    });

    test('Custom mode fallback to DIRECT when host is empty or port invalid', () {
      manager.updateSettings(
        mode: AppProxyMode.custom,
        customHost: '',
        customPort: 7890,
      );
      expect(
        manager.resolveProxyRuleSync(Uri.parse('https://example.com')),
        equals('DIRECT'),
      );

      manager.updateSettings(
        mode: AppProxyMode.custom,
        customHost: '127.0.0.1',
        customPort: 0,
      );
      expect(
        manager.resolveProxyRuleSync(Uri.parse('https://example.com')),
        equals('DIRECT'),
      );
    });

    test('Custom mode respects bypass rules', () {
      manager.updateSettings(
        mode: AppProxyMode.custom,
        customHost: '127.0.0.1',
        customPort: 7890,
        customBypass: 'localhost; 127.0.0.1; *.internal.net; <local>',
      );

      // Localhost bypass
      expect(
        manager.resolveProxyRuleSync(Uri.parse('http://localhost:8080/api')),
        equals('DIRECT'),
      );
      expect(
        manager.resolveProxyRuleSync(Uri.parse('http://127.0.0.1:9000/stream')),
        equals('DIRECT'),
      );

      // <local> bypass (host without dot)
      expect(
        manager.resolveProxyRuleSync(Uri.parse('http://myserver:5000/stream')),
        equals('DIRECT'),
      );

      // Subdomain wildcard bypass
      expect(
        manager.resolveProxyRuleSync(Uri.parse('https://music.internal.net/audio')),
        equals('DIRECT'),
      );

      // Non-bypassed external host
      expect(
        manager.resolveProxyRuleSync(Uri.parse('https://subsonic.remote.com/rest')),
        equals('PROXY 127.0.0.1:7890; DIRECT'),
      );
    });

    test('updateSettings triggers onProxyChanged and updates properties', () {
      bool called = false;
      manager.onProxyChanged = () {
        called = true;
      };

      manager.updateSettings(
        mode: AppProxyMode.custom,
        customHost: '10.0.0.1',
        customPort: 1080,
      );

      expect(called, isTrue);
      expect(manager.mode, equals(AppProxyMode.custom));
      expect(manager.customHost, equals('10.0.0.1'));
      expect(manager.customPort, equals(1080));
    });

    test('resolveProxyRule asynchronous method caches lookups', () async {
      manager.updateSettings(
        mode: AppProxyMode.custom,
        customHost: '127.0.0.1',
        customPort: 7890,
        customBypass: '',
      );

      final uri = Uri.parse('https://musicbrainz.org/ws/2/recording');
      final rule1 = await manager.resolveProxyRule(uri);
      final rule2 = await manager.resolveProxyRule(uri);

      expect(rule1, equals('PROXY 127.0.0.1:7890; DIRECT'));
      expect(rule2, equals('PROXY 127.0.0.1:7890; DIRECT'));
    });

    test('resolveProxyRuleSync does not cause recursion or stack overflow in system mode', () {
      manager.updateSettings(mode: AppProxyMode.system);
      final rule = manager.resolveProxyRuleSync(Uri.parse('https://demo.navidrome.org/rest/ping.view'));
      expect(rule, isNotEmpty);
    });
  });

  group('AppProxyManager system proxy cache', () {
    late AppProxyManager manager;
    
    const proxyUri = 'https://generativelanguage.googleapis.com/v1beta';

    setUp(() {
      manager = AppProxyManager.instance;
      manager.updateSettings(mode: AppProxyMode.system);
      manager.clearCache();
    });

    tearDown(() {
      manager.systemProxyLoaderOverride = null;
      manager.clearCache();
    });

    test('loader failure is not cached and retried on next resolution', () async {
      var calls = 0;
      manager.systemProxyLoaderOverride = () async {
        calls++;
        if (calls == 1) throw Exception('channel unavailable');
        return const SystemProxy(
          enable: true,
          host: '127.0.0.1',
          port: 7890,
          bypass: '',
        );
      };

      final failed = await manager.resolveProxyRule(Uri.parse(proxyUri));
      expect(failed, equals('DIRECT'));
      expect(manager.cachedSystemProxy, isNull);

      manager.clearCache();
      final retried = await manager.resolveProxyRule(Uri.parse(proxyUri));
      expect(retried, equals('PROXY 127.0.0.1:7890; DIRECT'));
      expect(calls, equals(2));
    });

    test('successful reads are cached within TTL', () async {
      var calls = 0;
      manager.systemProxyLoaderOverride = () async {
        calls++;
        return const SystemProxy(
          enable: true,
          host: '127.0.0.1',
          port: 7890,
          bypass: '',
        );
      };

      await manager.resolveProxyRule(Uri.parse(proxyUri));
      await manager.resolveProxyRule(Uri.parse('$proxyUri?2'));

      expect(calls, equals(1));
    });

    test('cache expiry re-reads system proxy without settings change', () async {
      var calls = 0;
      manager.systemProxyLoaderOverride = () async {
        calls++;
        return const SystemProxy(
          enable: true,
          host: '127.0.0.1',
          port: 7890,
          bypass: '',
        );
      };

      await manager.resolveProxyRule(Uri.parse(proxyUri));
      expect(calls, equals(1));

      final cachedAt = manager.systemProxyCachedAtForTest!;
      manager.systemProxyCachedAtForTest = cachedAt.subtract(
        AppProxyManager.systemProxyCacheTtl + const Duration(seconds: 1),
      );

      // 换一个 URL，避免被按 URL 缓存的规则短路，验证的是系统代理缓存本身过期。
      await manager.resolveProxyRule(Uri.parse('$proxyUri?after-expiry'));
      expect(calls, equals(2));
    });

    test('concurrent resolutions share one in-flight refresh', () async {
      var calls = 0;
      manager.systemProxyLoaderOverride = () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const SystemProxy(
          enable: true,
          host: '127.0.0.1',
          port: 7890,
          bypass: '',
        );
      };

      await Future.wait([
        manager.resolveProxyRule(Uri.parse('$proxyUri?a')),
        manager.resolveProxyRule(Uri.parse('$proxyUri?b')),
        manager.resolveProxyRule(Uri.parse('$proxyUri?c')),
      ]);

      expect(calls, equals(1));
    });
  });
}
