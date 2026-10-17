import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum StoreUpdateStatus {
  idle,
  checking,
  current,
  available,
  unavailable,
  failed,
}

class InstalledAppInfo {
  const InstalledAppInfo({
    required this.version,
    required this.build,
    required this.packageName,
    required this.platform,
    this.storeCountry,
    this.storeInstallation,
    this.osVersion,
  });
  final String version, build, packageName, platform;
  final String? storeCountry, osVersion;
  final bool? storeInstallation;
}

class StoreUpdate {
  const StoreUpdate({this.version, this.build, this.storeUri});
  final String? version, build;
  final Uri? storeUri;
  String get key => '${version ?? ''}:${build ?? ''}';
}

class StoreCheckResult {
  const StoreCheckResult({required this.status, this.update, this.message});
  final StoreUpdateStatus status;
  final StoreUpdate? update;
  final String? message;
}

abstract interface class AppUpdateGateway {
  Future<InstalledAppInfo> info();
  Future<StoreCheckResult> check(InstalledAppInfo installed);
  Future<bool> openStore(InstalledAppInfo installed, StoreUpdate update);
  void dispose();
}

/// Separate unauthenticated transport: no Akribos cookies, API keys or account IDs.
class PlatformAppUpdateGateway implements AppUpdateGateway {
  PlatformAppUpdateGateway({
    MethodChannel? channel,
    Dio? storeClient,
    Future<bool> Function(Uri)? launcher,
  }) : _channel = channel ?? const MethodChannel('de.akribos.app/updates'),
       _ownsClient = storeClient == null,
       _storeClient = storeClient ?? Dio(BaseOptions(connectTimeout: _timeout)),
       _launcher =
           launcher ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final MethodChannel _channel;
  final Dio _storeClient;
  final bool _ownsClient;
  final Future<bool> Function(Uri) _launcher;
  static const _timeout = Duration(seconds: 12);
  final Set<VoidCallback> _pending = {};
  bool _disposed = false;

  Future<T> _bounded<T>(Future<T> operation, {VoidCallback? cancel}) {
    if (_disposed) {
      cancel?.call();
      return Future.error(StateError('Store gateway is disposed.'));
    }
    final result = Completer<T>();
    late final Timer timer;
    late final VoidCallback abort;
    void fail(Object error, [StackTrace? stack]) {
      if (result.isCompleted) return;
      timer.cancel();
      _pending.remove(abort);
      result.completeError(error, stack);
    }

    abort = () {
      cancel?.call();
      fail(StateError('Store gateway is disposed.'));
    };
    timer = Timer(_timeout, () {
      cancel?.call();
      fail(TimeoutException('Store request timed out.'));
    });
    _pending.add(abort);
    operation.then((value) {
      if (result.isCompleted) return;
      timer.cancel();
      _pending.remove(abort);
      result.complete(value);
    }, onError: (Object error, StackTrace stack) => fail(error, stack));
    return result.future;
  }

  @override
  Future<InstalledAppInfo> info() async {
    final data = await _bounded(
      _channel.invokeMapMethod<String, dynamic>('info'),
    );
    String requiredString(String name) {
      final value = data?[name];
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('Missing installed application metadata.');
      }
      return value;
    }

