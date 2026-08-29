class_name GooglePlayGamesProvider
extends GameServicesProvider

## Adapter for the `GodotPlayGameServices` Android singleton.

const BASE_CAPABILITIES := (
	Capability.AUTHENTICATION
	| Capability.PLAYER_PROFILE
	| Capability.ACHIEVEMENTS
	| Capability.ACHIEVEMENT_PROGRESS
	| Capability.LEADERBOARDS
	| Capability.PLATFORM_UI
	| Capability.SERVER_CREDENTIALS
)

var _plugin: Object
var _authenticated: bool = false
var _player: Dictionary = {}
var _pending_signals: Dictionary = {}
var _capabilities: int = BASE_CAPABILITIES


func provider_name() -> StringName:
	return &"google_play_games"


func capabilities() -> int:
	return _capabilities


func initialize(p_config: GameServicesConfig) -> GameServicesResult:
	config = p_config
	_capabilities = BASE_CAPABILITIES
	if not Engine.has_singleton("GodotPlayGameServices"):
		return GameServicesResult.failure(
			&"initialize",
			GameServicesResult.Code.UNAVAILABLE,
			"The GodotPlayGameServices Android singleton is not installed",
			provider_name()
		)
	_plugin = Engine.get_singleton("GodotPlayGameServices")
	if (
		_plugin.has_method("saveGame")
		and _plugin.has_method("loadGame")
		and _plugin.has_method("loadSnapshots")
		and _plugin.has_method("deleteSnapshot")
		and _plugin.has_method("resolveSnapshotConflict")
		and _plugin.has_signal("conflictResolved")
	):
		_capabilities |= Capability.CLOUD_SAVES
	_connect_native_signals()
	_plugin.call("initialize")
	return GameServicesResult.success(
		&"initialize",
		{"capabilities": capabilities()},
		provider_name()
	)


func shutdown() -> void:
	_pending_signals.clear()
	_plugin = null


func is_authenticated() -> bool:
	return _authenticated


func authenticate() -> GameServicesRequest:
	var request := _new_request(&"authenticate")
	_queue_signal("userAuthenticated", request)
	_plugin.call("signIn")
	return request


func load_player() -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"load_player")
	var request := _new_request(&"load_player")
	_queue_signal("currentPlayerLoaded", request)
	_plugin.call("loadCurrentPlayer", true)
	return request


func unlock_achievement(platform_id: String) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"unlock_achievement")
	var request := _new_request(&"unlock_achievement")
	_queue_signal("achievementUnlocked", request, {"platform_id": platform_id})
	_plugin.call("unlockAchievement", platform_id)
	return request


func set_achievement_progress(
	platform_id: String,
	progress: float,
	total_steps: int = 0
) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"set_achievement_progress")
	if total_steps <= 0:
		var invalid := _new_request(&"set_achievement_progress")
		invalid.complete(GameServicesResult.failure(
			&"set_achievement_progress",
			GameServicesResult.Code.NOT_CONFIGURED,
			"Google incremental achievements require a positive total-step count",
			provider_name()
		))
		return invalid
	var normalized_progress := clampf(progress, 0.0, 1.0)
	var steps := ceili(normalized_progress * total_steps)
	if steps <= 0:
		var noop := _new_request(&"set_achievement_progress")
		noop.complete(GameServicesResult.success(
			&"set_achievement_progress",
			{"platform_id": platform_id, "progress": 0.0, "submitted": false},
			provider_name()
		))
		return noop
	var request := _new_request(&"set_achievement_progress")
	_queue_signal("achievementUnlocked", request, {
		"platform_id": platform_id,
		"progress": normalized_progress,
		"steps": steps,
		"total_steps": total_steps,
	})
	_plugin.call("setAchievementSteps", platform_id, steps)
	return request


func load_achievements(force_reload: bool = false) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"load_achievements")
	var request := _new_request(&"load_achievements")
	_queue_signal("achievementsLoaded", request)
	_plugin.call("loadAchievements", force_reload)
	return request


func submit_score(platform_id: String, score: int) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"submit_score")
	var request := _new_request(&"submit_score")
	_queue_signal("scoreSubmitted", request, {
		"platform_id": platform_id,
		"score": score,
	})
	_plugin.call("submitScore", platform_id, score)
	return request


