import 'package:meta/meta.dart';

import 'json.dart';

/// The named flags served by the state endpoint.
///
/// Each `{"flag": "Unlocked", "state": "1"}` row becomes one entry. Lookups
/// ignore case, so `flags['unlocked']` and `flags['Unlocked']` are the same
/// flag.
@immutable
class InquisitorFlags {
  /// Creates a flag set from raw name/value pairs.
  InquisitorFlags(Map<String, String> values)
    : _values = <String, String>{
        for (final entry in values.entries) entry.key.toLowerCase(): entry.value,
      },
      _names = List<String>.unmodifiable(values.keys);

  const InquisitorFlags._empty()
    : _values = const <String, String>{},
      _names = const <String>[];

  /// A flag set with nothing in it.
  static const InquisitorFlags empty = InquisitorFlags._empty();

  final Map<String, String> _values;
  final List<String> _names;

  /// The flag names, as the server spelled them.
  Iterable<String> get names => _names;

  /// Whether no flags were served at all.
  bool get isEmpty => _values.isEmpty;

  /// The raw value of [name], or `null` when the server did not send it.
  String? operator [](String name) => _values[name.toLowerCase()];

  /// Whether [name] is switched on.
  ///
  /// A flag the server left out, or whose value reads as neither true nor
  /// false, counts as off — locked content stays locked until the server
  /// clearly says otherwise.
  bool isOn(String name) => asBool(this[name]) ?? false;

  @override
  bool operator ==(Object other) {
    if (other is! InquisitorFlags || other._values.length != _values.length) {
      return false;
    }
    for (final entry in _values.entries) {
      if (other._values[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    _values.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );

  @override
  String toString() => 'InquisitorFlags(${{
    for (final name in _names) name: this[name],
  }})';
}