    return InstalledAppInfo(
      version: requiredString('version'),
      build: requiredString('build'),
      packageName: requiredString('packageName'),
      platform: requiredString('platform'),
      storeCountry: data?['storeCountry'] as String?,
      storeInstallation: data?['storeInstallation'] as bool?,
      osVersion: data?['osVersion'] as String?,
    );
  }

  @override
  Future<StoreCheckResult> check(InstalledAppInfo installed) async {
    if (installed.storeInstallation == false) {
      return const StoreCheckResult(
        status: StoreUpdateStatus.unavailable,
        message:
            'Für diese Installation ist keine Store-Updateprüfung verfügbar.',
      );
    }
    if (installed.platform == 'android') {
      final data = await _bounded(
        _channel.invokeMapMethod<String, dynamic>('check'),
      );
      switch (data?['status']) {
        case 'available':
          final build = data?['build'];
          final current = int.tryParse(installed.build);
          final offered = build is String ? int.tryParse(build) : null;
          if (current == null || offered == null || offered <= current) {
            throw const FormatException('Invalid Play update version.');
          }
          return StoreCheckResult(
            status: StoreUpdateStatus.available,
            update: StoreUpdate(build: build as String),
          );
        case 'current':
          return const StoreCheckResult(status: StoreUpdateStatus.current);
        case 'unavailable':
          return const StoreCheckResult(status: StoreUpdateStatus.unavailable);
        default:
          throw const FormatException('Invalid Play update response.');
      }
    }
    if (installed.platform != 'ios') {
      return const StoreCheckResult(status: StoreUpdateStatus.unavailable);
    }
    final country =
        installed.storeCountry ??
        await _bounded(_channel.invokeMethod<String>('storeCountry'));
    if (country == null || !RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      return const StoreCheckResult(
        status: StoreUpdateStatus.unavailable,
        message: 'Der App Store ist momentan nicht verfügbar. Versuche es später erneut.',
      );
    }
    final cancellation = CancelToken();
    final response = await _bounded(
      _storeClient.getUri<Object?>(
        Uri.https('itunes.apple.com', '/lookup', {
          'bundleId': installed.packageName,
          'country': country.toLowerCase(),
          'entity': 'software',
        }),
        cancelToken: cancellation,
        options: Options(
          followRedirects: false,
          responseType: ResponseType.json,
          sendTimeout: _timeout,
          receiveTimeout: _timeout,
          headers: {'Accept': 'application/json'},
        ),
      ),
      cancel: () => cancellation.cancel('Store lookup cancelled.'),
    );
    final body = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (body is! Map || body['results'] is! List) {
      throw const FormatException('Invalid App Store response.');
    }
    final matches = (body['results'] as List)
        .whereType<Map>()
        .where(
          (entry) =>
              entry['bundleId'] == installed.packageName &&
              entry['wrapperType'] == 'software',
        )
        .toList();
    if (matches.isEmpty) {
      return const StoreCheckResult(
        status: StoreUpdateStatus.unavailable,
        message: 'Akribos ist in deinem App Store momentan nicht verfügbar.',
      );
    }
    if (matches.length != 1) {
      throw const FormatException('Ambiguous App Store response.');
    }
    final entry = matches.single;
    final version = entry['version'];
    final id = entry['trackId'];
    if (version is! String || id is! int || id <= 0) {
      throw const FormatException('Missing App Store release identity.');
    }
    final comparison = compareStoreVersions(version, installed.version);
    if (comparison == null) {
      throw const FormatException('Invalid App Store version.');
    }
    if (comparison <= 0) {
      return const StoreCheckResult(status: StoreUpdateStatus.current);
    }
    final minimumOs = entry['minimumOsVersion'];
    if (minimumOs is String) {
      final osComparison = compareStoreVersions(
        installed.osVersion ?? '',
        minimumOs,
      );
      if (osComparison == null || osComparison < 0) {
        return const StoreCheckResult(
          status: StoreUpdateStatus.unavailable,
          message: 'Die neue App-Version benötigt eine neuere iOS-Version.',
        );
      }
    }
    return StoreCheckResult(
      status: StoreUpdateStatus.available,
      update: StoreUpdate(
        version: version,
        // Only Apple's validated result supplies an ID. Never trust a response URL.
        storeUri: Uri.https(
          'apps.apple.com',
          '/${country.toLowerCase()}/app/id$id',
        ),
      ),
    );
  }

  @override
  Future<bool> openStore(InstalledAppInfo installed, StoreUpdate update) async {
    if (installed.platform == 'android') {
      return await _bounded<bool?>(_channel.invokeMethod<bool>('openStore')) ??
          false;
    }
    final uri = update.storeUri;
    if (installed.platform != 'ios' ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'apps.apple.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        !RegExp(r'^/[a-z]{2}/app/id[1-9][0-9]*$').hasMatch(uri.path)) {
      return false;
    }
    return _bounded(_launcher(uri));
  }

  @override
  void dispose() {
    _disposed = true;
    for (final abort in _pending.toList()) {
      abort();
    }
    if (_ownsClient) _storeClient.close(force: true);
  }
}

