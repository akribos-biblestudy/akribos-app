import 'package:akribos_app/core/api_client.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

void main() {
  test(
    'only Reader connection failures signal fallback; success cancels it',
    () async {
      var fails = true;
      final adapter = FakeHttpAdapter((request) async {
        if (fails) {
          throw DioException(
            requestOptions: request.options,
            type: DioExceptionType.connectionError,
          );
        }
        return jsonResponse({'ok': true});
      });
      final api = AppApi(
        server: 'https://example.test',
        dio: Dio()..httpClientAdapter = adapter,
        cookies: CookieJar(),
      );
      addTearDown(api.dispose);
      var failures = 0;
      var restores = 0;
      api.onReaderConnectionFailure = () => failures++;
      api.onReaderConnectionRestored = () => restores++;
      await expectLater(
        api.get('/api/reader/43/1?resource=bible'),
        throwsA(isA<ApiException>()),
      );
      expect(failures, 1);
      await expectLater(
        api.get('/api/app/offline/resources'),
        throwsA(isA<ApiException>()),
      );
      expect(failures, 1);
      await expectLater(
        api.get('/api/app/page?path=%2Fnotes'),
        throwsA(isA<ApiException>()),
      );
      expect(failures, 1);
      await expectLater(
        api.get('/api/app/page?path=%2FJoh3'),
        throwsA(isA<ApiException>()),
      );
      expect(failures, 2);
      fails = false;
      await api.get('/api/app/page?path=%2Fnotes');
      expect(restores, 0);
      await api.get('/api/reader/43/1?resource=bible');
      expect(restores, 1);
    },
  );
}
