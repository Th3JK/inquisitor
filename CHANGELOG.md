## 0.1.0

Rebuilt around the two-endpoint backend. **Breaking.**

* Only the `app_state` / `app_version` format is supported:
  `[{"flag": ..., "state": ...}]` and `[{"device": ..., "version": ...}]`.
  `InquisitorConfig` takes `stateUrl` and `versionUrl` directly.
* Every state row is now a flag. `InquisitorState.flags`,
  `Inquisitor.isFlagOn`, `watchFlag` and `addFlagListener`, plus
  `InquisitorConfig.flagListeners`, follow them.
* New `InquisitorFlagBuilder` widget for locked/unlocked content.
* `KillSwitch` (or `Switch`) is the only flag that blocks. `Unlocked = "0"`
  no longer blocks the app; it is a content flag.
* Store URLs and minimum versions are configured in the app
  (`storeUrls`, `minimumVersions`).
* Each endpoint must answer with a JSON array. Anything else counts as a
  failed fetch and never replaces the cache. Bodies are no longer
  double-decoded, and a single object is no longer accepted as a row.
* `InquisitorCache` stores the state and version bodies separately
  (`write(state:, version:, fetchedAt:)`, `CachedPayload.state` /
  `.version`).
* `InquisitorPlatform.fromKey` only recognises `Android`, `Apple` and `iOS`;
  the unused `key` getter is gone.
* Removed: the generic JSON schema, `InquisitorFetcher`, `HttpFetcher`,
  `CompositeFetcher`, `InquisitorMapper`, `LegacyListMapper`, `BlockRule`,
  `PlatformRules`, `VersionRange`, maintenance mode and its countdown,
  `Inquisitor.reevaluate`, ETag revalidation, release notes and
  `NoDataPolicy.custom`. `NoDataPolicy` is now an enum
  (`allow` / `block`).

## 0.0.1

Initial release.

* Remote kill switch and maintenance mode, with optional version-range targeting
  and a self-lifting `until` window.
* Two update tiers per platform: `latestVersion` prompts, `minimumVersion`
  blocks.
* Per-platform rules over a shared `defaults` block, so a release can be
  staggered across stores without any date arithmetic in the payload.
* Lenient version parsing and comparison — build numbers only count when both
  sides declare one.
* Responses cached in `SharedPreferences`, with a soft `cacheTtl` and an
  optional hard `cacheMaxAge`; ETag revalidation when the server supports it.
* Configurable `NoDataPolicy` for a first launch with no network: `allow`,
  `block`, or `custom`.
* Backend-agnostic seams: `InquisitorFetcher` for any transport,
  `InquisitorMapper` for any response shape, plus `CompositeFetcher` and
  `LegacyListMapper` for split, list-shaped endpoints.
* Opt-in UI: `InquisitorGate` with built-in blocking screens and an update
  prompt, every screen and string replaceable.
