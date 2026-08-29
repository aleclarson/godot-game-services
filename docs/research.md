# Feasibility research

Research snapshot: 2026-08-29.

## Finding

A useful normalized layer is feasible, provided it models a shared core and
reports optional capabilities at runtime. Treating every similarly named API as
identical would be incorrect, especially for authentication, achievement
progress, server credentials, and cloud-save conflicts.

## Existing Godot integrations

The [Godot SDK Integrations organization](https://github.com/godot-sdk-integrations)
currently lists both target integrations:

- [godot-play-game-services](https://github.com/godot-sdk-integrations/godot-play-game-services)
  provides a Godot 4 Android plugin backed by Play Games Services v2. Its latest
  release during this review was `v3.4.0` (2026-07-20), using
  `play-services-games-v2:21.0.0` and Godot `4.5.1.stable` at build time.
- [godot-ios-plugins](https://github.com/godot-sdk-integrations/godot-ios-plugins)
  contains a Godot 4-compatible `GameCenter` singleton. Its source is maintained,
  but its latest packaged GitHub release is still the Godot 3.5 release from
  2022. Godot 4 users currently need to build its XCFramework from source.

Both native integrations use MIT-compatible licensing. This package adapts
their runtime singletons without linking against their GDScript types and ships
narrow source forks plus Godot 4.7.2 binaries. That keeps the normalized core
independently testable and makes missing native plugins a reported runtime
condition rather than a parse error.

## Capability matrix

| Capability | Apple Game Center | Google Play Games Services | Normalized contract |
| --- | --- | --- | --- |
| Platform authentication | `GKLocalPlayer.authenticateHandler`; may request presentation of system UI and may call back more than once | PGS v2 performs automatic platform authentication and also exposes an explicit sign-in attempt | `authenticate()` plus observable authentication state; no sign-out promise |
| Player profile | Team-scoped player ID, alias, and display name | Player ID, display name, title, and images | Stable provider-scoped ID and display name; provider data remains available as `raw` |
| Standard achievements | Report percentage complete; `100` unlocks | Explicit unlock | `unlock_achievement()` |
| Incremental achievements | Percentage in the range `0...100` | Integer steps with a configured total | `set_achievement_progress()` in the range `0.0...1.0`; Google step totals live in configuration |
| Hidden achievements | Defined in App Store Connect | Hidden/revealed state plus explicit reveal API | Reveal remains optional rather than being implied by progress |
| Score submission | Signed 64-bit leaderboard score | Signed 64-bit raw score | `submit_score()` with a logical leaderboard ID and integer score |
| Platform UI | One Game Center controller with dashboard states | Separate achievements, leaderboard, and saved-game intents | Presentation requests share methods; completion only means the request was accepted |
| Cloud saves | `GKLocalPlayer` saved-game APIs with named data and conflict resolution | Snapshot APIs with metadata and conflicts | Capability-gated named binary saves with explicit conflict results |
| Server credentials | Identity-verification signature tuple | One-time server authorization code | One method returning a discriminated credential `kind`; payloads are deliberately not flattened |

## Upstream constraints and the package boundary

- The upstream Game Center plugin converts submitted scores through a 32-bit
  floating-point value before assigning them to GameKit's integer score. The
  bundled fork accepts a signed 64-bit integer end to end. The adapter still
  rejects large scores when it detects an older, unpatched bridge.
- The current Play Games Services wrapper uses the same boolean callback for a
  successful incremental-achievement update that has not unlocked the
  achievement and for some failures. The normalized adapter can report whether
  the achievement became unlocked, but it cannot recover a missing native error
  from that callback.
- The upstream Android wrapper detects snapshot conflicts but does not expose
  the native conflict-resolution call. The bundled fork retains pending native
  conflicts and exposes `SnapshotsClient.resolveConflict`, including repeated
  conflicts.
- The upstream Game Center bridge does not expose `GKSavedGame`. The bundled
  fork adds save, load, list, delete, and conflict-resolution events. Apple
  iCloud container and entitlement setup remains game-specific.

## Important semantic constraints

- Google documents PGS v2 as a platform engagement identity, not a game's
  primary account system. The normalized player ID must not be presented as a
  replacement for an in-game account.
- Game Center has no application-controlled sign-out operation. The public API
  therefore does not promise portable sign-out behavior.
- An Apple achievement percentage and Google incremental steps can be
  normalized only when the Google total-step count is known. This belongs in
  per-game configuration.
- Platform UI calls have incompatible closing callbacks. Their normalized result
  means "presentation accepted," not "the player closed the screen."
- Server credential formats serve related but distinct verification flows. The
  result includes a `kind` discriminator and provider-native fields.
- Cloud-save conflict resolution requires more design than last-write-wins. A
  provider that cannot expose conflicts must not advertise the cloud-save
  capability.

## Primary references

- Godot: [Plugins for iOS](https://docs.godotengine.org/en/stable/tutorials/platform/ios/plugins_for_ios.html)
- Apple: [Initializing and configuring Game Center](https://developer.apple.com/documentation/gamekit/initializing-and-configuring-game-center)
- Apple: [Fetching saved games](https://developer.apple.com/documentation/gamekit/gklocalplayer/fetchsavedgames(completionhandler:))
- Google: [Get started with Play Games Services](https://developer.android.com/games/pgs/start)
- Google: [PGS v2 migration overview](https://developer.android.com/games/pgs/migration_overview)
- Google: [Achievements](https://developer.android.com/games/pgs/achievements)
- Google: [Quality checklist](https://developer.android.com/games/pgs/quality)
