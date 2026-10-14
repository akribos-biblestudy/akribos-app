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
import 'features/reader/workspace_screen.dart';
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
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
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

ThemeData appTheme(Brightness brightness, {bool eInk = false}) {
  final normal = ColorScheme.fromSeed(
    seedColor: const Color(0xff49664f),
    brightness: brightness,
  );
  final scheme = eInk
      ? normal.copyWith(
          primary: Colors.black,
          onPrimary: Colors.white,
          primaryContainer: Colors.white,
          onPrimaryContainer: Colors.black,
          secondary: Colors.black,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xffeeeeee),
          onSecondaryContainer: Colors.black,
          surface: Colors.white,
          onSurface: Colors.black,
          surfaceContainerLow: Colors.white,
          surfaceContainer: Colors.white,
          surfaceContainerHighest: Colors.white,
          outline: Colors.black,
          outlineVariant: Colors.black,
        )
      : normal;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: eInk
        ? Colors.white
        : brightness == Brightness.light
        ? const Color(0xfff7f6f0)
        : const Color(0xff171c19),
    splashFactory: eInk ? NoSplash.splashFactory : InkRipple.splashFactory,
    pageTransitionsTheme: eInk
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _InstantTransition(),
              TargetPlatform.iOS: _InstantTransition(),
            },
          )
        : const PageTransitionsTheme(),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    textTheme: ThemeData(brightness: brightness).textTheme
        .apply(fontFamilyFallback: const ['NotoSansHebrew']),
  );
}

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
  Future<bool> Function()? _guard;
  Object? _guardOwner;
  bool _ready = false, _started = false;
  Object? _error;
  int _generation = 0;
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

  Future<void> _refreshSession() async {
    await widget.api.initializeReader(MediaQuery.sizeOf(context).width);
    await widget.api.loadBootstrap();
    if (mounted) setState(() {});
  }

  bool _reader(String path) {
    final p = Uri.parse(path).path;
    return p == '/' ||
        !RegExp(
          r'^/(search|G\d|H\d|notes|sermons|lists|l/|invites|account|login|logout|register|password-reset|admin|help|menu|workspaces|datenschutz|impressum|about|api)',
        ).hasMatch(p);
  }

  Future<void> _open(String path, {bool record = true}) async {
    try {
      final uri = widget.api.safeUri(path);
      final target =
          '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}${uri.hasFragment ? '#${uri.fragment}' : ''}';
      if (_guard != null && !await _guard!()) return;
      if (!mounted) return;
      setState(() {
        if (record && _path != target) {
          _history.add(_path);
          if (_history.length > 100) _history.removeAt(0);
        }
        _path = target;
        _generation++;
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
    } else if (_guard != null && await _guard!()) {
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  int get _selected => _reader(_path)
      ? 0
      : _path.startsWith('/search') || RegExp(r'^/[GH]\d').hasMatch(_path)
      ? 1
      : _path.startsWith('/notes') || _path.startsWith('/sermons')
      ? 2
      : _path.startsWith('/lists') || _path.startsWith('/l/')
      ? 3
      : 4;
  void _select(int index) =>
      _open(['/', '/search', '/notes', '/lists', '/menu'][index]);
  static const _destinations = [
    ('Lesen', Icons.auto_stories_outlined, Icons.auto_stories),
    ('Suchen', Icons.search_outlined, Icons.search),
    ('Notizen', Icons.edit_note_outlined, Icons.edit_note),
    (
      'Sammlungen',
      Icons.collections_bookmark_outlined,
      Icons.collections_bookmark,
    ),
    ('Mehr', Icons.more_horiz, Icons.more_horiz),
  ];
  void _setGuard(Object owner, Future<bool> Function()? guard) {
    if (guard != null) {
      _guardOwner = owner;
      _guard = guard;
    } else if (identical(owner, _guardOwner)) {
      _guard = null;
      _guardOwner = null;
    }
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      final wide = MediaQuery.sizeOf(context).width >= 840;
      final user = asMap(widget.api.bootstrap['user']);
      return PopScope(
        canPop: _history.isEmpty && _guard == null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _back();
        },
        child: Scaffold(
          appBar: AppBar(
            title: TextButton(
              onPressed: _ready ? () => _open('/') : null,
              child: Text(
                'akribos',
                style: TextStyle(
                  fontFamily: 'AkribosText',
                  fontWeight: FontWeight.w700,
                  fontSize: 29,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            leading: _history.isNotEmpty
                ? IconButton(
                    tooltip: 'Zurück',
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back),
                  )
                : null,
            actions: [
              IconButton(
                tooltip: 'Arbeitsbereiche',
                onPressed: _ready ? () => _open('/workspaces') : null,
                icon: const Icon(Icons.dashboard_outlined),
              ),
              IconButton(
                tooltip: user.isEmpty ? 'Anmelden' : 'Konto',
                onPressed: _ready
                    ? () => _open(user.isEmpty ? '/login' : '/account')
                    : null,
                icon: Icon(
                  user.isEmpty
                      ? Icons.person_outline
                      : Icons.account_circle_outlined,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: !_ready
                ? _startup(context)
                : Row(
                    children: [
                      if (wide)
                        NavigationRail(
                          selectedIndex: _selected,
                          onDestinationSelected: _select,
                          labelType: NavigationRailLabelType.all,
                          destinations: _destinations
                              .map(
                                (d) => NavigationRailDestination(
                                  icon: Icon(d.$2),
                                  selectedIcon: Icon(d.$3),
                                  label: Text(d.$1),
                                ),
                              )
                              .toList(),
                        ),
                      if (wide) const VerticalDivider(width: 1),
                      Expanded(
                        child: KeyedSubtree(
                          key: ValueKey('$_path:$_generation'),
                          child: _screen(context),
                        ),
                      ),
                    ],
                  ),
          ),
          bottomNavigationBar: !wide && _ready
              ? NavigationBar(
                  labelBehavior: MediaQuery.sizeOf(context).width < 500
                      ? NavigationDestinationLabelBehavior.onlyShowSelected
                      : NavigationDestinationLabelBehavior.alwaysShow,
                  animationDuration: widget.eInk
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  selectedIndex: _selected,
                  onDestinationSelected: _select,
                  destinations: _destinations
                      .map(
                        (d) => NavigationDestination(
                          icon: Icon(d.$2),
                          selectedIcon: Icon(d.$3),
                          label: d.$1,
                        ),
                      )
                      .toList(),
                )
              : null,
        ),
      );
    },
  );
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
  Widget _screen(BuildContext context) {
    final route = Uri.parse(_path).path;
    if (route == '/menu') return _menu(context);
    if (route == '/workspaces' || route.startsWith('/workspaces/')) {
      return WorkspaceScreen(path: _path);
    }
    if (route.startsWith('/notes') || route.startsWith('/sermons')) {
      return DocumentsScreen(path: _path);
    }
    if (route.startsWith('/lists') ||
        route.startsWith('/l/') ||
        route.startsWith('/invites/')) {
      return CollectionsScreen(path: _path);
    }
    if (route.startsWith('/account')) return AccountScreen(path: _path);
    if (route.startsWith('/login') ||
        route.startsWith('/logout') ||
        route.startsWith('/register') ||
        route.startsWith('/password-reset')) {
      return AuthScreen(path: _path);
    }
    if (route.startsWith('/help')) return HelpScreen(path: _path);
    if (['/about', '/impressum', '/datenschutz', '/api'].contains(route) ||
        route.startsWith('/api/')) {
      return InformationScreen(path: _path);
    }
    if (route == '/search' || RegExp(r'^/[GH]\d').hasMatch(route)) {
      return SearchScreen(path: _path);
    }
    return ReaderScreen(path: _path);
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
          ('/workspaces', 'Arbeitsbereiche', Icons.dashboard_outlined),
          ('/sermons', 'Ausarbeitungen', Icons.view_kanban_outlined),
          ('/sermons/templates', 'Vorlagen', Icons.description_outlined),
          ('/notes/import', 'Notizen importieren', Icons.file_upload_outlined),
          ('/account', 'Konto & Darstellung', Icons.manage_accounts_outlined),
          ('/help', 'Hilfe & Anleitungen', Icons.help_outline),
          ('/about', 'Über Akribos', Icons.info_outline),
          ('/datenschutz', 'Datenschutz', Icons.privacy_tip_outlined),
          ('/impressum', 'Impressum', Icons.business_outlined),
        ])
          Card(
            child: ListTile(
              leading: Icon(item.$3),
              title: Text(item.$2),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(item.$1),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Akribos-Link öffnen'),
            onTap: () => _openLink(context),
          ),
        ),
      ],
    );
  }

  Future<void> _openLink(BuildContext context) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => const _LinkDialog(),
    );
    if (value == null || value.isEmpty) return;
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.scheme == 'akribos') {
      final target = appLinkPath(parsed, widget.api.origin);
      if (target != null) {
        await _open(target);
      } else if (context.mounted) {
        showError(context, 'Dieser App-Link ist ungültig.');
      }
      return;
    }
    await _open(
      value.startsWith('http') || value.startsWith('/') ? value : '/$value',
    );
  }
}

class _InstantTransition extends PageTransitionsBuilder {
  const _InstantTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog();
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Link öffnen'),
    content: TextField(
      controller: _controller,
      decoration: const InputDecoration(
        labelText: 'Akribos-Link oder Bibelstelle',
      ),
      autofocus: true,
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Öffnen'),
      ),
    ],
  );
}
