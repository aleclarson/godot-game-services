# Architecture

## Public boundary

Games call one `GameServices` autoload. Every asynchronous operation returns a
`GameServicesRequest`; awaiting `request.wait()` produces a
`GameServicesResult`.

```gdscript
var request := GameServices.unlock_achievement("first_win")
var result := await request.wait()
if not result.ok:
    push_warning(result.error_message)
```

The request object avoids two common signal-only API problems: callers can
associate completion with the operation they started, and immediate validation
failures cannot race past an `await` connection.

## Data flow

```text
Game code
    -> CloudSaveStore (typed values, schema migration, revisions, conflicts)
        -> GameServices raw cloud-save transport
    -> GameServices (logical IDs, validation, result normalization)
        -> AppleGameCenterProvider -> native GameCenter singleton
        -> GooglePlayGamesProvider -> native GodotPlayGameServices singleton
        -> MockGameServicesProvider -> deterministic editor/test state
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

The addon owns two narrow forks of existing MIT-licensed integrations. The
Android export plugin injects its AAR and Maven dependencies into a Gradle
export. Godot's iOS exporter discovers the `.gdip` descriptor and selects the
debug or release XCFramework. Both native bridges are built against an exact
Godot engine version because their Godot-facing ABI is version-coupled.

The forks add only behavior required for the normalized contract: Android
snapshot conflict resolution, Apple saved-game operations, and lossless Apple
64-bit score submission. Source and install scripts live under `native/`;
binaries live in the project paths consumed by Godot's exporters.

## Escape hatches

Normalized result dictionaries may contain `raw` provider data. This is a
read-only escape hatch for features that do not justify a portable type yet. It
does not expose the native singleton through the main API, keeping dependencies
and lifecycle ownership inside providers.
