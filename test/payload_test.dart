import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inquisitor/inquisitor.dart';
import 'package:inquisitor/src/model/payload.dart';

import 'support/fake_backend.dart';

void main() {
  // Exactly what the live endpoints serve.
  const liveState =
      '[{"flag":"Unlocked","state":"1"},{"flag":"KillSwitch","state":"0"}]';
  const liveVersion =
      '[{"device":"Android","version":"1.0.0"},{"device":"Apple","version":"1.0.0"}]';

  InquisitorPayload parse({String? state, String? version}) =>
      InquisitorPayload.parse(
        state: state ?? stateBody(),
        version: version ?? versionBody(),
      );

  group('live responses', () {
    final payload = parse(state: liveState, version: liveVersion);

    test('reads every state row as a flag', () {
      expect(payload.flags.names, <String>['Unlocked', 'KillSwitch']);
      expect(payload.flags['Unlocked'], '1');
      expect(payload.flags.isOn('Unlocked'), isTrue);
      expect(payload.flags.isOn('KillSwitch'), isFalse);
    });

    test('leaves the kill switch off', () {
      expect(payload.killSwitch, isFalse);
    });

    test('maps "Apple" onto iOS and reads both versions', () {
      expect(payload.latestVersions[InquisitorPlatform.ios].toString(), '1.0.0');
      expect(
        payload.latestVersions[InquisitorPlatform.android].toString(),
        '1.0.0',
      );
    });
  });

  group('kill switch', () {
    test('fires on a truthy KillSwitch row', () {
      expect(parse(state: stateBody(killSwitch: true)).killSwitch, isTrue);
    });

    test('accepts "Switch" and ignores case', () {
      for (final name in <String>['Switch', 'switch', 'KILLSWITCH']) {
        final state = jsonEncode(<Map<String, String>>[
          <String, String>{'flag': name, 'state': '1'},
        ]);
        expect(parse(state: state).killSwitch, isTrue, reason: name);
      }
    });

    test('a locked Unlocked flag is not a kill switch', () {
      final payload = parse(state: stateBody());
      expect(payload.flags.isOn('Unlocked'), isFalse);
      expect(payload.killSwitch, isFalse);
    });

    test('is never invented out of unreadable rows', () {
      for (final body in <String>['[]', '[{}]', '[{"flag": "KillSwitch"}]']) {
        final payload = parse(state: body);
        expect(payload.killSwitch, isFalse, reason: 'body: $body');
        expect(payload.flags.isEmpty, isTrue, reason: 'body: $body');
      }
    });
  });

  group('flags', () {
    test('are looked up without case', () {
      final flags = parse(state: liveState).flags;
      expect(flags['unlocked'], '1');
      expect(flags.isOn('UNLOCKED'), isTrue);
    });

    test('a missing or unreadable flag reads as off', () {
      final state = jsonEncode(<Map<String, String>>[
        <String, String>{'flag': 'Beta', 'state': 'maybe'},
      ]);
      final flags = parse(state: state).flags;
      expect(flags.isOn('Beta'), isFalse);
      expect(flags['Beta'], 'maybe');
      expect(flags.isOn('Nope'), isFalse);
    });

    test('compare by value', () {
      expect(parse(state: liveState).flags, parse(state: liveState).flags);
      expect(
        parse(state: liveState).flags,
        isNot(parse(state: stateBody()).flags),
      );
    });
  });

  test('skips array items that are not objects', () {
    final payload = parse(state: '[1, "x", null, {"flag":"Unlocked","state":"1"}]');
    expect(payload.flags.names, <String>['Unlocked']);
    expect(payload.flags.isOn('Unlocked'), isTrue);
  });

  test('ignores devices it does not know', () {
    final version = jsonEncode(<Map<String, String>>[
      <String, String>{'device': 'Fridge', 'version': '9.9.9'},
      <String, String>{'device': 'Android', 'version': '1.2.3'},
    ]);
    final payload = parse(version: version);
    expect(payload.latestVersions.keys, <InquisitorPlatform>[
      InquisitorPlatform.android,
    ]);
  });

  test('rejects a body that is not a JSON array, so it cannot displace the '
      'cache', () {
    for (final body in <String>[
      'garbage',
      '',
      '<html>502</html>',
      '"1"',
      '{"flag": "Unlocked", "state": "1"}',
    ]) {
      expect(() => parse(state: body), throwsFormatException, reason: body);
      expect(() => parse(version: body), throwsFormatException, reason: body);
    }
  });
}
