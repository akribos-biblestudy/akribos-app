import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api_client.dart';
import 'core/app_scope.dart';
import 'core/app_updates.dart';
import 'core/deep_link.dart';
import 'features/account/account_screen.dart';
import 'features/account/auth_screen.dart';
import 'features/collections/collections_screen.dart';
import 'features/documents/documents_screen.dart';
import 'features/help/help_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/reader/offline_reader_screen.dart';
import 'features/reader/offline_resource_manager.dart';
import 'features/reader/offline_resource_store.dart';
import 'features/reader/offline_resources_screen.dart';
import 'features/reader/reader_local_store.dart';
import 'features/reader/reader_controller.dart';
import 'features/reader/books.dart';
import 'theme/akribos_theme.dart';
import 'widgets/floating_navigation.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';
import 'widgets/common.dart';
import 'widgets/app_update_notice.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final name in ['OFL-Akribos-Text', 'OFL-Noto-Sans-Hebrew']) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/fonts/$name.txt'));
    }
  });
  runApp(const AkribosApp());
}

class AkribosApp extends StatefulWidget {
  const AkribosApp({
    super.key,
    this.api,
    this.enableLinks = true,
    this.updates,
  });
  final AppApi? api;
  final bool enableLinks;
  final AppUpdateController? updates;
  @override
  State<AkribosApp> createState() => _AkribosAppState();
}

class _AkribosAppState extends State<AkribosApp> with WidgetsBindingObserver {
  late final bool _ownsUpdates;
  late final AppUpdateController _updates =
      widget.updates ?? AppUpdateController();
  late final AppApi _api =
      widget.api ??
      AppApi(
        server: const String.fromEnvironment(
          'AKRIBOS_SERVER',
          defaultValue: 'https://akribos.de',
        ),
      );
  final _shellKey = GlobalKey<_AppShellState>();
  ThemeMode _theme = ThemeMode.system;
  bool _eInk = false;
  @override
  void initState() {
    super.initState();
    _ownsUpdates = widget.updates == null;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_updates.initialize());
    _loadTheme();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_updates.check());
  }

  Future<void> _loadTheme() async {
    final preferences = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _theme = ThemeMode.values.firstWhere(
          (mode) => mode.name == preferences.getString('theme'),
          orElse: () => ThemeMode.system,
        );
        _eInk = preferences.getBool('eInk') ?? false;
      });
    }
  }

  void _setTheme(ThemeMode mode) {
    setState(() => _theme = mode);
    SharedPreferences.getInstance().then(
      (p) => p.setString('theme', mode.name),
    );
    if (mode != ThemeMode.system) {
      _api.send('POST', '/api/theme', data: {'theme': mode.name}).catchError((
        Object error,
      ) {
        final context = _shellKey.currentContext;
        if (context != null && context.mounted) showError(context, error);
        return <String, dynamic>{};
      });
    }
  }

  void _setEInk(bool enabled) {
    setState(() => _eInk = enabled);
    SharedPreferences.getInstance().then((p) => p.setBool('eInk', enabled));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsUpdates) _updates.dispose();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Akribos',
    debugShowCheckedModeBanner: false,
    locale: const Locale('de'),
    supportedLocales: const [Locale('de'), Locale('en')],
    localizationsDelegates: const [...GlobalMaterialLocalizations.delegates],
    theme: appTheme(Brightness.light, eInk: _eInk),
    darkTheme: appTheme(Brightness.dark),
    themeMode: _eInk ? ThemeMode.light : _theme,
    builder: (context, child) => AppScope(
      api: _api,
      open: (path) async {
        await _shellKey.currentState?._open(path);
      },
      refreshSession: () async {
        await _shellKey.currentState?._refreshSession();
      },
      onAuthenticationChanged: () async {
        await _shellKey.currentState?._authenticationChanged();
      },
      setNavigationGuard: (owner, guard) =>
          _shellKey.currentState?._setGuard(owner, guard),
      setTheme: _setTheme,
      themeMode: _theme,
      eInk: _eInk,
      setEInk: _setEInk,
      updates: _updates,
      openUpdateStore: () async {
        await _shellKey.currentState?._openUpdateStore();
      },
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: _eInk || MediaQuery.of(context).disableAnimations,
          highContrast: _eInk || MediaQuery.of(context).highContrast,
        ),
        child: child!,
      ),
    ),
    home: _AppShell(
      key: _shellKey,
      api: _api,
      themeMode: _theme,
      setTheme: _setTheme,
      enableLinks: widget.enableLinks,
      eInk: _eInk,
      setEInk: _setEInk,
      updates: _updates,
    ),
  );
}

ThemeData appTheme(Brightness brightness, {bool eInk = false}) =>
    buildAkribosTheme(brightness, eInk: eInk);

