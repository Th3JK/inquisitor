import 'package:flutter_test/flutter_test.dart';
import 'package:inquisitor/inquisitor.dart';

void main() {
  AppVersion parse(String input) {
    final version = AppVersion.tryParse(input);
    expect(version, isNotNull, reason: 'failed to parse "$input"');
    return version!;
  }

  group('parsing', () {
    test('reads the full form', () {
      final version = parse('2.4.1+15');
      expect(version.major, 2);
      expect(version.minor, 4);
      expect(version.patch, 1);
      expect(version.build, '15');
      expect(version.preRelease, isEmpty);
    });

    test('defaults missing segments to zero', () {
      expect(parse('2').toString(), '2.0.0');
      expect(parse('2.4').toString(), '2.4.0');
    });

    test('ignores a leading v and extra segments', () {
      expect(parse('v2.4.0').toString(), '2.4.0');
      expect(parse('2.4.0.7').toString(), '2.4.0');
    });

    test('reads pre-release identifiers', () {
      final version = parse('2.4.0-beta.1+3');
      expect(version.preRelease, <String>['beta', '1']);
      expect(version.build, '3');
      expect(version.isPreRelease, isTrue);
    });

    test('tolerates surrounding whitespace', () {
      expect(parse('  2.4.0  ').toString(), '2.4.0');
    });

    test('returns null rather than throwing on junk', () {
      for (final input in <String?>[
        null,
        '',
        '   ',
        'latest',
        'v',
        '.',
        'two.four.zero',
      ]) {
        expect(AppVersion.tryParse(input), isNull, reason: 'input: "$input"');
      }
    });
  });

  group('comparison', () {
    test('orders by major, minor then patch', () {
      expect(parse('3.0.0') > parse('2.9.9'), isTrue);
      expect(parse('2.5.0') > parse('2.4.9'), isTrue);
      expect(parse('2.4.1') > parse('2.4.0'), isTrue);
      expect(parse('2.4.0') < parse('2.4.1'), isTrue);
    });

    test('ignores the build number unless both sides declare one', () {
      // The important case: a server advertising "2.4.0" must not mark a
      // locally installed 2.4.0+15 as outdated.
      expect(parse('2.4.0+15') < parse('2.4.0'), isFalse);
      expect(parse('2.4.0') < parse('2.4.0+15'), isFalse);
      expect(parse('2.4.0+15') == parse('2.4.0'), isTrue);
    });

    test('compares build numbers when both declare one', () {
      expect(parse('2.4.0+15') < parse('2.4.0+16'), isTrue);
      expect(parse('2.4.0+9') < parse('2.4.0+10'), isTrue);
    });

    test('sorts a pre-release below its release', () {
      expect(parse('2.4.0-beta.1') < parse('2.4.0'), isTrue);
      expect(parse('2.4.0-beta.1') < parse('2.4.0-beta.2'), isTrue);
      expect(parse('2.4.0-alpha') < parse('2.4.0-beta'), isTrue);
      expect(parse('2.4.0-beta') < parse('2.4.0-beta.1'), isTrue);
    });

    test('ranks numeric pre-release identifiers below alphanumeric ones', () {
      expect(parse('2.4.0-1') < parse('2.4.0-alpha'), isTrue);
    });

    test('sorts a list into ascending order', () {
      final versions = <AppVersion>[
        parse('2.4.0'),
        parse('1.0.0'),
        parse('2.4.0-beta.1'),
        parse('2.10.0'),
        parse('2.2.0'),
      ]..sort();

      expect(versions.map((v) => v.toString()).toList(), <String>[
        '1.0.0',
        '2.2.0',
        '2.4.0-beta.1',
        '2.4.0',
        '2.10.0',
      ]);
    });
  });

  test('round-trips through toString', () {
    for (final input in <String>['2.4.0', '2.4.0+15', '2.4.0-beta.1+3']) {
      expect(parse(input).toString(), input);
    }
  });
}