func show_achievements() -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"show_achievements")
	_plugin.call("showAchievements")
	return _immediate_success(&"show_achievements", {"presentation_accepted": true})


func show_leaderboards(platform_id: String = "") -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"show_leaderboards")
	if platform_id.is_empty():
		_plugin.call("showAllLeaderboards")
	else:
		_plugin.call("showLeaderboard", platform_id)
	return _immediate_success(&"show_leaderboards", {
		"presentation_accepted": true,
		"platform_id": platform_id,
	})


func request_server_credentials(options: Dictionary = {}) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"request_server_credentials")
	var client_id := str(options.get("server_client_id", config.google_server_client_id))
	if client_id.is_empty():
		var missing := _new_request(&"request_server_credentials")
		missing.complete(GameServicesResult.failure(
			&"request_server_credentials",
			GameServicesResult.Code.NOT_CONFIGURED,
			"google_server_client_id is required for server credentials",
			provider_name()
		))
		return missing
	var request := _new_request(&"request_server_credentials")
	_queue_signal("serverSideAccessRequested", request)
	_plugin.call(
		"requestServerSideAccess",
		client_id,
		bool(options.get("force_refresh_token", false))
	)
	return request


func save_game(name: String, data: PackedByteArray, metadata: Dictionary = {}) -> GameServicesRequest:
	if not supports(Capability.CLOUD_SAVES):
		return _unsupported(&"save_game")
	if not _authenticated:
		return _not_authenticated(&"save_game")
	var request := _new_request(&"save_game")
	_queue_signal("gameSaved", request, {"name": name})
	_plugin.call(
		"saveGame",
		name,
		str(metadata.get("description", "")),
		data,
		int(metadata.get("played_time_msec", 0)),
		int(metadata.get("progress_value", 0))
	)
	return request


func load_game(name: String) -> GameServicesRequest:
	if not supports(Capability.CLOUD_SAVES):
		return _unsupported(&"load_game")
	if not _authenticated:
		return _not_authenticated(&"load_game")
	var request := _new_request(&"load_game")
	_queue_signal("gameLoaded", request, {"name": name})
	_plugin.call("loadGame", name, false)
	return request


func list_saved_games(force_reload: bool = false) -> GameServicesRequest:
	if not supports(Capability.CLOUD_SAVES):
		return _unsupported(&"list_saved_games")
	if not _authenticated:
		return _not_authenticated(&"list_saved_games")
	var request := _new_request(&"list_saved_games")
	_queue_signal("snapshotsLoaded", request)
	_plugin.call("loadSnapshots", force_reload)
	return request


func delete_saved_game(id: String) -> GameServicesRequest:
	if not supports(Capability.CLOUD_SAVES):
		return _unsupported(&"delete_saved_game")
	if not _authenticated:
		return _not_authenticated(&"delete_saved_game")
	var request := _new_request(&"delete_saved_game")
	_queue_signal("snapshotDeleted", request, {"id": id})
	_plugin.call("deleteSnapshot", id)
	return request


func resolve_saved_game_conflict(
	conflict_id: String,
	snapshot_id: String,
	data: PackedByteArray,
	metadata: Dictionary = {}
) -> GameServicesRequest:
	if not supports(Capability.CLOUD_SAVES):
		return _unsupported(&"resolve_saved_game_conflict")
	if not _authenticated:
		return _not_authenticated(&"resolve_saved_game_conflict")
	if snapshot_id.is_empty():
		var invalid := _new_request(&"resolve_saved_game_conflict")
		invalid.complete(GameServicesResult.failure(
			&"resolve_saved_game_conflict",
			GameServicesResult.Code.INVALID_ARGUMENT,
			"Google Play Games Services requires a selected snapshot ID",
			provider_name()
		))
		return invalid
	var request := _new_request(&"resolve_saved_game_conflict")
	_queue_signal("conflictResolved", request, {"conflict_id": conflict_id})
	_plugin.call(
		"resolveSnapshotConflict",
		conflict_id,
		snapshot_id,
		data,
		str(metadata.get("description", "")),
		int(metadata.get("played_time_msec", 0)),
		int(metadata.get("progress_value", 0))
	)
	return request