/// Store marketing versions are numeric dotted components, not string ordering.
int? compareStoreVersions(String left, String right) {
  if (!RegExp(r'^\d+(\.\d+){0,3}$').hasMatch(left) ||
      !RegExp(r'^\d+(\.\d+){0,3}$').hasMatch(right)) {
    return null;
  }
  final a = left.split('.').map(int.tryParse).toList();
  final b = right.split('.').map(int.tryParse).toList();
  if (a.any((part) => part == null) || b.any((part) => part == null)) {
    return null;
  }
  for (var index = 0; index < a.length || index < b.length; index++) {
    final order = (index < a.length ? a[index]! : 0).compareTo(
      index < b.length ? b[index]! : 0,
    );
    if (order != 0) return order;
  }
  return 0;
}

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    AppUpdateGateway? gateway,
    DateTime Function()? now,
    Future<SharedPreferences> Function()? preferences,
  }) : _gateway = gateway ?? PlatformAppUpdateGateway(),
       _now = now ?? DateTime.now,
       _preferences = preferences ?? SharedPreferences.getInstance;

  final AppUpdateGateway _gateway;
  final DateTime Function() _now;
  final Future<SharedPreferences> Function() _preferences;
  static const checkInterval = Duration(hours: 12);
  static const remindInterval = Duration(hours: 24);
  static const retryInterval = Duration(minutes: 15);
  InstalledAppInfo? installed;
  StoreUpdateStatus status = StoreUpdateStatus.idle;
  StoreUpdate? update;
  String? errorMessage;
  DateTime? _lastCheck, _dismissedUntil;
  String? _dismissedKey;
  SharedPreferences? _prefs;
  Future<void>? _initializing, _checking;
  bool _disposed = false;

  bool get showNotice =>
      status == StoreUpdateStatus.available &&
      update != null &&
      (_dismissedKey != update!.key ||
          _dismissedUntil == null ||
          !_now().isBefore(_dismissedUntil!));

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      _prefs = await _preferences();
      _dismissedKey = _prefs!.getString('appUpdates.dismissedKey');
      final until = _prefs!.getInt('appUpdates.dismissedUntil');
      if (until != null) {
        _dismissedUntil = DateTime.fromMillisecondsSinceEpoch(until);
      }
    } catch (_) {
      // A preference-store error must not prevent version display or checking.
    }
    if (!_disposed) await check();
  }

  Future<void> check({bool force = false}) {
    if (_disposed) return Future.value();
    if (_checking != null) return _checking!;
    final elapsed = _lastCheck == null ? null : _now().difference(_lastCheck!);
    final interval =
        status == StoreUpdateStatus.failed ||
            status == StoreUpdateStatus.unavailable
        ? retryInterval
        : checkInterval;
    if (!force &&
        elapsed != null &&
        !elapsed.isNegative &&
        elapsed < interval) {
      // Refresh a previously dismissed notice when its reminder expires.
      notifyListeners();
      return Future.value();
    }
    return _checking = _check().whenComplete(() => _checking = null);
  }

  Future<void> _check() async {
    _lastCheck = _now();
    status = StoreUpdateStatus.checking;
    errorMessage = null;
    notifyListeners();
    try {
      // Refresh storefront/installation metadata on every real check.
      final info = await _gateway.info();
      if (_disposed) return;
      installed = info;
      notifyListeners();
      final result = await _gateway.check(info);
      if (_disposed) return;
      if (![
            StoreUpdateStatus.current,
            StoreUpdateStatus.available,
            StoreUpdateStatus.unavailable,
          ].contains(result.status) ||
          (result.status == StoreUpdateStatus.available &&
              result.update == null)) {
        throw const FormatException('Invalid update result.');
      }
      status = result.status;
      update = result.update;
      errorMessage =
          result.message ??
          (status == StoreUpdateStatus.unavailable
              ? 'Für diese Installation ist die Store-Updateprüfung momentan nicht verfügbar.'
              : null);
    } catch (_) {
      if (_disposed) return;
      status = StoreUpdateStatus.failed;
      update = null;
      errorMessage = 'Updates konnten nicht geprüft werden. Prüfe deine Verbindung und versuche es erneut.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> dismiss() async {
    if (_disposed || update == null) return;
    final key = _dismissedKey = update!.key;
    final until = _dismissedUntil = _now().add(remindInterval);
    notifyListeners();
    try {
      final prefs = _prefs ??= await _preferences();
      await prefs.setString('appUpdates.dismissedKey', key);
      await prefs.setInt(
        'appUpdates.dismissedUntil',
        until.millisecondsSinceEpoch,
      );
    } catch (_) {
      // The in-memory dismissal still works until the app is closed.
    }
  }

  Future<bool> openStore() async {
    final info = installed;
    final offered = update;
    if (_disposed ||
        info == null ||
        offered == null ||
        status != StoreUpdateStatus.available) {
      return false;
    }
    try {
      return await _gateway.openStore(info, offered);
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _gateway.dispose();
    super.dispose();
  }
}
