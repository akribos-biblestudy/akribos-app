import 'dart:async';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/core/app_updates.dart';
import 'package:akribos_app/features/help/help_screen.dart';
import 'package:akribos_app/features/reader/reader_controller.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/settings/settings_screen.dart';
import 'package:akribos_app/main.dart';
import 'package:akribos_app/widgets/app_update_details.dart';
import 'package:akribos_app/widgets/app_update_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../reader/native_reader_test.dart' show ReaderApi, readerFixture;

const _installed = InstalledAppInfo(
  version: '0.5.0',
  build: '17',
  packageName: 'de.akribos.app',
  platform: 'android',
);
final _available = StoreCheckResult(
  status: StoreUpdateStatus.available,
  update: StoreUpdate(
    version: '0.6.0',
    build: '18',
    storeUri: Uri.parse(
      'https://play.google.com/store/apps/details?id=de.akribos.app',
    ),
  ),
);

class _Gateway implements AppUpdateGateway {
  StoreCheckResult result = _available;
  Completer<StoreCheckResult>? pending;
  int checks = 0, opens = 0, disposals = 0;
  bool openResult = true, failCheck = false;

  @override
  Future<InstalledAppInfo> info() async => _installed;

  @override
  Future<StoreCheckResult> check(InstalledAppInfo installed) async {
    checks++;
    if (failCheck) throw StateError('Store unavailable');
    return pending?.future ?? result;
  }

  @override
  Future<bool> openStore(InstalledAppInfo installed, StoreUpdate update) async {
    opens++;
    return openResult;
  }

  @override
  void dispose() => disposals++;
}

class _UpdateApi extends ReaderApi {
  _UpdateApi() : super(readerFixture());

  @override
  Future<Json> loadBootstrap() async => bootstrap;
}

