/// What to do when the server is unreachable **and** no usable cached response
/// exists — in practice, a first-ever launch with no connectivity.
///
/// This does not apply when a cached response is available: a cached verdict
/// is always preferred over a policy decision.
enum NoDataPolicy {
  /// Fail open: let the user in. The right default for most apps — a flaky
  /// network should not brick the app on first launch. Every flag reads as
  /// off.
  allow,

  /// Fail closed: block the user behind a "no connection" screen until a
  /// server response can be obtained.
  block,
}
