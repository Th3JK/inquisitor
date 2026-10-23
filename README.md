# inquisitor

Remote app control for Flutter: a kill switch, content flags and update gating, driven by two endpoints on your server.

- **Kill switch:** set `KillSwitch` to `"1"` and every install is blocked.
- **Content flags:** every state row is a flag the app can listen to. For example, `Unlocked = "1"` opens up locked content.
- **Update tiers:** the server's latest version prompts a soft update, and a minimum set in the app forces one.
- **Per-platform, independently:** iOS can sit two days ahead of Android, or the other way round.
- **Offline-first:** the last response is cached in `SharedPreferences`, and you decide what happens on a first launch with no network.
- **Opt-in UI:** ready-made blocking screens, an update prompt and a flag builder. Or take just the state and build your own.

Pure Dart on top of `http`, `shared_preferences`, `package_info_plus` and `url_launcher`.

## The endpoints

```
GET app_state.php    ->  [{"flag": "Unlocked",   "state": "1"},
                          {"flag": "KillSwitch", "state": "0"}]
GET app_version.php  ->  [{"device": "Android", "version": "1.0.0"},
                          {"device": "Apple",   "version": "1.0.0"}]
```

Both are fetched in parallel on every refresh, and both bodies are cached together.

- **State rows** become flags. Names are compared without case. `"1"`/`"0"` (as well as `true`/`false`, `yes`/`no` and `on`/`off`) read as on/off, and a flag the server leaves out reads as **off**.
- **`KillSwitch`** (or `Switch`) set to on blocks the app. It is the only flag Inquisitor acts on itself. The rest are for the app to interpret.
- **Version rows** give the latest version per platform. `device` is `Android` or `Apple` (`iOS` is accepted too). Other devices are ignored.
- **A bad response is a failed fetch.** A body that isn't a JSON array (an HTML error page, say) never replaces a good cached response.

## Getting started

```dart
import 'package:inquisitor/inquisitor_ui.dart';

final premium = ValueNotifier<bool>(false);

final inquisitor = Inquisitor(
  config: InquisitorConfig(
    stateUrl: Uri.parse('https://tastyair.cz/rymarov/app_state.php'),
    versionUrl: Uri.parse('https://tastyair.cz/rymarov/app_version.php'),
    storeUrls: {
      InquisitorPlatform.ios: 'https://apps.apple.com/app/id123456789',
      InquisitorPlatform.android:
          'https://play.google.com/store/apps/details?id=com.example.app',
    },
    minimumVersions: {InquisitorPlatform.ios: '1.0.0'},
    flagListeners: {'Unlocked': (isOn) => premium.value = isOn},
  ),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await inquisitor.start();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) =>
        InquisitorGate(inquisitor: inquisitor, child: child!),
    home: const HomePage(),
  );
}
```

Mount the gate through `MaterialApp.builder`. That puts the barrier above the `Navigator`, so it covers every route. The app below stays mounted but hidden, so when the kill switch is lifted, the user is back exactly where they left off.

Headless works too. Import `package:inquisitor/inquisitor.dart` instead and drive your own UI from `inquisitor.state` and `inquisitor.stream`.

## Flags

There are four ways to follow a flag. Pick whichever fits the code that cares about it.

```dart
// 1. Declared up front, in the config.
InquisitorConfig(
  // ...
  flagListeners: {'Unlocked': (isOn) => premium.value = isOn},
);

// 2. Added at runtime. The returned function removes it again.
final remove = inquisitor.addFlagListener('Unlocked', (isOn) { ... });

// 3. As a stream of distinct values.
inquisitor.watchFlag('Unlocked').listen((isOn) { ... });

// 4. In the widget tree. The controller comes from InquisitorGate's scope.
InquisitorFlagBuilder(
  flag: 'Unlocked',
  builder: (context, isOn) => isOn ? const PremiumPanel() : const LockedTeaser(),
);
```

A listener is called once the flag's value is first known, whether that comes from the cache or the network, and again each time it changes. An unchanged value is never repeated. If there is no data at all, listeners hear `false`, so locked content stays locked. `addFlagListener(..., fireImmediately: false)` skips the current value and only reports changes. A listener that throws is reported to `onError` and does not affect the other listeners.

For a one-off check, `inquisitor.isFlagOn('Unlocked')` and `state.flags['Unlocked']` give the current value (the second returns the raw string).

