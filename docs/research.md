# Feasibility research

Research snapshot: 2026-08-29.

## Finding

A useful normalized layer is feasible, provided it models a shared core and
reports optional capabilities at runtime. Treating every similarly named API as
identical would be incorrect, especially for authentication, achievement
progress, server credentials, and cloud-save conflicts.

The implementation validates the architectural and packaging parts of that
finding: its normalized contract runs against mock and native-singleton fakes,
the documented two-directory installation works in a clean Godot project, an
Android Gradle export contains the bridges and PGS/review configuration, and
the iOS export links the Game Center and StoreReview bridges for device and
simulator. This does not validate live accounts, console records, system UI,
network errors, or cloud-save conflicts on physical devices; those remain the
release-gating evidence.

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

The Android fork is rebuilt against PGS v2 `22.0.0`, released after the current
upstream wrapper. Google's release notes describe the update as adding game
statistics and player game events; the normalized API does not expose those
provider-only features yet.

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
| Store reviews | StoreKit review request; App Store write-a-review URL | Play In-App Review flow; Play Store app URL | Contextual `request_in_app_review()` plus explicit `open_store_review_page()`; completion is a handoff, not proof of display or submission |

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
  primary account system. Authentication normally begins automatically during
  launch, while an explicit sign-in attempt is available after an unsuccessful
  automatic attempt. The normalized player ID must not be presented as a
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
- Store review prompts are policy-controlled and may not appear. The normalized
  API must not claim display or submission, and a failed or suppressed request
  must not trigger an implicit store-page redirect. The explicit page operation
  remains available for a game-owned fallback action and is independent of
  Game Center or Play Games authentication.

## Primary references

- Godot: [Android plugins](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html)
- Godot: [Plugins for iOS](https://docs.godotengine.org/en/stable/tutorials/platform/ios/plugins_for_ios.html)
- Godot: [Registering an autoload from an editor plugin](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/making_plugins.html#registering-autoloads-singletons-in-plugins)
- Apple: [Authenticating a player](https://developer.apple.com/documentation/gamekit/authenticating-a-player)
- Apple: [Saving game data to iCloud](https://developer.apple.com/documentation/gamekit/saving-the-player-s-game-data-to-an-icloud-account)
- Apple: [SKStoreReviewController](https://developer.apple.com/documentation/storekit/skstorereviewcontroller)
- Google: [Get started with Play Games Services](https://developer.android.com/games/pgs/start)
- Google: [Platform authentication](https://developer.android.com/games/pgs/platform-authentication)
- Google: [Achievements](https://developer.android.com/games/pgs/achievements)
- Google: [Cloud save](https://developer.android.com/games/pgs/savedgames)
- Google: [In-app reviews](https://developer.android.com/guide/playcore/in-app-review)
- Google: [Google Play services release notes](https://developers.google.com/android/guides/releases)
- Google: [Quality checklist](https://developer.android.com/games/pgs/quality)
