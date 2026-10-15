import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api_client.dart';
import 'core/app_scope.dart';
import 'core/deep_link.dart';
import 'features/account/account_screen.dart';
import 'features/account/auth_screen.dart';
import 'features/collections/collections_screen.dart';
import 'features/documents/documents_screen.dart';
import 'features/help/help_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/reader/reader_controller.dart';
import 'theme/akribos_theme.dart';
import 'widgets/floating_navigation.dart';
import 'features/search/search_screen.dart';
import 'widgets/common.dart';

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
  const AkribosApp({super.key, this.api, this.enableLinks = true});
  final AppApi? api;
  final bool enableLinks;
  @override
  State<AkribosApp> createState() => _AkribosAppState();
}

class _AkribosAppState extends State<AkribosApp> {
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
    _loadTheme();
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
  });
  final AppApi api;
  final ThemeMode themeMode;
  final void Function(ThemeMode) setTheme;
  final bool enableLinks, eInk;
  final void Function(bool) setEInk;
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
  Future<void>? _refreshing;
  bool get _hasGuard => _guards[_activeBranch]?.isNotEmpty ?? false;
  bool _ready = false, _started = false;
  Object? _error;
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
    setState(() => _error = null);
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
  }

  Future<void> _authenticationChanged() {
    final precedingRefresh = _refreshing;
    final generation = ++_bootstrapGeneration;
    // A successful auth response is the boundary, even if the next request fails.
    _acceptedBootstrap = {};
    widget.api.bootstrap = {};
    _sessionOwner = null;
    _readerFontScale = null;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _invalidatePrivateBranches(preserveAuthForm: true));
    return _trackRefresh(() async {
      // Never reuse a request sent with the previous session. Let it finish first
      // so its API-client assignment cannot race the new authoritative response.
      try {
        await precedingRefresh;
      } catch (_) {
        // The fresh request below determines the new session's result.
      }
      if (!mounted || generation != _bootstrapGeneration) return;
      await _loadSession(generation);
    }());
  }

  Future<void> _loadSession(int generation) async {
    await widget.api.initializeReader(MediaQuery.sizeOf(context).width);
    final data = await widget.api.loadBootstrap();
    if (generation != _bootstrapGeneration) {
      widget.api.bootstrap = _acceptedBootstrap;
      return;
    }
    if (!mounted) return;
    final owner = asString(asMap(data['user'])['id']);
    final ownerChanged = _sessionOwner != null && _sessionOwner != owner;
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
      if (_readerFontScale == null || ownerChanged || refreshReader) {
        _readerFontScale = fontScale;
      }
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

  bool _reader(String path) {
    final p = Uri.parse(path).path;
    return p == '/' ||
        !RegExp(
          r'^/(search|G\d|H\d|notes|sermons|lists|l/|invites|account|login|logout|register|password-reset|admin|help|menu|workspaces|datenschutz|impressum|about|api)',
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
    if (state == AppLifecycleState.resumed && _ready) {
      _refreshSession().catchError((Object error) {
        if (mounted) showError(context, error);
      });
    }
  }

  @override
  void dispose() {
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
              : IndexedStack(
                  index: _activeBranch,
                  children: List.generate(4, _branchScreen),
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
        Card(
          child: SwitchListTile.adaptive(
            title: const Text('E-Ink-Modus'),
            subtitle: const Text(
              'Hoher Kontrast und direktes Blättern, z. B. für Boox-Tablets.',
            ),
            value: widget.eInk,
            onChanged: widget.setEInk,
          ),
        ),
        for (final item in [
          ('/lists', 'Sammlungen', Icons.collections_bookmark_outlined),
          ('/account', 'Konto & Darstellung', Icons.manage_accounts_outlined),
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