class _AppShell extends StatefulWidget {
  const _AppShell({
    super.key,
    required this.api,
    required this.themeMode,
    required this.setTheme,
    required this.enableLinks,
    required this.eInk,
    required this.setEInk,
    required this.updates,
  });
  final AppApi api;
  final ThemeMode themeMode;
  final void Function(ThemeMode) setTheme;
  final bool enableLinks, eInk;
  final void Function(bool) setEInk;
  final AppUpdateController updates;
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  String _path = '/';
  final List<String> _history = [];
  final _readerController = ReaderController();
  final _branchPaths = <int, String>{
    0: '/',
    1: '/search',
    2: notesLibraryPath,
    3: '/menu',
  };
  final _visited = <int>{0};
  final _deferredPaths = <int, String>{};
  int _readerRevision = 0;
  final _guards = <int, Map<Object, Future<bool> Function()>>{};
  final _guardSetters =
      <int, void Function(Object, Future<bool> Function()?)>{};
  final _branchOpeners = <int, Future<void> Function(String)>{};
  final _branchEpochs = List<int>.filled(4, 0);
  int _activeBranch = 0, _navigationRequest = 0, _bootstrapGeneration = 0;
  Json _acceptedBootstrap = {};
  ReaderSearchResource? _searchResource;
  String _lastSearchPath = '/search';
  int? _readerFontScale;
  bool _guardFramePending = false;
  String? _sessionOwner;
  String _notesChapter = '';
  bool _notesChapterEnabled = true;
  String _notesPreferenceKey(String owner) =>
      'akribos.notes.chapter.${Uri.encodeComponent(widget.api.origin.origin)}.${Uri.encodeComponent(owner)}';

