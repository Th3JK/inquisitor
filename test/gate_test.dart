import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquisitor/inquisitor_ui.dart';

import 'support/fake_backend.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 12);

  Inquisitor build(
    FakeBackend backend, {
    InquisitorCache? cache,
    NoDataPolicy policy = NoDataPolicy.allow,
    String version = '2.3.0',
    String? minimum,
  }) => Inquisitor(
    config: InquisitorConfig(
      stateUrl: stateUrl,
      versionUrl: versionUrl,
      httpClient: backend.client,
      storeUrls: const <InquisitorPlatform, String>{
        InquisitorPlatform.ios: 'https://apps.apple.com/app/id1',
      },
      minimumVersions: <InquisitorPlatform, String>{
        InquisitorPlatform.ios: ?minimum,
      },
      cache: cache ?? InMemoryCache(),
      noDataPolicy: policy,
      cacheTtl: Duration.zero,
      refreshOnResume: false,
      versionProvider: () async => AppVersion.tryParse(version),
      platformResolver: () => InquisitorPlatform.ios,
      clock: () => now,
      onError: (_, _) {},
    ),
  );

  Widget app(
    Inquisitor inquisitor, {
    List<String> opened = const <String>[],
    InquisitorScreenBuilder? blockedBuilder,
    bool promptForUpdates = true,
    Widget home = const Scaffold(body: Center(child: Text('the app'))),
  }) => MaterialApp(
    builder: (context, child) => InquisitorGate(
      inquisitor: inquisitor,
      blockedBuilder: blockedBuilder,
      promptForUpdates: promptForUpdates,
      onOpenUrl: (url) async => opened.add(url),
      child: child!,
    ),
    home: home,
  );

  FakeBackend killed() => FakeBackend(state: stateBody(killSwitch: true));
  FakeBackend newer() => FakeBackend(version: versionBody(ios: '2.4.0'));

  testWidgets('shows the app when the verdict is ok', (tester) async {
    final inquisitor = build(FakeBackend());
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor));
    await tester.pumpAndSettle();

    expect(find.text('the app'), findsOneWidget);
    expect(find.byType(InquisitorBlockedScreen), findsNothing);
    expect(find.byType(InquisitorUpdateDialog), findsNothing);
  });

  testWidgets('blocks on a kill switch', (tester) async {
    final inquisitor = build(killed());
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor));
    await tester.pumpAndSettle();

    expect(find.byType(InquisitorBlockedScreen), findsOneWidget);
    expect(find.text('App unavailable'), findsOneWidget);
    // The app stays mounted underneath, just hidden.
    expect(find.text('the app', skipOffstage: false), findsOneWidget);
    expect(find.text('the app'), findsNothing);
  });

  testWidgets('offers no retry for a kill switch', (tester) async {
    final inquisitor = build(killed());
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a locked Unlocked flag does not block', (tester) async {
    final inquisitor = build(FakeBackend(state: stateBody()));
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor));
    await tester.pumpAndSettle();

    expect(find.byType(InquisitorBlockedScreen), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('blocks on a forced update and opens the store', (tester) async {
    final opened = <String>[];
    final inquisitor = build(FakeBackend(), minimum: '9.0.0');
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor, opened: opened));
    await tester.pumpAndSettle();

    expect(find.byType(InquisitorUpdateRequiredScreen), findsOneWidget);
    expect(find.text('the app'), findsNothing);

    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();

    expect(opened, <String>['https://apps.apple.com/app/id1']);
    // A forced update has no way past it.
    expect(find.byType(InquisitorUpdateRequiredScreen), findsOneWidget);
  });

  testWidgets('prompts for an optional update over the running app', (
    tester,
  ) async {
    final inquisitor = build(newer());
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor));
    await tester.pumpAndSettle();

    expect(find.byType(InquisitorUpdateDialog), findsOneWidget);
    expect(find.text('Update available'), findsOneWidget);
    // The app is still live behind the prompt.
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('dismissing the prompt records it and shows the app', (
    tester,
  ) async {
    final cache = InMemoryCache();
    final inquisitor = build(newer(), cache: cache);
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.byType(InquisitorUpdateDialog), findsNothing);
    expect(await cache.dismissedAt('2.4.0'), isNotNull);
    expect(await inquisitor.shouldPromptUpdate(), isFalse);
  });

  testWidgets('does not re-prompt for a version already dismissed', (
    tester,
  ) async {
    final cache = InMemoryCache();
    await cache.markDismissed('2.4.0', now);

    final inquisitor = build(newer(), cache: cache);
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor));
    await tester.pumpAndSettle();

    expect(find.byType(InquisitorUpdateDialog), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('tapping update does not persist a dismissal', (tester) async {
    final cache = InMemoryCache();
    final opened = <String>[];
    final inquisitor = build(newer(), cache: cache);
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor, opened: opened));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();

    expect(opened, <String>['https://apps.apple.com/app/id1']);
    expect(find.byType(InquisitorUpdateDialog), findsNothing);
    // Someone who never installs the update should be asked again next launch.
    expect(await cache.dismissedAt('2.4.0'), isNull);
  });

  testWidgets('promptForUpdates: false suppresses the prompt', (tester) async {
    final inquisitor = build(newer());
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor, promptForUpdates: false));
    await tester.pumpAndSettle();

    expect(find.byType(InquisitorUpdateDialog), findsNothing);
    expect(inquisitor.state.verdict, InquisitorVerdict.updateAvailable);
  });

  testWidgets('lifts the barrier when the server relents', (tester) async {
    final backend = killed();
    final inquisitor = build(backend);
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor));
    await tester.pumpAndSettle();
    expect(find.byType(InquisitorBlockedScreen), findsOneWidget);

    backend.state = stateBody();
    await tester.runAsync(() => inquisitor.refresh(force: true));
    await tester.pumpAndSettle();

    expect(find.byType(InquisitorBlockedScreen), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('a custom builder replaces the blocking screen', (tester) async {
    final inquisitor = build(killed());
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(
      app(
        inquisitor,
        blockedBuilder: (context, state) =>
            Material(child: Center(child: Text('custom ${state.verdict.name}'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('custom blocked'), findsOneWidget);
    expect(find.byType(InquisitorBlockedScreen), findsNothing);
  });

  testWidgets('fail-closed offline shows the no-connection screen', (
    tester,
  ) async {
    final inquisitor = build(
      FakeBackend(error: StateError('offline')),
      policy: NoDataPolicy.block,
    );
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(app(inquisitor));
    await tester.pumpAndSettle();

    expect(find.text('No connection'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('the app'), findsNothing);
  });

  testWidgets('exposes the controller through InquisitorScope', (tester) async {
    final inquisitor = build(FakeBackend());
    addTearDown(inquisitor.dispose);

    Inquisitor? found;
    await tester.pumpWidget(
      app(
        inquisitor,
        home: Builder(
          builder: (context) {
            found = InquisitorScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(found, same(inquisitor));
  });

  testWidgets('loadingBuilder covers the app until the verdict lands', (
    tester,
  ) async {
    final backend = FakeBackend()..gate = Completer<void>();
    final inquisitor = build(backend);
    addTearDown(inquisitor.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => InquisitorGate(
          inquisitor: inquisitor,
          loadingBuilder: (context) =>
              const Material(child: Center(child: Text('checking'))),
          child: child!,
        ),
        home: const Scaffold(body: Center(child: Text('the app'))),
      ),
    );
    await tester.pump();

    expect(find.text('checking'), findsOneWidget);
    expect(find.text('the app'), findsNothing);

    backend.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('checking'), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  group('InquisitorFlagBuilder', () {
    Widget lockedContent() => Scaffold(
      body: InquisitorFlagBuilder(
        flag: 'Unlocked',
        builder: (context, isOn) => Text(isOn ? 'premium' : 'locked'),
      ),
    );

    testWidgets('shows unlocked content when the flag is on', (tester) async {
      final inquisitor = build(FakeBackend(state: stateBody(unlocked: true)));
      addTearDown(inquisitor.dispose);

      await tester.pumpWidget(app(inquisitor, home: lockedContent()));
      await tester.pumpAndSettle();

      expect(find.text('premium'), findsOneWidget);
    });

    testWidgets('flips when the server changes the flag', (tester) async {
      final backend = FakeBackend();
      final inquisitor = build(backend);
      addTearDown(inquisitor.dispose);

      await tester.pumpWidget(app(inquisitor, home: lockedContent()));
      await tester.pumpAndSettle();
      expect(find.text('locked'), findsOneWidget);

      backend.state = stateBody(unlocked: true);
      await tester.runAsync(() => inquisitor.refresh(force: true));
      await tester.pumpAndSettle();
      expect(find.text('premium'), findsOneWidget);

      backend.state = stateBody();
      await tester.runAsync(() => inquisitor.refresh(force: true));
      await tester.pumpAndSettle();
      expect(find.text('locked'), findsOneWidget);
    });

    testWidgets('works without a gate when given a controller', (
      tester,
    ) async {
      final inquisitor = build(FakeBackend(state: stateBody(unlocked: true)));
      addTearDown(inquisitor.dispose);
      await tester.runAsync(inquisitor.start);

      await tester.pumpWidget(
        MaterialApp(
          home: InquisitorFlagBuilder(
            inquisitor: inquisitor,
            flag: 'Unlocked',
            builder: (context, isOn) => Text(isOn ? 'premium' : 'locked'),
          ),
        ),
      );

      expect(find.text('premium'), findsOneWidget);
    });
  });
}