## Verdicts

`InquisitorState.verdict` is one of the following, in ascending severity:

| Verdict | Meaning | `isBlocking` |
| --- | --- | --- |
| `ok` | Nothing to do | no |
| `updateAvailable` | Below the server's latest version: prompt, don't insist | no |
| `updateRequired` | Below `minimumVersions` | yes |
| `blocked` | `KillSwitch` is on, or there is no data and `NoDataPolicy.block` applies | yes |

`state.source` says where the answer came from (`network`, `cache` or `fallback`). `state.error` carries the last fetch failure, even when a cached verdict is being served.

### Staggering a release

The server only ever states what is current, so there is no rollout schedule to maintain. Ship to iOS on Monday and bump the `Apple` row to the new version; Android users see nothing. Bump the `Android` row on Wednesday when the Play review clears.

### Version comparison

Versions parse as `major.minor.patch[-preRelease][+build]`. Missing segments default to zero, a leading `v` is ignored, and pre-releases sort below their release. **The build number only counts when both sides declare one**, so a server advertising `2.4.0` will not mark a locally installed `2.4.0+15` as outdated. An install whose version cannot be read is never forced to update.

## Offline behaviour

At launch, a cached response is applied immediately, before the network is consulted. `cacheTtl` (default 15 minutes) decides when a background refresh is worth making. `cacheMaxAge` (default: never) decides when a cached response stops counting at all.

When there is no usable cache **and** the server is unreachable (a first-ever launch with no connectivity), `noDataPolicy` decides what happens:

```dart
NoDataPolicy.allow  // fail open (default); every flag reads as off
NoDataPolicy.block  // fail closed behind a "no connection" screen with a retry button
```

## Configuration

| Option | Default | |
| --- | --- | --- |
| `stateUrl` / `versionUrl` | required | The two endpoints |
| `storeUrls` | `{}` | Where the update button sends each platform |
| `minimumVersions` | `{}` | Below this, an update is forced |
| `flagListeners` | `{}` | Called with each flag's value as it becomes known and changes |
| `httpClient` | a new `http.Client` | Reuse the app's client; it is not closed on dispose |
| `headers` | `{}` | Sent to both endpoints, for example an API key |
| `timeout` | 10 s | Per request |
| `cacheTtl` | 15 min | How long a cached response is considered fresh |
| `cacheMaxAge` | `null` | When a cached response stops being usable at all |
| `refreshOnResume` | `true` | Refresh when the app returns to the foreground |
| `minRefreshInterval` | 5 min | Minimum time between automatic refreshes |
| `nagInterval` | `null` | How long a dismissed prompt stays dismissed; `null` means once per version |
| `noDataPolicy` | `allow` | What happens when offline with no cache |
| `versionProvider` | `package_info_plus` | Where the running version comes from |
| `platformResolver` | the real platform | Which platform's version row to apply |
| `clock` | `DateTime.now` | For deterministic tests |
| `onError` | `null` | Every failure Inquisitor absorbs; wire up your logger here |

Nothing in this package throws at the app. Failed fetches, unreadable responses, cache errors and throwing flag listeners are all caught, reported to `onError`, and surfaced as `state.error`. A kill switch that crashes the app it protects would be worse than no kill switch.

## Customising the UI

```dart
InquisitorGate(
  inquisitor: inquisitor,
  strings: InquisitorStrings(updateAction: context.l10n.updateNow),
  blockedBuilder: (context, state) => MyBlockedScreen(state: state),
  updateRequiredBuilder: (context, state) => MyForcedUpdate(state: state),
  updatePromptBuilder: (context, state, onUpdate, onDismiss) => ...,
  loadingBuilder: (context) => const SplashScreen(),
  onOpenUrl: (url) => myLauncher.open(url),
  promptForUpdates: false, // keep the hard tiers, surface soft updates yourself
  child: child,
);
```

`InquisitorStrings` is a plain data class, so localisation goes through your own delegate and this package doesn't need `intl`. Inside the gate, `InquisitorScope.of(context)` reaches the controller.

## Example

`example/` is a demo app with a fake backend. It has a switch for every scenario: up to date, staggered rollout, forced update, kill switch, `Unlocked` on/off, and offline under both policies.

```bash
cd example && flutter run
```
