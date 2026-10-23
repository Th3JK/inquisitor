import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Where the real endpoints live. The demo never calls them — [demoClient]
/// answers in their place — but a real app passes these to
/// `InquisitorConfig`.
final Uri stateUrl = Uri.parse('https://tastyair.cz/rymarov/app_state.php');
final Uri versionUrl = Uri.parse('https://tastyair.cz/rymarov/app_version.php');

/// The situations the demo can put the app in.
enum DemoScenario {
  /// Both stores are on the installed version.
  upToDate('Up to date'),

  /// iOS is on 2.4.0, Android is still on 2.3.0. The app runs 2.3.0, so iOS
  /// sees an optional update and Android sees nothing.
  staggeredRollout('Staggered rollout'),

  /// The app's own minimum is above the installed version.
  forcedUpdate('Forced update'),

  /// `KillSwitch` is `"1"`.
  killSwitch('Kill switch'),

  /// The server cannot be reached.
  offline('Server unreachable');

  const DemoScenario(this.label);

  /// Human-readable name for the picker.
  final String label;
}

/// An HTTP client that serves canned bodies, in the server's exact shape, for
/// [scenario] instead of talking to the network.
http.Client demoClient(DemoScenario scenario, {required bool unlocked}) =>
    MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));

      if (scenario == DemoScenario.offline) {
        throw http.ClientException('No route to host', request.url);
      }
      if (request.url == stateUrl) {
        return http.Response(
          jsonEncode(<Map<String, String>>[
            <String, String>{'flag': 'Unlocked', 'state': unlocked ? '1' : '0'},
            <String, String>{
              'flag': 'KillSwitch',
              'state': scenario == DemoScenario.killSwitch ? '1' : '0',
            },
          ]),
          200,
        );
      }
      return http.Response(
        jsonEncode(<Map<String, String>>[
          // Android has not been bumped yet in any scenario.
          <String, String>{'device': 'Android', 'version': '2.3.0'},
          <String, String>{
            'device': 'Apple',
            'version': scenario == DemoScenario.upToDate ? '2.3.0' : '2.4.0',
          },
        ]),
        200,
      );
    });
