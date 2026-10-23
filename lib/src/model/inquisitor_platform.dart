import 'package:flutter/foundation.dart';

/// The platform the app runs on, and so which version row applies to it.
///
/// This is Inquisitor's own enum rather than Flutter's [TargetPlatform] so that
/// `web` is a first-class value and so that the server data can be evaluated
/// for an arbitrary platform in tests.
enum InquisitorPlatform {
  /// Android devices — the `Android` version row.
  android,

  /// iOS devices — the `Apple` version row.
  ios,

  /// macOS desktop.
  macos,

  /// Windows desktop.
  windows,

  /// Linux desktop.
  linux,

  /// Web browsers.
  web,

  /// A platform Inquisitor could not identify.
  unknown;

  /// Resolves the platform the app is currently running on.
  static InquisitorPlatform current() {
    if (kIsWeb) return InquisitorPlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => InquisitorPlatform.android,
      TargetPlatform.iOS => InquisitorPlatform.ios,
      TargetPlatform.macOS => InquisitorPlatform.macos,
      TargetPlatform.windows => InquisitorPlatform.windows,
      TargetPlatform.linux => InquisitorPlatform.linux,
      TargetPlatform.fuchsia => InquisitorPlatform.unknown,
    };
  }

  /// Maps a version row's `device` onto a platform: `Android`, `Apple` or
  /// `iOS`, without case. Returns `null` for anything else.
  static InquisitorPlatform? fromKey(String? key) =>
      switch (key?.trim().toLowerCase()) {
        'android' => InquisitorPlatform.android,
        'apple' || 'ios' => InquisitorPlatform.ios,
        _ => null,
      };
}

/// Supplies the platform Inquisitor should evaluate against.
///
/// Override it in `InquisitorConfig` to exercise another platform in tests or
/// a debug menu.
typedef PlatformResolver = InquisitorPlatform Function();
