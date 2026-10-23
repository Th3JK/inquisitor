import 'package:meta/meta.dart';

/// A parsed application version.
///
/// Understands the Flutter/pubspec form `major.minor.patch[-preRelease][+build]`
/// (for example `2.4.0`, `2.4.0+15`, `2.4.0-beta.1+3`) and is deliberately
/// lenient about what a server might send:
///
/// * Missing segments default to zero, so `"2"` and `"2.4"` parse as `2.0.0`
///   and `2.4.0`.
/// * A leading `v` is ignored (`"v2.4.0"`).
/// * Extra numeric segments beyond the patch are ignored (`"2.4.0.1"`).
/// * Anything unparseable yields `null` from [tryParse] rather than throwing.
///
/// The build number only participates in comparison when **both** versions
/// declare one. That way a server advertising `2.4.0` does not mark a locally
/// installed `2.4.0+15` as outdated, while a server that deliberately
/// advertises `2.4.0+16` still can.
@immutable
class AppVersion implements Comparable<AppVersion> {
  /// Creates a version from its components.
  const AppVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const <String>[],
    this.build,
  });

  /// The lowest possible version, used when nothing is known.
  static const AppVersion zero = AppVersion(0, 0, 0);

  static final RegExp _pattern = RegExp(
    r'^[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\.\d+)*'
    r'(?:-([0-9A-Za-z.\-]+))?'
    r'(?:\+([0-9A-Za-z.\-]+))?$',
  );

  /// The major component.
  final int major;

  /// The minor component.
  final int minor;

  /// The patch component.
  final int patch;

  /// Dot-separated pre-release identifiers, empty for a stable release.
  ///
  /// A version carrying pre-release identifiers sorts *below* the same version
  /// without them, matching semver: `2.4.0-beta.1 < 2.4.0`.
  final List<String> preRelease;

  /// The build metadata following `+`, or `null` when unspecified.
  final String? build;

  /// Parses [input], returning `null` when it cannot be understood.
  ///
  /// Never throws — malformed server data must not be able to crash the host
  /// app.
  static AppVersion? tryParse(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final match = _pattern.firstMatch(trimmed);
    if (match == null) return null;

    final preRelease = match.group(4);
    return AppVersion(
      int.parse(match.group(1)!),
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
      preRelease: preRelease == null || preRelease.isEmpty
          ? const <String>[]
          : preRelease.split('.'),
      build: match.group(5),
    );
  }

  /// Whether this is a pre-release version.
  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(AppVersion other) {
    var result = major.compareTo(other.major);
    if (result != 0) return result;

    result = minor.compareTo(other.minor);
    if (result != 0) return result;

    result = patch.compareTo(other.patch);
    if (result != 0) return result;

    result = _comparePreRelease(preRelease, other.preRelease);
    if (result != 0) return result;

    // Build metadata is only meaningful when both sides declare one.
    final thisBuild = build;
    final otherBuild = other.build;
    if (thisBuild == null || otherBuild == null) return 0;
    return _compareIdentifiers(thisBuild, otherBuild);
  }

  static int _comparePreRelease(List<String> a, List<String> b) {
    if (a.isEmpty && b.isEmpty) return 0;
    // A release outranks any pre-release of the same number.
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;

    for (var i = 0; i < a.length && i < b.length; i++) {
      final result = _compareIdentifiers(a[i], b[i]);
      if (result != 0) return result;
    }
    return a.length.compareTo(b.length);
  }

  /// Compares two identifiers numerically when both are numeric, and
  /// lexicographically otherwise. Numeric identifiers rank below alphanumeric
  /// ones, per semver.
  static int _compareIdentifiers(String a, String b) {
    final numA = int.tryParse(a);
    final numB = int.tryParse(b);
    if (numA != null && numB != null) return numA.compareTo(numB);
    if (numA != null) return -1;
    if (numB != null) return 1;
    return a.compareTo(b);
  }

  /// Whether this version is strictly lower than [other].
  bool operator <(AppVersion other) => compareTo(other) < 0;

  /// Whether this version is lower than or equal to [other].
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  /// Whether this version is strictly higher than [other].
  bool operator >(AppVersion other) => compareTo(other) > 0;

  /// Whether this version is higher than or equal to [other].
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0 && isPreRelease == other.isPreRelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, Object.hashAll(preRelease));

  @override
  String toString() {
    final buffer = StringBuffer('$major.$minor.$patch');
    if (preRelease.isNotEmpty) buffer.write('-${preRelease.join('.')}');
    if (build != null) buffer.write('+$build');
    return buffer.toString();
  }
}