Future<void> _harness(
  WidgetTester tester, {
  required AppUpdateController updates,
  required Widget child,
  double scale = 1,
  bool eInk = false,
  Future<void> Function()? openStore,
}) async {
  final api = AppApi(server: 'https://example.test');
  addTearDown(api.dispose);
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(Brightness.light, eInk: eInk),
      builder: (context, content) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: AppScope(
          api: api,
          open: (_) async {},
          refreshSession: () async {},
          setNavigationGuard: (_, _) {},
          setTheme: (_) {},
          themeMode: ThemeMode.light,
          eInk: eInk,
          updates: updates,
          openUpdateStore: openStore,
          child: content!,
        ),
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final destination in ['about', 'settings']) {
    testWidgets('real package version appears in $destination', (tester) async {
      final updates = AppUpdateController(gateway: _Gateway());
      final reader = ReaderController();
      addTearDown(updates.dispose);
      addTearDown(reader.dispose);
      await updates.initialize();
      await _harness(
        tester,
        updates: updates,
        child: destination == 'about'
            ? const InformationScreen(path: '/about')
            : SettingsScreen(readerController: reader),
      );
      await tester.ensureVisible(find.byType(AppUpdateDetails));
      expect(find.text('Version 0.5.0 · Build 17'), findsOneWidget);
      expect(
        find.text('Version 0.6.0 ist im Store verfügbar.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'manual checks show progress, current, unsupported and failure states',
    (tester) async {
      final gateway = _Gateway();
      final updates = AppUpdateController(gateway: gateway);
      addTearDown(updates.dispose);
      await updates.initialize();
      await _harness(
        tester,
        updates: updates,
        child: const SingleChildScrollView(child: AppUpdateDetails()),
      );
      gateway.pending = Completer<StoreCheckResult>();
      await tester.tap(find.text('Nach Updates suchen'));
      await tester.pump();
      expect(find.text('Im Store wird nach Updates gesucht …'), findsOneWidget);
      final checkingButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Nach Updates suchen'),
      );
      expect(checkingButton.onPressed, isNull);
      gateway.pending!.complete(
        const StoreCheckResult(status: StoreUpdateStatus.current),
      );
      await tester.pumpAndSettle();
      gateway.pending = null;
      expect(
        find.textContaining('kein neueres Update verfügbar'),
        findsOneWidget,
      );
      expect(find.text('Im Store öffnen'), findsNothing);
      gateway.result = const StoreCheckResult(
        status: StoreUpdateStatus.unavailable,
        message: 'Diese Installation stammt nicht aus Google Play.',
      );
      await tester.tap(find.text('Nach Updates suchen'));
      await tester.pumpAndSettle();
      expect(
        find.text('Diese Installation stammt nicht aus Google Play.'),
        findsOneWidget,
      );
      gateway.failCheck = true;
      await tester.tap(find.text('Nach Updates suchen'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Updates konnten nicht geprüft werden.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('update controls fit a narrow E-Ink screen at 200 percent text', (
    tester,
  ) async {
    final updates = AppUpdateController(gateway: _Gateway());
    addTearDown(updates.dispose);
    await updates.initialize();
    var opened = 0;
    await _harness(
      tester,
      updates: updates,
      scale: 2,
      eInk: true,
      openStore: () async {
        opened++;
      },
      child: const Column(
        children: [
          AppUpdateNotice(),
          Expanded(child: SingleChildScrollView(child: AppUpdateDetails())),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.descendant(
        of: find.byType(AppUpdateNotice),
        matching: find.text('Im Store öffnen'),
      ),
    );
    await tester.pumpAndSettle();
    expect(opened, 1);
    tester.view.physicalSize = const Size(900, 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Update-Hinweis für 24 Stunden schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Update auf 0.6.0 verfügbar'), findsNothing);
    expect(find.text('Version 0.6.0 ist im Store verfügbar.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('foregrounding checks again only after the controller interval', (
    tester,
  ) async {
    final api = _UpdateApi();
    final gateway = _Gateway();
    var now = DateTime(2026, 10, 17, 12);
    final updates = AppUpdateController(gateway: gateway, now: () => now);
    addTearDown(api.dispose);
    addTearDown(updates.dispose);
    await tester.pumpWidget(
      AkribosApp(api: api, updates: updates, enableLinks: false),
    );
    await tester.pumpAndSettle();
    expect(gateway.checks, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.checks, 1);
    now = now.add(const Duration(hours: 13));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.checks, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    now = now.add(const Duration(hours: 13));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      gateway.checks,
      2,
      reason: 'The disposed app removes its lifecycle observer.',
    );
  });

  testWidgets(
    'store navigation waits for active guards and the retained Reader',
    (tester) async {
      final api = _UpdateApi();
      final gateway = _Gateway();
      final updates = AppUpdateController(gateway: gateway);
      addTearDown(api.dispose);
      addTearDown(updates.dispose);
      await tester.pumpWidget(
        AkribosApp(api: api, updates: updates, enableLinks: false),
      );
      await tester.pumpAndSettle();
      final reader = tester
          .widget<ReaderScreen>(find.byType(ReaderScreen))
          .controller!;
      final readerState = tester.state(find.byType(ReaderScreen));
      await AppScope.of(tester.element(find.byType(ReaderScreen)))
          .open('/about');
      await tester.pumpAndSettle();
      final scope = AppScope.of(tester.element(find.byType(InformationScreen)));
      final guardOwner = Object(), readerOwner = Object();
      var allow = false, readerAllowed = true;
      final order = <String>[];
      reader.attach(
        readerOwner,
        showTabs: () async {},
        flush: () async {
          order.add('reader');
          return readerAllowed;
        },
      );
      scope.setNavigationGuard(guardOwner, () async {
        order.add('guard');
        return allow;
      });
      await scope.openUpdateStore!();
      expect(order, ['guard']);
      expect(gateway.opens, 0);
      allow = true;
      readerAllowed = false;
      await scope.openUpdateStore!();
      expect(order, ['guard', 'guard', 'reader']);
      expect(gateway.opens, 0);
      await tester.pumpAndSettle();
      expect(
        find.text('Die aktuelle Lesestelle konnte nicht gespeichert werden.'),
        findsOneWidget,
      );

      final guardDone = Completer<bool>(), readerDone = Completer<bool>();
      scope.setNavigationGuard(guardOwner, () => guardDone.future);
      reader.attach(
        readerOwner,
        showTabs: () async {},
        flush: () => readerDone.future,
      );
      final opening = scope.openUpdateStore!();
      await tester.pump();
      expect(gateway.opens, 0);
      guardDone.complete(true);
      await tester.pump();
      expect(gateway.opens, 0);
      readerDone.complete(true);
      await opening;
      expect(gateway.opens, 1);
      expect(
        tester.state(find.byType(ReaderScreen, skipOffstage: false)),
        same(readerState),
      );
      scope.setNavigationGuard(guardOwner, null);
      reader.detach(readerOwner);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        gateway.disposals,
        0,
        reason: 'The injected controller remains owned by its caller.',
      );
    },
  );

  testWidgets(
    'failed guards and store launches stay visible without losing the screen',
    (tester) async {
      final api = _UpdateApi();
      final gateway = _Gateway();
      final updates = AppUpdateController(gateway: gateway);
      addTearDown(api.dispose);
      addTearDown(updates.dispose);
      await tester.pumpWidget(
        AkribosApp(api: api, updates: updates, enableLinks: false),
      );
      await tester.pumpAndSettle();
      final scope = AppScope.of(tester.element(find.byType(ReaderScreen)));
      final owner = Object();
      scope.setNavigationGuard(owner, () async {
        throw const ApiException(
          'Der Entwurf konnte nicht gespeichert werden.',
        );
      });
      await scope.openUpdateStore!();
      await tester.pumpAndSettle();
      expect(gateway.opens, 0);
      expect(
        find.text('Der Entwurf konnte nicht gespeichert werden.'),
        findsOneWidget,
      );
      scope.setNavigationGuard(owner, null);
      ScaffoldMessenger.of(tester.element(find.byType(ReaderScreen)))
          .clearSnackBars();
      gateway.openResult = false;
      await scope.openUpdateStore!();
      await tester.pumpAndSettle();
      expect(gateway.opens, 1);
      expect(
        find.text(
          'Der Store konnte nicht geöffnet werden. Bitte versuche es erneut.',
        ),
        findsOneWidget,
      );
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
