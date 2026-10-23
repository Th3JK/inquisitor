import 'dart:convert';

import 'package:meta/meta.dart';

import 'app_version.dart';
import 'flags.dart';
import 'inquisitor_platform.dart';
import 'json.dart';

/// What the two endpoints said, parsed.
///
/// The backend serves two list-shaped documents:
///
/// ```json
/// // app_state.php
/// [{"flag": "Unlocked", "state": "1"}, {"flag": "KillSwitch", "state": "0"}]
/// // app_version.php
/// [{"device": "Android", "version": "1.0.0"}, {"device": "Apple", "version": "1.0.0"}]
/// ```
///
/// Every state row becomes a flag. A truthy `KillSwitch` (or `Switch`) row
/// revokes access; every other flag is for the app to interpret.
@immutable
class InquisitorPayload {
  /// Creates a payload.
  const InquisitorPayload({
    this.flags = InquisitorFlags.empty,
    this.killSwitch = false,
    this.latestVersions = const <InquisitorPlatform, AppVersion>{},
  });

  /// Flag names that revoke access when on, compared without case.
  static const Set<String> killSwitchFlags = <String>{'killswitch', 'switch'};

  /// Every flag from the state endpoint, the kill switch included.
  final InquisitorFlags flags;

  /// Whether the kill switch is on.
  final bool killSwitch;

  /// The newest published version per platform.
  final Map<InquisitorPlatform, AppVersion> latestVersions;

  /// Parses the raw [state] and [version] response bodies.
  ///
  /// Rows that cannot be read are skipped — a bad row never turns into a kill
  /// switch.
  ///
  /// Throws [FormatException] when either body is not a JSON array — an HTML
  /// error page, say — so it is treated as a failed fetch and never displaces
  /// a good cached response.
  factory InquisitorPayload.parse({
    required String state,
    required String version,
  }) {
    final flags = <String, String>{};
    for (final row in _rows(state, 'state')) {
      final name = asString(row['flag']);
      final value = asString(row['state']);
      if (name != null && value != null) flags[name] = value;
    }

    final latestVersions = <InquisitorPlatform, AppVersion>{};
    for (final row in _rows(version, 'version')) {
      final platform = InquisitorPlatform.fromKey(asString(row['device']));
      final version = AppVersion.tryParse(asString(row['version']));
      if (platform != null && version != null) {
        latestVersions[platform] = version;
      }
    }

    return InquisitorPayload(
      flags: InquisitorFlags(flags),
      killSwitch: flags.entries.any(
        (entry) =>
            killSwitchFlags.contains(entry.key.toLowerCase()) &&
            (asBool(entry.value) ?? false),
      ),
      latestVersions: latestVersions,
    );
  }

  /// Decodes the response called [name] into its object rows, skipping
  /// anything in the array that is not an object.
  static Iterable<Map<Object?, Object?>> _rows(String body, String name) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw FormatException('Unreadable $name response', body);
    }
    if (decoded is! List) {
      throw FormatException('Unreadable $name response', body);
    }
    return decoded.whereType<Map<Object?, Object?>>();
  }
}