func _connect_native_signals() -> void:
	_connect_native("userAuthenticated", "_on_user_authenticated")
	_connect_native("currentPlayerLoaded", "_on_current_player_loaded")
	_connect_native("achievementUnlocked", "_on_achievement_unlocked")
	_connect_native("achievementsLoaded", "_on_achievements_loaded")
	_connect_native("scoreSubmitted", "_on_score_submitted")
	_connect_native("serverSideAccessRequested", "_on_server_access_requested")
	_connect_native("gameSaved", "_on_game_saved")
	_connect_native("gameLoaded", "_on_game_loaded")
	_connect_native("conflictEmitted", "_on_conflict_emitted")
	_connect_native("conflictResolved", "_on_conflict_resolved")
	_connect_native("snapshotsLoaded", "_on_snapshots_loaded")
	_connect_native("snapshotDeleted", "_on_snapshot_deleted")


func _connect_native(signal_name: StringName, method_name: StringName) -> void:
	var callable := Callable(self, method_name)
	if _plugin.has_signal(signal_name) and not _plugin.is_connected(signal_name, callable):
		_plugin.connect(signal_name, callable)


func _on_user_authenticated(authenticated: bool) -> void:
	_authenticated = authenticated
	if not authenticated:
		_player.clear()
	authentication_changed.emit(authenticated, _player.duplicate(true))
	var item := _take_signal("userAuthenticated")
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	if authenticated:
		request.complete(GameServicesResult.success(
			&"authenticate",
			{"authenticated": true},
			provider_name()
		))
	else:
		request.complete(_signal_failure(
			&"authenticate",
			"Play Games Services did not authenticate the player",
			{"authenticated": false}
		))


func _on_current_player_loaded(player_json: String) -> void:
	var item := _take_signal("currentPlayerLoaded")
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var parsed := _parse_json_dictionary(player_json)
	if parsed.is_empty():
		request.complete(_signal_failure(
			&"load_player",
			"Play Games Services did not return a player"
		))
		return
	_player = {
		"id": str(parsed.get("playerId", "")),
		"display_name": str(parsed.get("displayName", "")),
		"alias": str(parsed.get("displayName", "")),
		"provider": String(provider_name()),
		"avatar_uri": str(parsed.get("iconImageUri", "")),
		"raw": parsed,
	}
	request.complete(GameServicesResult.success(
		&"load_player",
		_player.duplicate(true),
		provider_name()
	))


func _on_achievement_unlocked(unlocked: bool, platform_id: String) -> void:
	var item := _take_matching_signal("achievementUnlocked", "platform_id", platform_id)
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var context: Dictionary = item["context"]
	if request.operation == &"unlock_achievement" and not unlocked:
		request.complete(_signal_failure(
			request.operation,
			"Play Games Services did not unlock the achievement",
			context
		))
		return
	context["unlocked"] = unlocked
	request.complete(GameServicesResult.success(request.operation, context, provider_name()))


func _on_achievements_loaded(achievements_json: String) -> void:
	var item := _take_signal("achievementsLoaded")
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var parsed := JSON.parse_string(achievements_json)
	var achievements: Array[Dictionary] = []
	if parsed is Array:
		for value: Variant in parsed:
			if value is not Dictionary:
				continue
			var total_steps := int(value.get("totalSteps", 0))
			var current_steps := int(value.get("currentSteps", 0))
			var unlocked := str(value.get("state", "")) == "STATE_UNLOCKED"
			var progress := 1.0 if unlocked else 0.0
			if total_steps > 0:
				progress = clampf(float(current_steps) / float(total_steps), 0.0, 1.0)
			achievements.append({
				"platform_id": str(value.get("achievementId", "")),
				"name": str(value.get("name", "")),
				"description": str(value.get("description", "")),
				"progress": progress,
				"unlocked": unlocked,
				"hidden": str(value.get("state", "")) == "STATE_HIDDEN",
				"raw": value.duplicate(true),
			})
	request.complete(GameServicesResult.success(
		&"load_achievements",
		achievements,
		provider_name()
	))


