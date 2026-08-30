# API contract

All asynchronous methods return a `GameServicesRequest`. Call `wait()` to
receive a `GameServicesResult`:

```gdscript
var result := await GameServices.load_player().wait()
if result.ok:
	print(result.data)
else:
	push_warning("%s: %s" % [result.error_code, result.error_message])
```

`GameServicesResult` contains `ok`, `operation`, `data`, `error_code`,
`error_message`, `platform_code`, `provider`, and the originating `request_id`.
Successful feature calls put
typed value objects in `data`; `raw_data` (also available as `raw`) retains the
provider-normalized payload for diagnostics. Use `to_dictionary()` when a
serializable representation is useful. `is_success()`, `is_failure()`,
`is_code()`, and `value_or()` avoid repeating status branching. The specialized
`get_player()`, `get_achievement()`, `get_achievements()`, `get_score()`,
`get_credentials()`, and `get_presentation()` helpers perform typed extraction
and return `null` for failed results.

Calling `shutdown()` completes every unfinished request with `Code.CANCELLED`.
`initialize()` first shuts down the current provider, so replacing a provider
has the same behavior. The cancellation result retains the provider name that
owned the request.

## Authentication and sessions

`GameServices` owns a small session state so game code can observe the provider
without duplicating authentication flow:

- `session_state` is one of `SessionState.UNAVAILABLE`,
  `SessionState.SIGNED_OUT`, `SessionState.AUTHENTICATING`, or
  `SessionState.AUTHENTICATED`.
- `current_player` is the cached `GameServicesPlayer`. Use
  `get_current_player()` when a defensive copy is preferred.
- `session_changed(state, player)` fires when either the state or cached player
  changes. The existing `authentication_changed(authenticated, player)` signal
  remains available for provider authentication events.

Use `ensure_authenticated()` when a feature needs an authenticated player. It
is opt-in: it does not run for unrelated feature calls. Concurrent calls share
one request and one provider authentication/player-load sequence. Once a player
is cached, later calls complete from the cache until a provider event, provider
replacement, or shutdown clears it:

```gdscript
var ensured := await GameServices.ensure_authenticated().wait()
if not ensured.ok:
	push_warning(ensured.error_message)
	return

var player: GameServicesPlayer = ensured.data
print("Signed in as ", player.display_name if not player.display_name.is_empty() else player.id)
```

`authenticate()` and `load_player()` remain explicit transport operations for
callers that need them separately. Successful authentication or player loading
also updates the session cache. A provider authentication event updates the
cache immediately; an unauthenticated event clears it. `initialize()` and
`shutdown()` clear the previous session, and any unfinished ensure request is
completed with `Code.CANCELLED` using the provider that owned it.

## Operations

| Area | Methods |
| --- | --- |
| Authentication | `ensure_authenticated()`, `authenticate()`, `is_authenticated()`, `load_player()` |
| Achievements | `unlock_achievement(id)`, `set_achievement_progress(id, progress)`, `load_achievements()` |
| Leaderboards | `submit_score(id, score)`, `show_leaderboards(id)` |
| Platform UI | `show_achievements()`, `show_leaderboards()` |
| Store reviews | `supports_store_review()`, `request_in_app_review()`, `open_store_review_page()` |
| Server verification | `request_server_credentials(options)` |
| Typed cloud saves | `cloud_saves.slot(name)`, `create()`, `load()`, `load_or_create()`, `update()`, `save()`, `exists()`, `list()`, `delete()`, validation, and conflict resolution |
| Raw cloud saves | `save_game(name, data, metadata)`, `load_game(name)`, `list_saved_games()`, `delete_saved_game(id)`, `resolve_saved_game_conflict(...)` |

Achievement and leaderboard methods accept game-owned logical IDs. Their Apple
and Google identifiers live in `GameServicesConfig`. Google incremental
achievements also need a configured total-step count so normalized progress in
the range `0.0...1.0` can be converted to steps.

Server credentials are `GameServicesServerCredentials` values with a stable
`kind` discriminator. Apple returns
`kind = "game_center_identity_signature"` with its signature tuple; Google
returns `kind = "play_games_server_auth_code"` with a one-time authorization
code. The value exposes provider-specific fields (`signature`, `salt`,
`public_key_url`, `authorization_code`, and `token`) without flattening the two
formats.

Achievement operations return `GameServicesAchievement` values. Their `id` is
the logical game-owned ID, `platform_id` is the resolved native ID,
`progress` is normalized to `0.0...1.0`, and provider-specific fields such as
Google's step counts remain available. `load_achievements()` returns a typed
`Array[GameServicesAchievement]`. Score submissions return
`GameServicesLeaderboardScore` with the logical leaderboard `id`, native
`platform_id`, submitted integer `score`, and optional `rank`.

