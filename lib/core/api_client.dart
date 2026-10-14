import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'json.dart';
export 'json.dart';

class ApiResult {
  const ApiResult({
    required this.type,
    required this.status,
    this.data = const {},
    this.location,
  });
  factory ApiResult.fromJson(Json value, int status) => ApiResult(
    type: asString(value['type'], 'failure'),
    status: asInt(value['status'], status),
    data: asMap(value['data']),
    location: value['location'] as String?,
  );
  final String type;
  final int status;
  final Json data;
  final String? location;
  bool get isSuccess => type == 'success';
  bool get isRedirect => type == 'redirect' && location != null;
  bool get ok => isSuccess;
  String get message => errorMessage(data, status);
}

class ApiException implements Exception {
  const ApiException(this.message, {this.status = 0, this.data = const {}});
  final String message;
  final int status;
  final Json data;
  @override
  String toString() => message;
}

class AppRedirect implements Exception {
  const AppRedirect(this.location);
  final String location;
}

String errorMessage(Json data, int status) {
  final value =
      data['message'] ??
      data['error'] ??
      data.entries
          .where((e) => e.key.toLowerCase().endsWith('error'))
          .firstOrNull
          ?.value;
  const messages = {
    'conflict': 'Der Stand wurde inzwischen geändert. Dein Entwurf bleibt erhalten. Lade den aktuellen Stand, bevor du erneut speicherst.',
    'invalid': 'Die Anmeldedaten stimmen nicht.',
    'email': 'Bitte eine gültige E-Mail-Adresse eingeben.',
    'code': 'Der Code ist falsch oder abgelaufen.',
    'throttled':
        'Zu viele Versuche. Bitte warte und versuche es später erneut.',
    'mail': 'Die E-Mail konnte nicht versendet werden. Bitte später erneut versuchen.',
    'unverified': 'Die E-Mail-Adresse muss zuerst bestätigt werden.',
    'missing': 'Bitte alle Pflichtfelder ausfüllen.',
    'current': 'Das aktuelle Passwort stimmt nicht.',
    'mismatch': 'Die beiden Passwörter stimmen nicht überein.',
    'weak': 'Bitte ein längeres und sichereres Passwort wählen.',
    'notFound': 'Dieser Inhalt ist nicht mehr verfügbar.',
    'forbidden': 'Du hast keine Berechtigung für diese Aktion.',
    'confirm': 'Bitte die angegebene Bestätigung genau eingeben.',
  };
  if (messages[value] != null) return messages[value]!;
  if (value is String && value.length > 16) return value;
  return switch (status) {
    401 => 'Bitte melde dich erneut an.',
    403 => 'Diese Aktion ist nicht erlaubt.',
    404 => 'Dieser Inhalt ist nicht verfügbar.',
    409 => messages['conflict']!,
    413 => 'Die ausgewählte Datei ist zu groß.',
    429 => messages['throttled']!,
    >= 500 =>
      'Der Server ist vorübergehend nicht erreichbar. Bitte erneut versuchen.',
    _ =>
      'Die Aktion konnte nicht gespeichert werden${value == null ? '.' : ' ($value).'}',
  };
}

class AppUpload {
  const AppUpload({
    required this.field,
    required this.name,
    required this.bytes,
    this.contentType,
  });
  final String field, name;
  final List<int> bytes;
  final String? contentType;
}

class SecureCookieStorage implements Storage {
  SecureCookieStorage(this.namespace, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final String namespace;
  final FlutterSecureStorage _storage;
  String _key(String key) =>
      'akribos.$namespace.${base64Url.encode(utf8.encode(key))}';
  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {}
  @override
  Future<String?> read(String key) => _storage.read(key: _key(key));
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: _key(key), value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: _key(key));
  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      await delete(key);
    }
  }
}

/// The package's default redirect handling copies Set-Cookie to redirect targets.
/// A first-party session must only ever be stored for the server that issued it.
class _ServerCookieManager extends CookieManager {
  _ServerCookieManager(super.cookieJar);

  @override
  Future<void> saveCookies(Response response) => super.saveCookies(
    Response(
      requestOptions: response.requestOptions,
      headers: response.headers,
      statusCode: 200,
    ),
  );
}

String _formValue(Object value) {
  if (value is String || value is num || value is bool) return value.toString();
  throw const ApiException(
    'Formularfelder dürfen keine verschachtelten Objekte enthalten.',
  );
}