func _on_score_submitted(submitted: bool, platform_id: String) -> void:
	var item := _take_matching_signal("scoreSubmitted", "platform_id", platform_id)
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var context: Dictionary = item["context"]
	if submitted:
		request.complete(GameServicesResult.success(request.operation, context, provider_name()))
	else:
		request.complete(_signal_failure(
			request.operation,
			"Play Games Services rejected the score",
			context
		))


func _on_server_access_requested(token: String) -> void:
	var item := _take_signal("serverSideAccessRequested")
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	if token.is_empty():
		request.complete(_signal_failure(
			&"request_server_credentials",
			"Play Games Services returned an empty server authorization code"
		))
	else:
		request.complete(GameServicesResult.success(
			&"request_server_credentials",
			{"kind": "play_games_server_auth_code", "authorization_code": token},
			provider_name()
		))


func _on_game_saved(saved: bool, name: String, description: String) -> void:
	var item := _take_matching_signal("gameSaved", "name", name)
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var data := {"id": name, "name": name, "description": description}
	if saved:
		request.complete(GameServicesResult.success(&"save_game", data, provider_name()))
	else:
		request.complete(_signal_failure(&"save_game", "Play Games Services did not save the game", data))


func _on_game_loaded(snapshot_json: String, name: String = "") -> void:
	var item := (
		_take_matching_signal("gameLoaded", "name", name)
		if not name.is_empty()
		else _take_signal("gameLoaded")
	)
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var parsed := _parse_json_dictionary(snapshot_json)
	if parsed.is_empty():
		request.complete(GameServicesResult.failure(
			&"load_game",
			GameServicesResult.Code.NOT_FOUND,
			"The saved game was not found",
			provider_name()
		))
		return
	if parsed.has("error"):
		request.complete(GameServicesResult.failure(
			&"load_game",
			GameServicesResult.Code.PLATFORM_ERROR,
			str(parsed.get("error", "Play Games Services failed to load the saved game")),
			provider_name(),
			parsed.get("errorCode"),
			{"raw": parsed}
		))
		return
	var metadata := _normalize_snapshot_metadata(parsed.get("metadata", {}))
	request.complete(GameServicesResult.success(
		&"load_game",
		{
			"data": PackedByteArray(parsed.get("content", [])),
			"metadata": metadata,
			"raw": parsed,
		},
		provider_name()
	))


func _on_conflict_emitted(conflict_json: String) -> void:
	var parsed := _parse_json_dictionary(conflict_json)
	var signal_name: String
	match str(parsed.get("origin", "")):
		"SAVE":
			signal_name = "gameSaved"
		"RESOLVE":
			signal_name = "conflictResolved"
		_:
			signal_name = "gameLoaded"
	var normalized := _normalize_snapshot_conflict(parsed)
	var name := ""
	if not normalized.snapshots.is_empty():
		name = str(normalized.snapshots[0].metadata.get("name", ""))
	var item := (
		_take_matching_signal(signal_name, "name", name)
		if signal_name != "conflictResolved" and not name.is_empty()
		else _take_signal(signal_name)
	)
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	request.complete(GameServicesResult.failure(
		request.operation,
		GameServicesResult.Code.CONFLICT,
		"Cloud-save conflict requires resolution",
		provider_name(),
		null,
		normalized
	))


func _on_conflict_resolved(resolved: bool, payload_json: String) -> void:
	var item := _take_signal("conflictResolved")
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var parsed := _parse_json_dictionary(payload_json)
	if not resolved:
		request.complete(_signal_failure(
			&"resolve_saved_game_conflict",
			str(parsed.get("error", "Play Games Services did not resolve the conflict")),
			{"raw": parsed}
		))
		return
	request.complete(GameServicesResult.success(
		&"resolve_saved_game_conflict",
		{
			"data": PackedByteArray(parsed.get("content", [])),
			"metadata": _normalize_snapshot_metadata(parsed.get("metadata", {})),
			"raw": parsed,
		},
		provider_name()
	))