Player operations return `GameServicesPlayer` values with `id`, `display_name`,
`alias`, `provider`, and optional `avatar_uri`/`title`. `authenticate()` returns
`GameServicesAuthentication`, whose `.player` is typed; `ensure_authenticated()`
and `load_player()` return the player directly.

Presentation operations—including achievement/leaderboard UI and store-review
requests—return `GameServicesPresentationOutcome`. `accepted` (also exposed as
`presentation_accepted`) means that the platform accepted the handoff; it does
not claim that a prompt was displayed. Store-page results include `url` and
`handoff`.

All value objects expose a read-only-style `raw` field containing the original
normalized dictionary. The result's `raw_data` is the complete original result
payload, so normalized values do not discard provider details.

### Request helpers

`GameServicesRequest` keeps its original `id`/`request_id` and operation while
helpers create observable wrappers with `parent_id` linking back to the source
and `origin_id` identifying the original request. Results expose that origin as
`request_id`, so composition does not lose correlation metadata.
`map(transform)` receives a successful typed value and preserves failures;
`then(callback)` receives the complete successful `GameServicesResult` and must
return a request or result; `then_value(callback)` passes only the typed value.
`with_timeout(seconds)` bounds the wrapper and returns a portable
`PLATFORM_ERROR` timeout without pretending to cancel the native operation.
`cancel()` completes a pending wrapper with `CANCELLED`.

Retries are explicit and use `GameServicesRetryPolicy` (or a dictionary with
`max_attempts`, `initial_delay_seconds`, `backoff_multiplier`,
`max_delay_seconds`, and `retry_codes`). The policy counts the initial attempt;
the factory is called only for subsequent attempts. Use
`GameServicesRequest.run_with_retry(factory, policy)` to start a retryable flow,
or `request.with_retry(factory, policy)` after an initial request. No helper
implicitly authenticates or retries native mutations.

## Store reviews

`request_in_app_review()` is a contextual request. It uses the dedicated
StoreReview native plugin on iOS and Android and does not require Game Center or
Play Games authentication. A successful result reports that StoreKit or Google
Play accepted the native request/flow handoff; platform policy may suppress the
prompt, and the result does not claim that a prompt was displayed or a review
was submitted.

`open_store_review_page()` is an explicit store-page handoff. It never runs as
an automatic consequence of a failed or suppressed in-app request. Configure
the destinations in `GameServicesConfig`:

- `apple_store_review_url` or a digits-only `apple_app_store_id`
- `google_play_store_review_url` or `google_play_package_name`
- `mock_store_review_url` for the editor mock flow

Explicit URLs take precedence. When an explicit URL is absent, the Apple ID
derives `https://apps.apple.com/app/id<ID>?action=write-review` and the Google
package derives `https://play.google.com/store/apps/details?id=<PACKAGE>`.
The request result contains the normalized operation and native platform
details; the explicit page result includes the destination URL and whether the
native bridge accepted the handoff.

## Typed cloud saves

`GameServices.cloud_saves` is a `CloudSaveStore` layered over the provider's
binary save transport. It safely serializes Godot Variant values, attaches a
versioned envelope, and returns typed documents. For a fixed slot, use a
`CloudSaveSlot` so its defaults and schema policy stay together:

```gdscript
var campaign := GameServices.cloud_saves.slot("campaign", {
	"level": 1,
	"coins": 0,
})
campaign.schema_version = 2
campaign.add_migration(1, _migrate_v1_to_v2)

var loaded := await campaign.load_or_create().wait()
if not loaded.ok:
	push_warning(loaded.error_message)
	return

var document: CloudSaveDocument = loaded.data
document.value.coins += 10

var written := await campaign.save(document).wait()
if written.ok:
	document = written.data
```

`CloudSaveSlot` exposes `load()`, `load_or_create()`, `create()`, `update()`,
`save()`, `exists()`, `delete()`, validation, and conflict-resolution methods. Its
`schema_version`, migrations, `validator`, `conflict_policy`,
`conflict_resolver`, and `max_conflict_attempts` are independent of other
slots. A slot starts with the store's current settings, then can be configured
independently. Use the store's methods directly for dynamic slot names.

`update(mutator)` loads or creates the configured default, passes the decoded
`CloudSaveDocument` to the callable, and saves it. The callable may mutate that
document or return a replacement `CloudSaveDocument`; it runs exactly once, so
a conflict is returned rather than silently replaying game logic.

```gdscript
var result := await campaign.update(func(document):
	document.value.coins += 10
).wait()
```

`create()` returns an unsaved document. `save()` does not mutate its input; on
success, its result contains a new `CloudSaveDocument` with a new random
revision. Saving a previously loaded document records that revision as its
parent.

Documents expose:

- `slot` and decoded `value`
- `schema_version`, `revision`, `parent_revisions`, and `needs_save`
- `description`, `played_time_msec`, `progress_value`, and `custom_metadata`
- provider summary fields such as `provider_id`, `updated_at_msec`, and
  `device_name`