Json _formFields(Json fields) => {
  for (final entry in fields.entries)
    if (entry.value != null)
      entry.key: entry.value is List
          ? (entry.value as List)
                .where((value) => value != null)
                .map((value) => _formValue(value as Object))
                .toList()
          : _formValue(entry.value as Object),
};

/// The first-party client uses revocable server sessions. No API key or text cache is bundled.
class AppApi {
  AppApi({
    required String server,
    Dio? dio,
    CookieJar? cookies,
    String? browserTabId,
  }) : origin = validateServer(server),
       _dio = dio ?? Dio(),
       browserTabId = browserTabId ?? newBrowserTabId() {
    _cookies =
        cookies ??
        PersistCookieJar(
          storage: SecureCookieStorage(
            base64Url.encode(utf8.encode(origin.origin)),
          ),
        );
    _dio.options = BaseOptions(
      baseUrl: origin.origin,
      followRedirects: false,
      maxRedirects: 0,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(minutes: 3),
      validateStatus: (status) => status != null && status < 600,
      headers: {
        'Accept': 'application/json',
        'Origin': origin.origin,
        'x-akribos-app': '1',
        'x-reader-browser-tab': this.browserTabId,
      },
    );
    _dio.interceptors.add(_ServerCookieManager(_cookies));
  }
  final Uri origin;
  final Dio _dio;
  late final CookieJar _cookies;
  final String browserTabId;
  Json bootstrap = {};

  Future<void> initializeReader(double width) async {
    final columns = width < 768
        ? 1
        : width < 1200
        ? 2
        : width < 1920
        ? 3
        : 4;
    await _cookies.saveFromResponse(origin, [
      Cookie('reader-browser-enabled', '1')
        ..path = '/'
        ..secure = origin.scheme == 'https',
      Cookie('reader-initial-columns', '$columns')
        ..path = '/'
        ..secure = origin.scheme == 'https',
    ]);
  }

