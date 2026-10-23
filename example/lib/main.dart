import 'package:flutter/material.dart';
import 'package:inquisitor/inquisitor_ui.dart';

import 'demo_backend.dart';

void main() {
  runApp(const InquisitorDemoApp());
}

/// Drives Inquisitor from a fake backend so every verdict is reachable without
/// a server.
class InquisitorDemoApp extends StatefulWidget {
  /// Creates the demo.
  const InquisitorDemoApp({super.key});

  @override
  State<InquisitorDemoApp> createState() => _InquisitorDemoAppState();
}

class _InquisitorDemoAppState extends State<InquisitorDemoApp> {
  /// The version the demo pretends to be running.
  static final AppVersion installedVersion = AppVersion.tryParse('2.3.0')!;

  DemoScenario _scenario = DemoScenario.staggeredRollout;
  InquisitorPlatform _platform = InquisitorPlatform.ios;
  bool _unlocked = false;
  bool _failClosed = false;

  /// What the `Unlocked` listener last heard, to show a configured listener
  /// at work alongside [InquisitorFlagBuilder].
  final ValueNotifier<bool> _premium = ValueNotifier<bool>(false);

  late Inquisitor _inquisitor = _build();

  Inquisitor _build() => Inquisitor(
    config: InquisitorConfig(
      stateUrl: stateUrl,
      versionUrl: versionUrl,
      httpClient: demoClient(_scenario, unlocked: _unlocked),
      storeUrls: const <InquisitorPlatform, String>{
        InquisitorPlatform.ios: 'https://apps.apple.com/app/id284882215',
        InquisitorPlatform.android:
            'https://play.google.com/store/apps/details?id=com.example.app',
      },
      minimumVersions: <InquisitorPlatform, String>{
        InquisitorPlatform.ios: _scenario == DemoScenario.forcedUpdate
            ? '2.5.0'
            : '2.0.0',
        InquisitorPlatform.android: _scenario == DemoScenario.forcedUpdate
            ? '2.5.0'
            : '2.0.0',
      },
      flagListeners: <String, InquisitorFlagListener>{
        'Unlocked': (isOn) => _premium.value = isOn,
      },
      // A real app leaves these alone; the demo pins them so the outcome is
      // predictable on any device.
      versionProvider: () async => installedVersion,
      platformResolver: () => _platform,
      cache: InMemoryCache(),
      noDataPolicy: _failClosed ? NoDataPolicy.block : NoDataPolicy.allow,
      onError: (error, stack) => debugPrint('Inquisitor: $error'),
    ),
  );

  /// Rebuilds the controller — the demo's equivalent of relaunching the app.
  void _restart(VoidCallback change) {
    final previous = _inquisitor;
    setState(() {
      change();
      _inquisitor = _build();
    });
    previous.dispose();
  }