The envelope uses Godot's object-free Variant byte encoding. Dictionaries,
arrays, packed arrays, vectors, colors, transforms, and other value types retain
their Godot types. Objects and unsupported values fail with `INVALID_ARGUMENT`
instead of enabling object reconstruction.

`validate(document)` performs the same local cloning, migration, domain
validation, and serialization checks as `save()` without contacting a provider.
Its successful result contains a `Dictionary` with a would-be `document` and
`encoded_size`. `encoded_size(document)` returns just the encoded byte count,
which is useful for enforcing an app's chosen provider-size limit before upload.

Set `validator` to a callable that returns an empty string or `true` for valid
values, or a non-empty error string/`false` otherwise:

```gdscript
campaign.validator = func(value):
	return "campaign must be a Dictionary" if not value is Dictionary else ""
```

### Schema migrations

Register one migration for each version step:

```gdscript
campaign.schema_version = 3
campaign.add_migration(1, _migrate_v1_to_v2)
campaign.add_migration(2, _migrate_v2_to_v3)

func _migrate_v1_to_v2(value: Variant) -> Variant:
	value["difficulty"] = "normal"
	return value
```

The store applies migrations in memory while loading. A migrated document has
`needs_save = true`; the store never writes it back implicitly. A missing
migration, malformed envelope, foreign binary save, or save from a newer schema
returns `INVALID_DATA` without overwriting the provider copy.

### Conflicts

Manual resolution is the default. A conflicting `load()` or `save()` returns
`Code.CONFLICT` with a `CloudSaveConflict` in `result.data`. Each
`CloudSaveCandidate` contains the decoded document, provider snapshot ID, and
provider modification time:

```gdscript
var loaded := await campaign.load().wait()
if loaded.error_code == GameServicesResult.Code.CONFLICT:
	var conflict: CloudSaveConflict = loaded.data
	var chosen := conflict.highest_progress()
	var resolved := await campaign.resolve_with_candidate(conflict, chosen).wait()
```

Merged values may identify a provider candidate as the resolution base when
needed. If omitted, the store uses the newest decoded candidate; this keeps
Google's snapshot-ID requirement out of the common path:

```gdscript
await campaign.resolve_with_value(
	conflict,
	merge_game_states(conflict.candidates),
	{"progress_value": 80}
).wait()
```

A resolved document receives a new revision whose parents include every decoded
candidate revision. Explicit automatic policies are `NEWEST`,
`HIGHEST_PROGRESS`, and `CUSTOM`; `CUSTOM` may return a `CloudSaveResolution` or
a candidate. Repeated conflicts stop after `max_conflict_attempts` and return to
manual resolution.

### Listing and deletion

`list()` returns `Array[CloudSaveInfo]`. Provider summaries always identify the
logical slot and provider record, but cannot expose every value stored inside
the portable envelope. In particular, GameKit does not expose the embedded
custom metadata without loading each save. Use `load()` when complete metadata
is required.

`delete(slot)` resolves the provider record internally, so game code does not
need Google's snapshot ID. A missing logical slot returns `NOT_FOUND`.

## Raw binary cloud saves

Save names use a deliberately portable subset: 1–100 characters from
`A-Z`, `a-z`, `0-9`, `-`, `.`, `_`, and `~`. Save data is a
`PackedByteArray`. Portable metadata keys are:

- `description`
- `played_time_msec`
- `progress_value`

Providers may return additional metadata in `raw`.
Google persists the three portable metadata keys through snapshot metadata.
GameKit's named saved-game API stores only the name and bytes, so the Apple
provider ignores those optional values.

A conflicting load or save returns `Code.CONFLICT` and a data dictionary with:

```text
conflict_id: String
snapshots: Array[Dictionary]
    id: String
    data: PackedByteArray
    metadata: Dictionary
```

Choose or merge a candidate, then submit the resolved bytes:

```gdscript
var loaded := await GameServices.load_game("slot-1").wait()
if loaded.error_code == GameServicesResult.Code.CONFLICT:
	var conflict: Dictionary = loaded.data
	var chosen: Dictionary = conflict.snapshots[0]
	var resolved := await GameServices.resolve_saved_game_conflict(
		conflict.conflict_id,
		chosen.id,
		chosen.data,
		chosen.get("metadata", {})
	).wait()
```

Apple resolves all same-name `GKSavedGame` candidates with the supplied data;
its `snapshot_id` argument is ignored. Google requires the selected snapshot ID
as part of `SnapshotsClient.resolveConflict`.

## Error codes

The stable portable codes are `OK`, `UNAVAILABLE`, `UNSUPPORTED`,
`NOT_AUTHENTICATED`, `INVALID_ARGUMENT`, `NOT_CONFIGURED`, `PLATFORM_ERROR`,
`CANCELLED`, `CONFLICT`, `NOT_FOUND`, `INTERNAL_ERROR`, and `INVALID_DATA`.
Native error details remain available through `platform_code` and provider
`raw` data when supplied.
