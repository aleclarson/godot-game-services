# Architecture

## Public boundary

Games call one `GameServices` autoload. Every asynchronous operation returns a
`GameServicesRequest`; awaiting `request.wait()` produces a
`GameServicesResult`. Feature results expose small typed value objects at this
boundary, while the result's `raw_data` and each value's `raw` preserve provider
diagnostics.

```gdscript
var request := GameServices.unlock_achievement("first_win")
var result := await request.wait()
if not result.ok:
    push_warning(result.error_message)
```

The request object avoids two common signal-only API problems: callers can
associate completion with the operation they started, and immediate validation
failures cannot race past an `await` connection. Its `map`, `then`, timeout,
cancellation, and explicit retry helpers create linked wrappers while forwarding
the original operation/provider/error metadata. Retry factories are opt-in, so
native mutations and authentication are never replayed as an incidental helper
side effect.

The facade also owns authentication session coordination. `session_state` and
`current_player` are updated from explicit auth/player requests and provider
authentication events. `ensure_authenticated()` coalesces concurrent callers
onto one request, authenticates only when needed, and loads the player profile
when the provider's auth callback did not include it. Provider replacement and
shutdown clear the cache before disposing the old adapter; unfinished session
requests receive the normal `CANCELLED` lifecycle result.

`GameServicesConfig.validate()` is an independent synchronous boundary for
editor tooling and headless CI. It reports provider-specific errors for
malformed mappings, Google step counts, credentials, and store destinations;
`GameServices.initialize()` refuses to create a provider when errors exist.
Absent optional mappings are warnings and remain feature-level
`NOT_CONFIGURED` results.

The facade owns cached `GameServicesAchievementHandle` and
`GameServicesLeaderboardHandle` collections. Handles retain only logical IDs
and delegate mapping, capability, and request lifecycle decisions to the
facade. Consequently a handle can outlive a provider replacement and receives
the same unavailable, not-configured, or cancelled result as a direct facade
call.

## Data flow

```text
Game code
    -> CloudSaveSlot (fixed-slot defaults and policy)
        -> CloudSaveStore (typed values, schema migration, revisions, conflicts)
            -> GameServices raw cloud-save transport
    -> GameServices (logical IDs, validation, typed result normalization)
        -> AppleGameCenterProvider -> native GameCenter singleton
        -> GooglePlayGamesProvider -> native GodotPlayGameServices singleton
        -> MockGameServicesProvider -> deterministic editor/test state
    -> StoreReviewService (contextual request and explicit store-page handoff)
        -> native StoreReview singleton on iOS or Android
        -> mock/editor URL opener
```

Platform identifiers are configuration, not conditionals scattered through game
code. Results expose logical IDs and may also include a `platform_id` for
diagnostics.

## Capability model

Providers advertise a bit mask. Callers can query `supports()` before showing a
feature, and every unsupported operation still returns a completed request with
`GameServicesResult.Code.UNSUPPORTED`.

The initial capability set is:

- authentication
- player profile
- achievements
- incremental achievement progress
- leaderboards
- platform UI
- cloud saves
- server credentials

The mask describes implemented behavior, not what the underlying platform could
theoretically support.

Store reviews deliberately sit beside that provider mask. `StoreReviewService`
owns the dedicated native plugin lifecycle, store-destination configuration,
and the distinction between a contextual in-app request and an explicit store
page. It does not depend on provider authentication and does not redirect after
a suppressed or failed prompt.

## Error model

Portable errors use a small stable code set: unavailable, unsupported, not
authenticated, invalid argument, not configured, platform error, cancelled,
conflict, not found, internal error, and invalid data. The original platform
code and native payload are preserved separately when available.

The facade owns request lifetime. It tracks unfinished requests and completes
them as cancelled before shutting down or replacing their provider, so callers
do not remain suspended until a stale timeout after a lifecycle transition.

`CloudSaveStore` owns its higher-level requests while the facade silently tracks
the underlying provider requests for timeouts and shutdown. This prevents
internal transport operations from appearing as game-initiated
`GameServices.request_finished` events. The store has its own
`request_finished` signal.

## Typed cloud-save envelope

The high-level store serializes an object-free Godot Variant envelope containing
the logical slot, format and game schema versions, a random revision, parent
revisions, portable metadata, and the game value. Provider metadata remains
outside that envelope and is attached to the decoded `CloudSaveDocument`.

Schema migration is deliberately read-only: loading may upgrade the in-memory
document and mark it dirty, but only an explicit `save()` writes a new revision.
Likewise, conflict resolution is manual unless the game opts into a named or
custom policy. These boundaries avoid hidden writes and silent data loss.

## Native packaging boundary

The addon owns the narrow Game Center/Play Games forks plus a dedicated
StoreReview plugin. The Android export plugin injects both AARs and their Maven
dependencies into a Gradle export. Godot's iOS exporter discovers both `.gdip`
descriptors and selects the debug or release XCFrameworks. The native bridges
are built against an exact Godot engine version because their Godot-facing ABI
is version-coupled.

The forks add only behavior required for the normalized contract: Android
snapshot conflict resolution, Apple saved-game operations, and lossless Apple
64-bit score submission. Source and install scripts live under `native/`;
binaries live in the project paths consumed by Godot's exporters.

## Escape hatches

Typed normalized values retain their provider payload in `raw`, and every
result retains the complete normalized payload in `raw_data`. These are
read-only-style diagnostics for provider details that do not justify a portable
field yet. They do not expose the native singleton through the main API,
keeping dependencies and lifecycle ownership inside providers.