  Future<void> _setNotesChapterEnabled(bool enabled) async {
    if (!await _flushBranch() || !mounted) return;
    final owner = _sessionOwner;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_notesPreferenceKey(owner ?? ''), enabled);
      if (!mounted || owner != _sessionOwner) return;
      setState(() => _notesChapterEnabled = enabled);
      final params = {...Uri.parse(_path).queryParameters}
        ..remove('passage')
        ..remove('book')
        ..remove('resource')
        ..remove('page');
      await _open(Uri(path: '/notes', queryParameters: params).toString());
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void>? _refreshing;
  bool get _hasGuard => _guards[_activeBranch]?.isNotEmpty ?? false;
  bool _ready = false, _started = false;
  Object? _error;
  List<Json>? _offlinePackages;
  OfflineResourceManager? _offlineManager;
  OfflineResourceStore? _offlinePositionStore;
  Json? _offlinePosition;
  double _offlineFontScale = 1;
  bool _offlineVersePerLine = false;
  Future<void>? _offlinePositionSaving;
  (String, Json)? _offlinePositionDraft;
  bool _offlineRightsValidated = false;
  bool _offlineRechecking = false;
  OverlayEntry? _offlineCheckOverlay;
  Future<void>? _offlineRoutesClosing;
  StreamSubscription<Uri>? _links;
  String? _pendingLink;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enableLinks) {
      _links = AppLinks().uriLinkStream.listen(
        (uri) {
          final path = appLinkPath(uri, widget.api.origin);
          if (path == null) return;
          if (_ready) {
            _open(path);
          } else {
            _pendingLink = path;
          }
        },
        onError: (Object error) {
          if (mounted) {
            showError(context, 'Der App-Link konnte nicht geöffnet werden.');
          }
        },
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _start();
    }
  }

  Future<void> _start() async {
    if (_offlinePackages != null) {
      await _resumeOffline(manual: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _error = null;
      _offlinePackages = null;
      _ready = false;
    });
    try {
      await _refreshSession();
      if (mounted) {
        setState(() => _ready = true);
        if (_pendingLink != null) {
          final path = _pendingLink!;
          _pendingLink = null;
          await _open(path);
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _saveOfflinePosition() async {
    final draft = _offlinePositionDraft;
    final store = _offlinePositionStore;
    if (draft == null || store == null) return;
    await store.writePosition(draft.$1, draft.$2);
    if (identical(_offlinePositionDraft, draft)) _offlinePositionDraft = null;
  }

  Future<void> _flushOfflinePosition() async {
    try {
      await _offlinePositionSaving;
    } catch (_) {
      // The latest draft is retried explicitly below, including after a prior
      // autosave failed. A failed retry remains available for the next attempt.
    }
    while (_offlinePositionDraft != null && _offlinePositionStore != null) {
      await _saveOfflinePosition();
    }
  }

  Future<void> _openOffline() async {
    final generation = _bootstrapGeneration;
    final sessionOwner = _sessionOwner;
    void checkSession() {
      if (!mounted ||
          generation != _bootstrapGeneration ||
          sessionOwner != _sessionOwner) {
        throw const ApiException('Die Anmeldung hat sich geändert.');
      }
    }

    try {
      if (_ready && _offlineManager != null) {
        try {
          await _offlineManager!.reconcile();
        } on ApiException catch (error) {
          if (!error.connectionFailure) rethrow;
        }
        checkSession();
      }
      final identityStore = OfflineIdentityStore(origin: widget.api.origin);
      final identity = await identityStore.read();
      checkSession();
      final fingerprint = await widget.api.offlineSessionFingerprint();
      checkSession();
      if (identity == null ||
          identity['fingerprint'] != fingerprint ||
          (_ready &&
              (sessionOwner?.isEmpty == true ? null : sessionOwner) !=
                  identity['owner'])) {
        throw const ApiException(
          'Die Offline-Anmeldung stimmt nicht mehr. Bitte zuerst online anmelden.',
        );
      }
      final owner = identity['owner'] as String?;
      final store = OfflineResourceStore(
        origin: widget.api.origin,
        userId: owner,
      );
      final packages = <Json>[];
      for (final id in await store.ids()) {
        checkSession();
        final package = await store.read(id);
        checkSession();
        if (package != null) packages.add(package);
      }
      if (packages.isEmpty) {
        throw const ApiException('Es sind keine Werke offline gespeichert.');
      }
      final position = await store.readPosition();
      checkSession();
      final preferences = await ReaderLocalStore(
        origin: widget.api.origin,
        userId: owner,
      ).read();
      checkSession();
      // Authentication can change while encrypted storage is being read. Recheck
      // both the marker and the cookie before presenting any loaded text.
      final currentIdentity = await identityStore.read();
      checkSession();
      final currentFingerprint = await widget.api.offlineSessionFingerprint();
      checkSession();
      if (currentIdentity == null ||
          currentIdentity['owner'] != owner ||
          currentIdentity['fingerprint'] != fingerprint ||
          currentFingerprint != fingerprint) {
        throw const ApiException('Die Offline-Anmeldung hat sich geändert.');
      }
      setState(() {
        _offlinePositionStore = store;
        _offlinePositionDraft = null;
        _offlinePosition = position;
        _offlineFontScale = asInt(identity['fontScale'], 100) / 100;
        _offlineVersePerLine = preferences?['versePerLine'] == true;
        _offlinePackages = packages;
      });
    } catch (error) {
      if (mounted &&
          generation == _bootstrapGeneration &&
          sessionOwner == _sessionOwner) {
        showError(context, error);
      }
    }
  }

  Future<bool> _syncOfflineIdentity(String? owner, int generation) async {
    final identityStore = OfflineIdentityStore(origin: widget.api.origin);
    Json? old;
    try {
      if (generation != _bootstrapGeneration ||
          !widget.api.bootstrap.containsKey('user')) {
        return false;
      }
      old = await identityStore.read();
      if (generation != _bootstrapGeneration) return false;
      if (old != null && old['owner'] != owner) {
        await identityStore.clear();
        if (generation != _bootstrapGeneration) return false;
        await OfflineResourceStore(
          origin: widget.api.origin,
          userId: old['owner'] as String?,
        ).clear();
      }
      if (generation != _bootstrapGeneration) return false;
      final manager = OfflineResourceManager(api: widget.api, userId: owner);
      // When the offline reader is mounted, contact the server before waiting
      // on local storage: a stalled position write must not prevent the rights
      // request from starting. The reader remains covered while this runs.
      if (_offlinePackages != null || (await manager.store.ids()).isNotEmpty) {
        await manager.reconcile();
      }
      final fingerprint = await widget.api.offlineSessionFingerprint();
      if (generation != _bootstrapGeneration) return false;
      if (owner != null && fingerprint == null) {
        await identityStore.clear();
        return false;
      }
      await identityStore.write(
        owner,
        fingerprint,
        fontScale: asInt(widget.api.bootstrap['readerFontScale'], 100),
      );
      return generation == _bootstrapGeneration;
    } catch (error) {
      if (generation != _bootstrapGeneration) return false;
      // A transient connection failure does not revoke a previously confirmed
      // identity. Keep it only if both the account and cookie still match.
      if (error is ApiException &&
          error.connectionFailure &&
          old != null &&
          old['owner'] == owner) {
        try {
          final fingerprint = await widget.api.offlineSessionFingerprint();
          if (generation != _bootstrapGeneration) return false;
          if (old['fingerprint'] == fingerprint) return false;
        } catch (_) {
          if (generation != _bootstrapGeneration) return false;
        }
      }
      // Identity changes, invalid responses and storage errors fail closed.
      try {
        if (generation == _bootstrapGeneration) await identityStore.clear();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _trackRefresh(Future<void> operation) {
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_refreshing, tracked)) _refreshing = null;
    });
    _refreshing = tracked;
    return tracked;
  }

  Future<void> _refreshSession() =>
      _refreshing ?? _trackRefresh(_loadSession(_bootstrapGeneration));

  bool get _isAuthPath =>
      RegExp(r'^/(login|logout|register|password-reset)(/|$)')
          .hasMatch(Uri.parse(_path).path);

  void _invalidatePrivateBranches({bool preserveAuthForm = false}) {
    final preserve = preserveAuthForm && _activeBranch == 3 && _isAuthPath;
    for (var branch = 0; branch < 4; branch++) {
      if (!preserve || branch != 3) _branchEpochs[branch]++;
    }
    _navigationRequest++;
    _history.clear();
    _searchResource = null;
    _lastSearchPath = '/search';
    _notesChapter = '';
    _notesChapterEnabled = true;
    _guards.clear();
    _deferredPaths.clear();
    _branchOpeners.clear();
    _branchPaths.addAll({
      0: '/',
      1: '/search',
      2: notesLibraryPath,
      3: '/menu',
    });
    _branchPaths[_activeBranch] = _path;
    _visited
      ..clear()
      ..add(_activeBranch);
    _readerController.update(tabCount: 0, activeTitle: '');
    _offlineManager = null;
    _offlinePackages = null;
    _offlinePositionStore = null;
    _offlinePositionDraft = null;
    _offlineRechecking = false;
    _removeOfflineCheckOverlay();
  }

  void _removeOfflineCheckOverlay() {
    final entry = _offlineCheckOverlay;
    final closing = _offlineRoutesClosing;
    _offlineCheckOverlay = null;
    _offlineRoutesClosing = null;
    if (entry != null) {
      void remove() {
        entry.remove();
        entry.dispose();
      }

      // Navigator.popUntil starts reverse animations rather than disposing
      // routes immediately. Keep protecting their contents until every
      // transition has actually finished, including after an account change.
      if (closing == null) {
        remove();
      } else {
        unawaited(closing.whenComplete(remove));
      }
    }
  }

  Future<void> _authenticationChanged() {
    final precedingRefresh = _refreshing;
    final generation = ++_bootstrapGeneration;
    widget.api.invalidateOfflineIdentity();
    // A successful auth response is the boundary, even if the next request fails.
    _acceptedBootstrap = {};
    widget.api.bootstrap = {};
    _sessionOwner = null;
    _readerFontScale = null;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _invalidatePrivateBranches(preserveAuthForm: true));
    return _trackRefresh(() async {
      try {
        await precedingRefresh;
      } catch (_) {
        // The fresh request below determines the new session's result.
      }
      try {
        final identity = OfflineIdentityStore(origin: widget.api.origin);
        final old = await identity.read();
        await identity.clear();
        if (old != null) {
          await OfflineResourceStore(
            origin: widget.api.origin,
            userId: old['owner'] as String?,
          ).clear();
        }
      } catch (_) {}
      if (!mounted || generation != _bootstrapGeneration) return;
      await _loadSession(generation);
    }());
  }

  Future<void> _loadSession(int generation) async {
    _offlineRightsValidated = false;
    await widget.api.initializeReader(MediaQuery.sizeOf(context).width);
    final data = await widget.api.loadBootstrap();
    if (generation != _bootstrapGeneration) {
      widget.api.bootstrap = _acceptedBootstrap;
      return;
    }
    if (!mounted) return;
    final owner = asString(asMap(data['user'])['id']);
    final ownerChanged = _sessionOwner != null && _sessionOwner != owner;
    final preferences = await SharedPreferences.getInstance();
    if (!mounted || generation != _bootstrapGeneration) return;
    final notesChapterEnabled =
        preferences.getBool(_notesPreferenceKey(owner)) ?? true;
    final fontScale = asInt(data['readerFontScale'], 100);
    var refreshReader =
        !ownerChanged &&
        _readerFontScale != null &&
        _readerFontScale != fontScale;
    if (refreshReader && _visited.contains(0)) {
      // A preference refresh must not discard outstanding Reader changes.
      refreshReader = await _readerController.flush();
      if (!mounted || generation != _bootstrapGeneration) return;
    }
    _acceptedBootstrap = data;
    if (ownerChanged) Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      if (ownerChanged) {
        _invalidatePrivateBranches(preserveAuthForm: true);
      } else if (refreshReader) {
        _readerRevision++;
        // Restore the newly saved local position, not the last explicit link.
        _branchPaths[0] = '/';
        if (_activeBranch == 0) _path = '/';
      }
      _sessionOwner = owner;
      _notesChapterEnabled = notesChapterEnabled;
      if (_readerFontScale == null || ownerChanged || refreshReader) {
        _readerFontScale = fontScale;
      }
    });
    final verified = await _syncOfflineIdentity(
      owner.isEmpty ? null : owner,
      generation,
    );
    if (generation == _bootstrapGeneration) _offlineRightsValidated = verified;
  }

  Future<void> _reloadReaderAfterSettings() async {
    final generation = _bootstrapGeneration;
    if (!await _readerController.flush()) {
      throw const ApiException(
        'Die aktuelle Lesestelle konnte nicht gespeichert werden.',
      );
    }
    if (!mounted || generation != _bootstrapGeneration) return;
    setState(() {
      _readerRevision++;
      _branchPaths[0] = '/';
      if (_activeBranch == 0) _path = '/';
    });
  }

  int _branchFor(String path) {
    if (_reader(path)) return 0;
    if (path.startsWith('/search') || RegExp(r'^/[GH]\d').hasMatch(path)) {
      return 1;
    }
    if (path.startsWith('/notes') || path.startsWith('/sermons')) return 2;
    return 3;
  }

  Future<bool> _flushBranch() async {
    final guards = List<Future<bool> Function()>.of(
      _guards[_activeBranch]?.values ?? const [],
    );
    for (final guard in guards) {
      if (!await guard()) return false;
    }
    return true;
  }

  bool _openingUpdateStore = false;
  Future<void> _openUpdateStore() async {
    if (_openingUpdateStore) return;
    _openingUpdateStore = true;
    final request = _navigationRequest;
    final generation = _bootstrapGeneration;
    try {
      if (!await _flushBranch()) return;
      if (!mounted ||
          request != _navigationRequest ||
          generation != _bootstrapGeneration) {
        return;
      }
      // The retained Reader also needs its latest local position saved when
      // the current screen is a note, the account or Settings.
      if (!await _readerController.flush()) {
        throw const ApiException(
          'Die aktuelle Lesestelle konnte nicht gespeichert werden.',
        );
      }
      if (!mounted ||
          request != _navigationRequest ||
          generation != _bootstrapGeneration) {
        return;
      }
      if (!await widget.updates.openStore() && mounted) {
        showError(
          context,
          'Der Store konnte nicht geöffnet werden. Bitte versuche es erneut.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      _openingUpdateStore = false;
    }
  }

  bool _reader(String path) {
    final p = Uri.parse(path).path;
    return p == '/' ||
        !RegExp(
          r'^/(search|G\d|H\d|notes|sermons|lists|l/|invites|account|login|logout|register|password-reset|admin|help|menu|settings|offline|workspaces|datenschutz|impressum|about|api)',
        ).hasMatch(p);
  }

  Future<void> _open(
    String path, {
    bool record = true,
    bool preserveReader = false,
  }) async {
    try {
      final uri = widget.api.safeUri(path);
      var target = mobileDocumentPath(
        '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}${uri.hasFragment ? '#${uri.fragment}' : ''}',
      );
      if (Uri.parse(target).path == '/workspaces' ||
          Uri.parse(target).path.startsWith('/workspaces/')) {
        target = _branchPaths[0]!;
        preserveReader = true;
      }
      final request = ++_navigationRequest;
      if (!await _flushBranch()) return;
      if (!mounted || request != _navigationRequest) return;
      final isSearch = Uri.parse(target).path == '/search';
      ReaderSearchResource? searchResource;
      if (isSearch) {
        // A tab activation may have completed during the flush. Read the
        // controller after that Reader build, never from the saved workspace.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || request != _navigationRequest) return;
        searchResource = _readerController.activeResource;
        final parameters = {...Uri.parse(target).queryParameters};
        if (_searchResource?.id != searchResource?.id) {
          parameters.remove('book');
          parameters.remove('page');
        }
        parameters.remove('resource');
        if (searchResource != null) parameters['resource'] = searchResource.id;
        target = Uri(
          path: '/search',
          queryParameters: parameters.isEmpty ? null : parameters,
        ).toString();
      }
      if (Uri.parse(target).path == '/notes') {
        final reference = _readerController.reference;
        final chapter =
            asInt(reference['book']) > 0 && asInt(reference['chapter']) > 0
            ? referenceLabel({
                'book': reference['book'],
                'chapter': reference['chapter'],
              })
            : '';
        final params = {...Uri.parse(target).queryParameters};
        final explicitPassage = params['passage'];
        if (_notesChapterEnabled &&
            chapter.isNotEmpty &&
            (explicitPassage == null ||
                explicitPassage == _notesChapter ||
                explicitPassage == chapter)) {
          params['passage'] = chapter;
          params.remove('book');
          // Chapter notes include canonical anchors and all translations.
          params.remove('resource');
          target = Uri(path: '/notes', queryParameters: params).toString();
        }
        _notesChapter = chapter;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        if (record && _path != target) {
          _history.add(_path);
          if (_history.length > 100) _history.removeAt(0);
        }
        if (isSearch) {
          _searchResource = searchResource;
          _lastSearchPath = target;
        }
        _path = target;
        _activeBranch = _branchFor(target);
        if (_activeBranch == 0 && !preserveReader) _readerRevision++;
        _deferredPaths.remove(_activeBranch);
        _branchPaths[_activeBranch] = target;
        _visited.add(_activeBranch);
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _back() async {
    if (_history.isNotEmpty) {
      final target = _history.last, previous = _path;
      await _open(target, record: false);
      if (_path != previous) _history.removeLast();
    } else if (await _flushBranch()) {
      SystemNavigator.pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _offlinePackages != null) {
      unawaited(_resumeOffline());
      return;
    }
    if (state == AppLifecycleState.resumed && _ready) {
      _refreshSession().catchError((Object error) {
        if (mounted) showError(context, error);
      });
    }
  }

  Future<void> _resumeOffline({bool manual = false}) async {
    if (_offlineRechecking) return;
    final generation = _bootstrapGeneration;
    final packages = _offlinePackages;
    final store = _offlinePositionStore;
    // Notes and word-study sheets are Navigator routes above the reader. Close
    // them and cover the root overlay first: their reverse animations must not
    // expose revoked text while the network and storage checks are pending.
    final overlay = Overlay.of(context, rootOverlay: true);
    final surface = Theme.of(context).colorScheme.surface;
    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: BlockSemantics(
          key: const ValueKey('offline-rights-overlay'),
          child: Material(
            color: surface,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Offline-Freigaben werden geprüft …'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _offlineCheckOverlay = entry;
    overlay.insert(entry);
    final closing = <Future<void>>[];
    Navigator.of(context, rootNavigator: true).popUntil((route) {
      if (route.isFirst) return true;
      if (route is TransitionRoute) {
        closing.add(route.completed.then<void>((_) {}));
      }
      return false;
    });
    _offlineRoutesClosing = Future.wait(closing);
    setState(() => _offlineRechecking = true);
    // Start the server check even if the storage write is slow or fails.
    // While either operation is pending the mounted reader is covered and
    // excluded from accessibility until its grants have been revalidated.
    final refresh = _refreshSession().then<Object?>(
      (_) => null,
      onError: (Object error, StackTrace _) => error,
    );
    Object? positionError;
    try {
      await _flushOfflinePosition().timeout(const Duration(seconds: 5));
    } catch (error) {
      positionError = error;
    }
    try {
      final refreshError = await refresh;
      if (refreshError != null) throw refreshError;
      if (!mounted || generation != _bootstrapGeneration) return;
      // A failed position write must never block the server rights check. Only
      // keep the reader mounted when this exact account and every displayed
      // package have just been revalidated successfully.
      if (positionError != null &&
          _offlineRightsValidated &&
          packages != null &&
          store != null &&
          store.userId ==
              (_sessionOwner?.isEmpty == true ? null : _sessionOwner)) {
        try {
          final available = (await store.ids()).toSet();
          if (!mounted || generation != _bootstrapGeneration) return;
          if (packages.every(
            (package) =>
                available.contains(asString(asMap(package['resource'])['id'])),
          )) {
            showError(
              context,
              'Die Offline-Lesestelle konnte nicht gespeichert werden: $positionError',
            );
            return;
          }
        } catch (_) {
          // An unreadable catalogue cannot establish offline rights.
        }
      }
      if (!mounted || generation != _bootstrapGeneration) return;
      setState(() {
        _ready = true;
        _offlinePackages = null;
      });
      if (positionError != null) {
        showError(
          context,
          'Die Offline-Lesestelle konnte nicht gespeichert werden: $positionError',
        );
      }
    } catch (error) {
      if (!mounted || generation != _bootstrapGeneration) return;
      if (error is ApiException && error.connectionFailure) {
        if (positionError != null) {
          showError(
            context,
            'Die Offline-Lesestelle konnte nicht gespeichert werden: $positionError',
          );
        } else if (manual) {
          showError(context, error);
        }
      } else {
        setState(() => _offlinePackages = null);
        showError(context, error);
      }
    } finally {
      if (identical(_offlineCheckOverlay, entry)) _removeOfflineCheckOverlay();
      if (mounted && generation == _bootstrapGeneration) {
        setState(() => _offlineRechecking = false);
      }
    }
  }

  @override
  void dispose() {
    _removeOfflineCheckOverlay();
    _links?.cancel();
    _readerController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  int get _selected => switch (_activeBranch) {
    0 => 0,
    1 => 1,
    2 => 3,
    _ => 4,
  };

  Future<void> _select(int index) async {
    if (index == 2 || (index == 0 && _activeBranch == 0)) {
      if (_activeBranch != 0) {
        await _open(
          _deferredPaths.remove(0) ?? _branchPaths[0]!,
          preserveReader: true,
        );
      }
      if (!mounted || _activeBranch != 0) return;
      await WidgetsBinding.instance.endOfFrame;
      await _readerController.showTabs();
      return;
    }
    if (index == 1) {
      await _open(_lastSearchPath, preserveReader: true);
      return;
    }
    final branch = switch (index) {
      0 => 0,
      1 => 1,
      3 => 2,
      _ => 3,
    };
    final target = branch == 3
        ? '/menu'
        : branch == 2
        ? notesLibraryPath
        : (_deferredPaths.remove(branch) ?? _branchPaths[branch]!);
    if (_path != target || _activeBranch != branch) {
      await _open(target, preserveReader: true);
    }
  }

  void _setGuard(Object owner, Future<bool> Function()? guard) =>
      _setBranchGuard(_activeBranch, owner, guard);

  void _setBranchGuard(
    int branch,
    Object owner,
    Future<bool> Function()? guard,
  ) {
    final guards = _guards.putIfAbsent(branch, () => {});
    final hadGuard = guards.isNotEmpty;
    if (guard == null) {
      guards.remove(owner);
    } else {
      guards[owner] = guard;
    }
    if (hadGuard != guards.isNotEmpty && !_guardFramePending) {
      _guardFramePending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _guardFramePending = false;
        if (mounted) setState(() {});
      });
    }
  }

  Widget _branchScreen(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    final path = _branchPaths[index]!;
    final epoch = _branchEpochs[index];
    return AppScope(
      key: ValueKey('branch:$index:$epoch'),
      api: widget.api,
      open: _branchOpeners.putIfAbsent(
        index,
        () => (path) async {
          if (!mounted || epoch != _branchEpochs[index]) return;
          // Keep late redirects for the next visit without stealing the current screen.
          if (_activeBranch == index) {
            await _open(path);
          } else if (mounted) {
            widget.api.safeUri(path);
            setState(() {
              _deferredPaths[index] = path;
              _visited.remove(index);
            });
          }
        },
      ),
      refreshSession: _refreshSession,
      onAuthenticationChanged: _authenticationChanged,
      setNavigationGuard: _guardSetters.putIfAbsent(
        index,
        () =>
            (owner, guard) => _setBranchGuard(index, owner, guard),
      ),
      setTheme: widget.setTheme,
      themeMode: widget.themeMode,
      eInk: widget.eInk,
      setEInk: widget.setEInk,
      notesChapter: _notesChapter,
      notesChapterEnabled: _notesChapterEnabled,
      setNotesChapterEnabled: _setNotesChapterEnabled,
      updates: widget.updates,
      openUpdateStore: _openUpdateStore,
      child: TickerMode(
        enabled: _activeBranch == index,
        child: KeyedSubtree(
          key: ValueKey(index == 0 ? 'reader:$_readerRevision' : path),
          child: index == 0
              ? ReaderScreen(
                  path: path,
                  controller: _readerController,
                  active: _activeBranch == 0,
                )
              : _screen(context, path),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_offlinePackages != null) {
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              AbsorbPointer(
                absorbing: _offlineRechecking,
                child: ExcludeSemantics(
                  excluding: _offlineRechecking,
                  child: Column(
                    children: [
                      TextButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.wifi),
                        label: const Text('Online erneut verbinden'),
                      ),
                      Expanded(
                        child: OfflineReaderScreen(
                          packages: _offlinePackages!,
                          eInk: widget.eInk,
                          initialResourceId:
                              _offlinePosition?['resourceId'] as String?,
                          initialReference:
                              _offlinePosition?['reference'] is Map
                              ? asMap(_offlinePosition!['reference'])
                              : null,
                          fontScale: _offlineFontScale,
                          versePerLine: _offlineVersePerLine,
                          onPositionChanged: (resource, reference) {
                            final store = _offlinePositionStore;
                            if (store == null) return;
                            _offlinePositionDraft = (
                              resource,
                              Map.of(reference),
                            );
                            final task = _saveOfflinePosition();
                            task.catchError((Object error) {
                              if (mounted) {
                                showError(
                                  this.context,
                                  'Die Offline-Lesestelle konnte nicht gespeichert werden: $error',
                                );
                              }
                            });
                            _offlinePositionSaving = task;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_offlineRechecking)
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Offline-Freigaben werden geprüft …'),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final user = asMap(widget.api.bootstrap['user']);
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _history.isEmpty && !_hasGuard,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          titleSpacing: 16,
          title: Semantics(
            label: 'Akribos – Lesen',
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _ready
                  ? () => _open(_branchPaths[0]!, preserveReader: true)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Image.asset(
                  'assets/brand/wordmark.png',
                  width: 108,
                  height: 29,
                  fit: BoxFit.contain,
                  color: widget.eInk ? Colors.black : null,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
          leading: _history.isNotEmpty && _activeBranch != 0
              ? IconButton(
                  tooltip: 'Zurück',
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back, size: 22),
                )
              : null,
          actions: [
            IconButton(
              tooltip: user.isEmpty ? 'Anmelden' : 'Konto',
              onPressed: _ready
                  ? () => _open(user.isEmpty ? '/login' : '/account')
                  : null,
              icon: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline_rounded, size: 19),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: !_ready
              ? _startup(context)
              : Column(
                  children: [
                    const AppUpdateNotice(),
                    Expanded(
                      child: IndexedStack(
                        index: _activeBranch,
                        children: List.generate(4, _branchScreen),
                      ),
                    ),
                  ],
                ),
        ),
        bottomNavigationBar: _ready
            ? ListenableBuilder(
                listenable: _readerController,
                builder: (context, _) => FloatingNavigationBar(
                  selectedIndex: _selected,
                  onSelected: _select,
                  eInk: widget.eInk,
                  destinations: [
                    const FloatingNavigationDestination(
                      label: 'Lesen',
                      icon: Icon(Icons.menu_book_outlined),
                      selectedIcon: Icon(Icons.menu_book_rounded),
                    ),
                    const FloatingNavigationDestination(
                      label: 'Suchen',
                      icon: Icon(Icons.search_rounded),
                    ),
                    FloatingNavigationDestination(
                      label: 'Tabs',
                      semanticLabel:
                          'Tabs, ${_readerController.tabCount} geöffnet',
                      icon: _TabCountIcon(count: _readerController.tabCount),
                    ),
                    const FloatingNavigationDestination(
                      label: 'Notizen',
                      icon: Icon(Icons.edit_note_outlined),
                      selectedIcon: Icon(Icons.edit_note_rounded),
                    ),
                    const FloatingNavigationDestination(
                      label: 'Mehr',
                      icon: Icon(Icons.more_horiz_rounded),
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }

  Widget _startup(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories,
            size: 60,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            _error == null ? 'Akribos wird geöffnet …' : _error.toString(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_error == null)
            const CircularProgressIndicator()
          else
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          if (_error is ApiException &&
              (_error as ApiException).connectionFailure)
            TextButton.icon(
              onPressed: _openOffline,
              icon: const Icon(Icons.offline_bolt_outlined),
              label: const Text('Offline lesen'),
            ),
          const SizedBox(height: 12),
          Text(
            widget.api.origin.origin,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
  Widget _screen(BuildContext context, String path) {
    final route = Uri.parse(path).path;
    if (route == '/menu') return _menu(context);
    if (route == '/settings') {
      return SettingsScreen(
        readerController: _readerController,
        onHighlightStylesChanged: _reloadReaderAfterSettings,
      );
    }
    if (route == '/offline') {
      final id = asString(asMap(widget.api.bootstrap['user'])['id']);
      final manager = _offlineManager ??= OfflineResourceManager(
        api: widget.api,
        userId: id.isEmpty ? null : id,
      );
      return OfflineResourcesScreen(
        manager: manager,
        onReadOffline: _openOffline,
      );
    }
    if (route.startsWith('/notes') || route.startsWith('/sermons')) {
      return DocumentsScreen(path: path);
    }
    if (route.startsWith('/lists') ||
        route.startsWith('/l/') ||
        route.startsWith('/invites/')) {
      return CollectionsScreen(path: path);
    }
    if (route.startsWith('/account')) return AccountScreen(path: path);
    if (route.startsWith('/login') ||
        route.startsWith('/logout') ||
        route.startsWith('/register') ||
        route.startsWith('/password-reset')) {
      return AuthScreen(path: path);
    }
    if (route.startsWith('/help')) return HelpScreen(path: path);
    if (['/about', '/impressum', '/datenschutz', '/api'].contains(route) ||
        route.startsWith('/api/')) {
      return InformationScreen(path: path);
    }
    if (route == '/search' || RegExp(r'^/[GH]\d').hasMatch(route)) {
      return SearchScreen(path: path, resource: _searchResource);
    }
    return ReaderScreen(path: path);
  }

  Widget _menu(BuildContext context) {
    return PageBody(
      maxWidth: 800,
      children: [
        Text('Dein Studium', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        for (final item in [
          ('/lists', 'Sammlungen', Icons.collections_bookmark_outlined),
          ('/settings', 'Einstellungen', Icons.settings_outlined),
          ('/offline', 'Offline-Werke', Icons.offline_bolt_outlined),
          ('/help', 'Hilfe & Anleitungen', Icons.help_outline),
          ('/about', 'Über Akribos', Icons.info_outline),
        ])
          Card(
            child: ListTile(
              leading: Icon(item.$3),
              title: Text(item.$2),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(item.$1),
            ),
          ),
      ],
    );
  }
}

class _TabCountIcon extends StatelessWidget {
  const _TabCountIcon({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    width: 23,
    height: 23,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(
        color:
            IconTheme.of(context).color ??
            Theme.of(context).colorScheme.onSurface,
        width: 1.7,
      ),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: TextStyle(
        fontSize: count > 99 ? 9 : 12,
        height: 1,
        fontWeight: FontWeight.w600,
        color: IconTheme.of(context).color,
      ),
    ),
  );
}