  static Uri validateServer(String value) {
    final uri = Uri.tryParse(value);
    final development =
        kDebugMode &&
        uri != null &&
        ['localhost', '127.0.0.1', '::1', '10.0.2.2'].contains(uri.host);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.scheme != 'https' && !(development && uri.scheme == 'http'))) {
      throw const ApiException(
        'Die Serveradresse muss eine HTTPS-Adresse ohne Pfad oder Zugangsdaten sein.',
      );
    }
    return uri;
  }

  static String newBrowserTabId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Uri safeUri(String path) {
    final uri = Uri.tryParse(path);
    final resolved = uri == null ? null : origin.resolveUri(uri);
    if (resolved == null ||
        !['http', 'https'].contains(resolved.scheme) ||
        resolved.origin != origin.origin ||
        resolved.userInfo.isNotEmpty ||
        path.contains('\\') ||
        path.codeUnits.any((unit) => unit < 32 || unit == 127)) {
      throw const ApiException(
        'Die App kann diese externe Adresse nicht als API aufrufen.',
      );
    }
    return resolved;
  }

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    dynamic data,
    ResponseType? responseType,
  }) async {
    try {
      final response = await _dio.requestUri<dynamic>(
        safeUri(path),
        data: data,
        options: Options(method: method, responseType: responseType),
      );
      // Even same-origin HTTP redirects are deliberately handled by the caller: a POST must never
      // be replayed, and a login page must not silently masquerade as a successful JSON response.
      if (response.statusCode! >= 300 && response.statusCode! < 400) {
        final location = response.headers.value('location');
        if (location != null) {
          safeUri(location);
          throw AppRedirect(location);
        }
        throw const ApiException(
          'Die Serverweiterleitung enthält keine gültige Zieladresse.',
        );
      }
      return response;
    } on DioException catch (error) {
      throw ApiException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => 'Die Anfrage dauert zu lange. Bitte Verbindung prüfen und erneut versuchen.',
        DioExceptionType.badCertificate =>
          'Die verschlüsselte Verbindung konnte nicht überprüft werden.',
        _ =>
          'Keine Verbindung zu Akribos. Dein offener Entwurf bleibt erhalten.',
      });
    }
  }

  Future<ApiResult> _envelope(
    String method,
    String path, {
    dynamic data,
  }) async {
    final response = await _request(method, path, data: data);
    if (response.data is! Map || !asMap(response.data).containsKey('type')) {
      throw ApiException(
        response.statusCode == 404
            ? 'Dieser Akribos-Server unterstützt die App noch nicht. Die App-API muss zuerst bereitgestellt werden.'
            : 'Der Server hat keine gültige App-Antwort geliefert.',
        status: response.statusCode ?? 0,
      );
    }
    final result = ApiResult.fromJson(
      asMap(response.data),
      response.statusCode ?? 500,
    );
    if (result.location != null) safeUri(result.location!);
    return result;
  }

  Future<Json> loadBootstrap() async {
    final result = await _envelope('GET', '/api/app/bootstrap');
    if (!result.isSuccess) {
      throw ApiException(
        result.message,
        status: result.status,
        data: result.data,
      );
    }
    if (asInt(result.data['protocolVersion']) != 1) {
      throw const ApiException(
        'App und Server verwenden unterschiedliche API-Versionen. Bitte die App aktualisieren.',
      );
    }
    bootstrap = result.data;
    return bootstrap;
  }

  Future<Json> page(String path) async {
    safeUri(path);
    final result = await _envelope(
      'GET',
      Uri(path: '/api/app/page', queryParameters: {'path': path}).toString(),
    );
    if (result.isRedirect) throw AppRedirect(result.location!);
    if (!result.isSuccess) {
      throw ApiException(
        result.message,
        status: result.status,
        data: result.data,
      );
    }
    return result.data;
  }

  Future<ApiResult> action(String path, String action, Json fields) {
    safeUri(path);
    final encoded = _formFields(fields);
    return _envelope(
      'POST',
      Uri(
        path: '/api/app/action',
        queryParameters: {'path': path, 'action': action},
      ).toString(),
      data: {'fields': encoded},
    );
  }

  Future<ApiResult> uploadAction(
    String path,
    String action,
    Json fields,
    List<AppUpload> files,
  ) {
    safeUri(path);
    final form = FormData();
    for (final entry in _formFields(fields).entries) {
      for (final value
          in entry.value is List ? entry.value as List : [entry.value]) {
        if (value != null) {
          form.fields.add(MapEntry(entry.key, asString(value)));
        }
      }
    }
    for (final file in files) {
      form.files.add(
        MapEntry(
          file.field,
          MultipartFile.fromBytes(
            file.bytes,
            filename: file.name,
            contentType: file.contentType == null
                ? null
                : DioMediaType.parse(file.contentType!),
          ),
        ),
      );
    }
    return _envelope(
      'POST',
      Uri(
        path: '/api/app/action',
        queryParameters: {'path': path, 'action': action},
      ).toString(),
      data: form,
    );
  }

  Future<dynamic> get(String path) => send('GET', path);
  Future<Uint8List> bytes(String path) async {
    final response = await _request(
      'GET',
      path,
      responseType: ResponseType.bytes,
    );
    if (response.statusCode! >= 400) {
      throw ApiException(
        errorMessage({}, response.statusCode!),
        status: response.statusCode!,
      );
    }
    return Uint8List.fromList(List<int>.from(response.data as List));
  }

  Future<dynamic> send(String method, String path, {dynamic data}) async {
    final response = await _request(method, path, data: data);
    if (response.statusCode! >= 400) {
      throw ApiException(
        errorMessage(asMap(response.data), response.statusCode!),
        status: response.statusCode!,
        data: asMap(response.data),
      );
    }
    if (response.data is! Map && response.data is! List) {
      throw const ApiException(
        'Unerwartete Antwort vom Server. Bitte erneut laden.',
      );
    }
    return response.data;
  }

  Future<void> download(String path, {String? filename}) async {
    final response = await _request(
      'GET',
      path,
      responseType: ResponseType.bytes,
    );
    if (response.statusCode! >= 400) {
      throw ApiException(
        errorMessage({}, response.statusCode!),
        status: response.statusCode!,
      );
    }
    final mime =
        response.headers.value('content-type') ?? 'application/octet-stream';
    if (mime.contains('text/html')) {
      throw const ApiException(
        'Der Download ist nicht mehr verfügbar. Bitte Anmeldung prüfen.',
      );
    }
    final suggested = RegExp('filename="([^"]+)"')
        .firstMatch(response.headers.value('content-disposition') ?? '')
        ?.group(1);
    final name = (filename ?? suggested ?? 'akribos-export').replaceAll(
      RegExp(r'[/\\\x00-\x1f]'),
      '_',
    );
    final directory = await Directory(
      '${(await getTemporaryDirectory()).path}/akribos-exports',
    ).create(recursive: true);
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(List<int>.from(response.data as List), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mime)],
        fileNameOverrides: [name],
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
  }

  Future<void> clearSession() async {
    await _cookies.deleteAll();
    bootstrap = {};
  }

  void dispose() => _dio.close();
}