  @override
  void dispose() {
    _inquisitor.dispose();
    _premium.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inquisitor',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C4AB6),
        useMaterial3: true,
      ),
      builder: (context, child) =>
          InquisitorGate(inquisitor: _inquisitor, child: child!),
      home: _ControlPanel(
        inquisitor: _inquisitor,
        premium: _premium,
        scenario: _scenario,
        platform: _platform,
        unlocked: _unlocked,
        failClosed: _failClosed,
        onScenarioChanged: (value) => _restart(() => _scenario = value),
        onPlatformChanged: (value) => _restart(() => _platform = value),
        onUnlockedChanged: (value) => _restart(() => _unlocked = value),
        onFailClosedChanged: (value) => _restart(() => _failClosed = value),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.inquisitor,
    required this.premium,
    required this.scenario,
    required this.platform,
    required this.unlocked,
    required this.failClosed,
    required this.onScenarioChanged,
    required this.onPlatformChanged,
    required this.onUnlockedChanged,
    required this.onFailClosedChanged,
  });

  final Inquisitor inquisitor;
  final ValueNotifier<bool> premium;
  final DemoScenario scenario;
  final InquisitorPlatform platform;
  final bool unlocked;
  final bool failClosed;
  final ValueChanged<DemoScenario> onScenarioChanged;
  final ValueChanged<InquisitorPlatform> onPlatformChanged;
  final ValueChanged<bool> onUnlockedChanged;
  final ValueChanged<bool> onFailClosedChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inquisitor'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => inquisitor.refresh(force: true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _VerdictCard(inquisitor: inquisitor),
          const SizedBox(height: 16),
          const _PremiumCard(),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: premium,
            builder: (context, isOn, _) => Text(
              'flagListeners["Unlocked"] last heard: $isOn',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
          Text('Server says', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          RadioGroup<DemoScenario>(
            groupValue: scenario,
            onChanged: (value) {
              if (value != null) onScenarioChanged(value);
            },
            child: Column(
              children: <Widget>[
                for (final option in DemoScenario.values)
                  RadioListTile<DemoScenario>(
                    value: option,
                    title: Text(option.label),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          SwitchListTile(
            value: unlocked,
            title: const Text('Unlocked = "1"'),
            subtitle: const Text('Unlocks the premium card above.'),
            contentPadding: EdgeInsets.zero,
            onChanged: onUnlockedChanged,
          ),
          const Divider(height: 32),
          Text(
            'Running as',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<InquisitorPlatform>(
            segments: const <ButtonSegment<InquisitorPlatform>>[
              ButtonSegment<InquisitorPlatform>(
                value: InquisitorPlatform.ios,
                label: Text('iOS'),
              ),
              ButtonSegment<InquisitorPlatform>(
                value: InquisitorPlatform.android,
                label: Text('Android'),
              ),
            ],
            selected: <InquisitorPlatform>{platform},
            onSelectionChanged: (selection) =>
                onPlatformChanged(selection.first),
          ),
          const SizedBox(height: 8),
          Text(
            'On "Staggered rollout" the version endpoint puts Apple on 2.4.0 '
            'and Android on 2.3.0. The app runs '
            '${_InquisitorDemoAppState.installedVersion}, so only iOS is '
            'prompted.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          SwitchListTile(
            value: failClosed,
            title: const Text('Fail closed with no data'),
            subtitle: const Text(
              'NoDataPolicy.block instead of allow. Combine with "Server '
              'unreachable" to see the difference.',
            ),
            contentPadding: EdgeInsets.zero,
            onChanged: onFailClosedChanged,
          ),
        ],
      ),
    );
  }
}

/// Locked content, unlocked by the `Unlocked` flag.
class _PremiumCard extends StatelessWidget {
  const _PremiumCard();

  @override
  Widget build(BuildContext context) {
    return InquisitorFlagBuilder(
      flag: 'Unlocked',
      builder: (context, isOn) => Card.outlined(
        child: ListTile(
          leading: Icon(isOn ? Icons.lock_open : Icons.lock_outline),
          title: Text(isOn ? 'Premium content' : 'Locked content'),
          subtitle: Text(
            isOn
                ? 'The server set Unlocked to "1".'
                : 'Unlocks when the server sets Unlocked to "1".',
          ),
        ),
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.inquisitor});

  final Inquisitor inquisitor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<InquisitorState>(
      stream: inquisitor.stream,
      builder: (context, snapshot) {
        final state = snapshot.data ?? inquisitor.state;
        final theme = Theme.of(context);

        return Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(state.verdict.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                _row(theme, 'Platform', state.platform.name),
                _row(theme, 'Installed', '${state.currentVersion}'),
                _row(theme, 'Latest', '${state.latestVersion}'),
                _row(theme, 'Minimum', '${state.minimumVersion}'),
                _row(
                  theme,
                  'Flags',
                  state.flags.isEmpty
                      ? 'none'
                      : <String>[
                          for (final name in state.flags.names)
                            '$name=${state.flags[name]}',
                        ].join(', '),
                ),
                _row(theme, 'Source', state.source.name),
                if (state.error != null) _row(theme, 'Error', '${state.error}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 80,
          child: Text(label, style: theme.textTheme.labelMedium),
        ),
        Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
      ],
    ),
  );
}