func _on_snapshots_loaded(snapshots_json: String) -> void:
	var item := _take_signal("snapshotsLoaded")
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var parsed := JSON.parse_string(snapshots_json)
	if parsed is Dictionary and parsed.has("error"):
		request.complete(_signal_failure(
			&"list_saved_games",
			str(parsed.get("error", "Play Games Services failed to list saved games")),
			{"raw": parsed}
		))
		return
	if parsed is not Array:
		request.complete(_signal_failure(
			&"list_saved_games",
			"Play Games Services returned an invalid saved-game list"
		))
		return
	var snapshots: Array[Dictionary] = []
	for value: Variant in parsed:
		if value is Dictionary:
			snapshots.append(_normalize_snapshot_metadata(value))
	request.complete(GameServicesResult.success(
		&"list_saved_games",
		snapshots,
		provider_name()
	))


func _on_snapshot_deleted(deleted: bool, snapshot_id: String) -> void:
	var item := _take_matching_signal("snapshotDeleted", "id", snapshot_id)
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var data := {"id": snapshot_id, "deleted": deleted}
	if deleted:
		request.complete(GameServicesResult.success(&"delete_saved_game", data, provider_name()))
	else:
		request.complete(_signal_failure(
			&"delete_saved_game",
			"Play Games Services did not delete the saved game",
			data
		))


func _normalize_snapshot_metadata(value: Dictionary) -> Dictionary:
	return {
		"id": str(value.get("snapshotId", "")),
		"name": str(value.get("uniqueName", "")),
		"description": str(value.get("description", "")),
		"updated_at_msec": int(value.get("lastModifiedTimestamp", 0)),
		"played_time_msec": int(value.get("playedTime", 0)),
		"progress_value": int(value.get("progressValue", 0)),
		"raw": value.duplicate(true),
	}


func _normalize_snapshot_conflict(value: Dictionary) -> Dictionary:
	var snapshots: Array[Dictionary] = []
	for key in ["serverSnapshot", "conflictingSnapshot"]:
		var snapshot: Variant = value.get(key, {})
		if snapshot is not Dictionary:
			continue
		snapshots.append({
			"id": str(snapshot.get("metadata", {}).get("snapshotId", "")),
			"data": PackedByteArray(snapshot.get("content", [])),
			"metadata": _normalize_snapshot_metadata(snapshot.get("metadata", {})),
			"raw": snapshot.duplicate(true),
		})
	return {
		"conflict_id": str(value.get("conflictId", "")),
		"snapshots": snapshots,
		"raw": value.duplicate(true),
	}


func _parse_json_dictionary(json: String) -> Dictionary:
	var parsed := JSON.parse_string(json)
	return parsed if parsed is Dictionary else {}


func _queue_signal(
	signal_name: String,
	request: GameServicesRequest,
	context: Dictionary = {}
) -> void:
	if not _pending_signals.has(signal_name):
		_pending_signals[signal_name] = []
	_pending_signals[signal_name].append({
		"request": request,
		"context": context.duplicate(true),
	})


func _take_signal(signal_name: String) -> Dictionary:
	if not _pending_signals.has(signal_name):
		return {}
	var queue: Array = _pending_signals[signal_name]
	if queue.is_empty():
		_pending_signals.erase(signal_name)
		return {}
	var item: Dictionary = queue.pop_front()
	if queue.is_empty():
		_pending_signals.erase(signal_name)
	return item


func _take_matching_signal(signal_name: String, key: String, value: Variant) -> Dictionary:
	if not _pending_signals.has(signal_name):
		return {}
	var queue: Array = _pending_signals[signal_name]
	for index in queue.size():
		var item: Dictionary = queue[index]
		if item["context"].get(key) == value:
			queue.remove_at(index)
			if queue.is_empty():
				_pending_signals.erase(signal_name)
			return item
	return {}


func _immediate_success(operation: StringName, data: Variant = null) -> GameServicesRequest:
	var request := _new_request(operation)
	request.complete(GameServicesResult.success(operation, data, provider_name()))
	return request


func _signal_failure(
	operation: StringName,
	message: String,
	data: Variant = null
) -> GameServicesResult:
	return GameServicesResult.failure(
		operation,
		GameServicesResult.Code.PLATFORM_ERROR,
		message,
		provider_name(),
		null,
		data
	)
