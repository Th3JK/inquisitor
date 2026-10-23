import 'package:flutter_test/flutter_test.dart';
import 'package:inquisitor/inquisitor.dart';
import 'package:inquisitor_example/demo_backend.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('resolves a verdict against the real SharedPreferences plugin', (
    tester,
  ) async {
    final inquisitor = Inquisitor(
      config: InquisitorConfig(
        stateUrl: stateUrl,
        versionUrl: versionUrl,
        httpClient: demoClient(DemoScenario.staggeredRollout, unlocked: true),
        versionProvider: () async => AppVersion.tryParse('2.3.0'),
        platformResolver: () => InquisitorPlatform.ios,
        cache: SharedPreferencesCache(keyPrefix: 'inquisitor_integration_test'),
      ),
    );
    addTearDown(inquisitor.dispose);

    await inquisitor.start();

    expect(inquisitor.state.verdict, InquisitorVerdict.updateAvailable);
    expect(inquisitor.state.source, InquisitorSource.network);
    expect(inquisitor.state.latestVersion.toString(), '2.4.0');
    expect(inquisitor.isFlagOn('Unlocked'), isTrue);

    // The response must have survived the round trip through the platform.
    await inquisitor.refresh(force: true);
    expect(inquisitor.state.verdict, InquisitorVerdict.updateAvailable);
  });

  testWidgets('reads the real package version without throwing', (
    tester,
  ) async {
    final inquisitor = Inquisitor(
      config: InquisitorConfig(
        stateUrl: stateUrl,
        versionUrl: versionUrl,
        httpClient: demoClient(DemoScenario.staggeredRollout, unlocked: false),
        cache: InMemoryCache(),
      ),
    );
    addTearDown(inquisitor.dispose);

    await inquisitor.start();

    expect(inquisitor.state.currentVersion, isNotNull);
  });
}
