/// Lenient JSON coercion helpers.
///
/// Real backends are messy: booleans arrive as `"1"`, numbers as strings.
/// These helpers absorb that so a sloppy field never throws while parsing.
library;

/// Reads [value] as a bool, accepting `true`, `"true"`, `"1"`, `"yes"`, `"on"`
/// and any non-zero number. Returns `null` when nothing sensible can be made
/// of it.
bool? asBool(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return switch (value.trim().toLowerCase()) {
      'true' || '1' || 'yes' || 'y' || 'on' => true,
      'false' || '0' || 'no' || 'n' || 'off' => false,
      _ => null,
    };
  }
  return null;
}

/// Reads [value] as a non-empty string, stringifying numbers and bools.
String? asString(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return value.toString();
}
