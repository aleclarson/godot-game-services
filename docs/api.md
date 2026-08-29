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
`error_message`, `platform_code`, and `provider`. Use `to_dictionary()` when a
serializable representation is useful.

Calling `shutdown()` completes every unfinished request with `Code.CANCELLED`.
`initialize()` first shuts down the current provider, so replacing a provider
has the same behavior. The cancellation result retains the provider name that
owned the request.

## Operations

| Area | Methods |
| --- | --- |
| Authentication | `authenticate()`, `is_authenticated()`, `load_player()` |
| Achievements | `unlock_achievement(id)`, `set_achievement_progress(id, progress)`, `load_achievements()` |
| Leaderboards | `submit_score(id, score)`, `show_leaderboards(id)` |
| Platform UI | `show_achievements()`, `show_leaderboards()` |
| Server verification | `request_server_credentials(options)` |
| Cloud saves | `save_game(name, data, metadata)`, `load_game(name)`, `list_saved_games()`, `delete_saved_game(id)`, `resolve_saved_game_conflict(...)` |

Achievement and leaderboard methods accept game-owned logical IDs. Their Apple
and Google identifiers live in `GameServicesConfig`. Google incremental
achievements also need a configured total-step count so normalized progress in
the range `0.0...1.0` can be converted to steps.

Server credentials intentionally remain discriminated values. Apple returns
`kind = "game_center_identity_signature"` with its signature tuple; Google
returns `kind = "play_games_server_auth_code"` with a one-time authorization
code.

## Cloud saves

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
`CANCELLED`, `CONFLICT`, `NOT_FOUND`, and `INTERNAL_ERROR`. Native error details
remain available through `platform_code` and provider `raw` data when supplied.
