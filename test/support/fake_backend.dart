import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final Uri stateUrl = Uri.parse('https://example.com/app_state.php');
final Uri versionUrl = Uri.parse('https://example.com/app_version.php');

/// A state body in the server's exact shape.
String stateBody({bool unlocked = false, bool killSwitch = false}) =>
    jsonEncode(<Map<String, String>>[
      <String, String>{'flag': 'Unlocked', 'state': unlocked ? '1' : '0'},
      <String, String>{'flag': 'KillSwitch', 'state': killSwitch ? '1' : '0'},
    ]);

/// A version body in the server's exact shape.
String versionBody({String ios = '2.3.0', String android = '2.3.0'}) =>
    jsonEncode(<Map<String, String>>[
      <String, String>{'device': 'Android', 'version': android},
      <String, String>{'device': 'Apple', 'version': ios},
    ]);

/// Serves whatever bodies the test sets, through a real `http.Client`.
class FakeBackend {
  FakeBackend({String? state, String? version, this.error})
    : state = state ?? stateBody(),
      version = version ?? versionBody();

  String state;
  String version;
  int statusCode = 200;

  /// Thrown from every request when set.
  Object? error;

  /// Held open to keep a fetch in flight while the test inspects things.
  Completer<void>? gate;

  /// How many refreshes reached the server.
  int calls = 0;

  late final http.Client client = MockClient((request) async {
    final isState = request.url == stateUrl;
    if (isState) calls++;
    if (gate != null) await gate!.future;
    final error = this.error;
    if (error != null) throw error;
    return http.Response(isState ? state : version, statusCode);
  });
}
