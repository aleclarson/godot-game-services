class_name AppleGameCenterProvider
extends GameServicesProvider

## Adapter for the `GameCenter` singleton from godot-ios-plugins.

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
var _pending_events: Dictionary = {}
var _capabilities: int = BASE_CAPABILITIES


func _ready() -> void:
	set_process(false)


func provider_name() -> StringName:
	return &"apple_game_center"


func capabilities() -> int:
	return _capabilities


func initialize(p_config: GameServicesConfig) -> GameServicesResult:
	config = p_config
	_capabilities = BASE_CAPABILITIES
	if not Engine.has_singleton("GameCenter"):
		return GameServicesResult.failure(
			&"initialize",
			GameServicesResult.Code.UNAVAILABLE,
			"The GameCenter native singleton is not installed",
			provider_name()
		)
	_plugin = Engine.get_singleton("GameCenter")
	if (
		_plugin.has_method("save_game")
		and _plugin.has_method("load_game")
		and _plugin.has_method("list_saved_games")
		and _plugin.has_method("delete_saved_game")
		and _plugin.has_method("resolve_saved_game_conflict")
	):
		_capabilities |= Capability.CLOUD_SAVES
	_authenticated = bool(_plugin.call("is_authenticated"))
	set_process(true)
	return GameServicesResult.success(
		&"initialize",
		{"capabilities": capabilities()},
		provider_name()
	)


func shutdown() -> void:
	set_process(false)
	_pending_events.clear()
	_plugin = null


func is_authenticated() -> bool:
	return _authenticated


func authenticate() -> GameServicesRequest:
	var request := _new_request(&"authenticate")
	_queue_event("authentication", request)
	var native_error := int(_plugin.call("authenticate"))
	if native_error != OK:
		_remove_request("authentication", request)
		request.complete(_native_failure(&"authenticate", native_error))
	return request


func load_player() -> GameServicesRequest:
	if not _authenticated or _player.is_empty():
		return _not_authenticated(&"load_player")
	var request := _new_request(&"load_player")
	_complete_later(request, GameServicesResult.success(
		&"load_player",
		_player.duplicate(true),
		provider_name()
	))
	return request


func unlock_achievement(platform_id: String) -> GameServicesRequest:
	return _report_achievement(&"unlock_achievement", platform_id, 1.0)


func set_achievement_progress(
	platform_id: String,
	progress: float,
	_total_steps: int = 0
) -> GameServicesRequest:
	return _report_achievement(
		&"set_achievement_progress",
		platform_id,
		clampf(progress, 0.0, 1.0)
	)


func _report_achievement(
	operation: StringName,
	platform_id: String,
	progress: float
) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(operation)
	var request := _new_request(operation)
	var context := {"platform_id": platform_id, "progress": progress}
	_queue_event("award_achievement", request, context)
	var native_error := int(_plugin.call("award_achievement", {
		"name": platform_id,
		"progress": progress * 100.0,
	}))
	if native_error != OK:
		_remove_request("award_achievement", request)
		request.complete(_native_failure(operation, native_error, context))
	return request


func load_achievements(_force_reload: bool = false) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"load_achievements")
	var request := _new_request(&"load_achievements")
	_queue_event("achievements", request)
	_plugin.call("request_achievements")
	return request


func submit_score(platform_id: String, score: int) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"submit_score")
	# Older upstream builds read the score into a float before assigning GameKit's
	# Int64. The bundled bridge also has saved-game methods and fixes that bug.
	if not _plugin.has_method("save_game") and absi(score) > 16_777_216:
		var invalid := _new_request(&"submit_score")
		invalid.complete(GameServicesResult.failure(
			&"submit_score",
			GameServicesResult.Code.UNSUPPORTED,
			"The installed GameCenter bridge cannot submit this integer without precision loss",
			provider_name(),
			null,
			{"platform_id": platform_id, "score": score}
		))
		return invalid
	var request := _new_request(&"submit_score")
	var context := {"platform_id": platform_id, "score": score}
	_queue_event("post_score", request, context)
	var native_error := int(_plugin.call("post_score", {
		"category": platform_id,
		"score": score,
	}))
	if native_error != OK:
		_remove_request("post_score", request)
		request.complete(_native_failure(&"submit_score", native_error, context))
	return request


func show_achievements() -> GameServicesRequest:
	return _show_game_center(&"show_achievements", {"view": "achievements"})


func show_leaderboards(platform_id: String = "") -> GameServicesRequest:
	var options := {"view": "leaderboards"}
	if not platform_id.is_empty():
		options["leaderboard_name"] = platform_id
	return _show_game_center(&"show_leaderboards", options)


func _show_game_center(operation: StringName, options: Dictionary) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(operation)
	var request := _new_request(operation)
	var native_error := int(_plugin.call("show_game_center", options))
	if native_error == OK:
		request.complete(GameServicesResult.success(
			operation,
			{"presentation_accepted": true},
			provider_name()
		))
	else:
		request.complete(_native_failure(operation, native_error))
	return request


func request_server_credentials(_options: Dictionary = {}) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"request_server_credentials")
	var request := _new_request(&"request_server_credentials")
	_queue_event("identity_verification_signature", request)
	var native_error := int(_plugin.call("request_identity_verification_signature"))
	if native_error != OK:
		_remove_request("identity_verification_signature", request)
		request.complete(_native_failure(&"request_server_credentials", native_error))
	return request


func save_game(name: String, data: PackedByteArray, metadata: Dictionary = {}) -> GameServicesRequest:
	if not supports(Capability.CLOUD_SAVES):
		return _unsupported(&"save_game")
	if not _authenticated:
		return _not_authenticated(&"save_game")
	var request := _new_request(&"save_game")
	_queue_event("save_game", request, {"name": name, "metadata": metadata})
	var native_error := int(_plugin.call("save_game", {"name": name, "data": data}))
	if native_error != OK:
		_remove_request("save_game", request)
		request.complete(_native_failure(&"save_game", native_error, {"name": name}))
	return request


func load_game(name: String) -> GameServicesRequest:
	if not supports(Capability.CLOUD_SAVES):
		return _unsupported(&"load_game")
	if not _authenticated:
		return _not_authenticated(&"load_game")
	var request := _new_request(&"load_game")
	_queue_event("load_game", request, {"name": name})
	_plugin.call("load_game", name)
	return request


func list_saved_games(_force_reload: bool = false) -> GameServicesRequest:
	if not supports(Capability.CLOUD_SAVES):
		return _unsupported(&"list_saved_games")
	if not _authenticated:
		return _not_authenticated(&"list_saved_games")
	var request := _new_request(&"list_saved_games")
	_queue_event("list_saved_games", request)
	_plugin.call("list_saved_games")
	return request


func delete_saved_game(id: String) -> GameServicesRequest:
	if not supports(Capability.CLOUD_SAVES):
		return _unsupported(&"delete_saved_game")
	if not _authenticated:
		return _not_authenticated(&"delete_saved_game")
	var request := _new_request(&"delete_saved_game")
	_queue_event("delete_saved_game", request, {"id": id})
	_plugin.call("delete_saved_game", id)
	return request


func resolve_saved_game_conflict(
	conflict_id: String,
	_snapshot_id: String,
	data: PackedByteArray,
	_metadata: Dictionary = {}
) -> GameServicesRequest:
	if not supports(Capability.CLOUD_SAVES):
		return _unsupported(&"resolve_saved_game_conflict")
	if not _authenticated:
		return _not_authenticated(&"resolve_saved_game_conflict")
	var request := _new_request(&"resolve_saved_game_conflict")
	_queue_event("resolve_saved_game_conflict", request, {"conflict_id": conflict_id})
	var native_error := int(_plugin.call("resolve_saved_game_conflict", {
		"conflict_id": conflict_id,
		"data": data,
	}))
	if native_error != OK:
		_remove_request("resolve_saved_game_conflict", request)
		request.complete(_native_failure(
			&"resolve_saved_game_conflict",
			native_error,
			{"conflict_id": conflict_id}
		))
	return request


func _process(_delta: float) -> void:
	if not is_instance_valid(_plugin):
		return
	while int(_plugin.call("get_pending_event_count")) > 0:
		var event: Variant = _plugin.call("pop_pending_event")
		if event is Dictionary:
			_dispatch_event(event)


func _dispatch_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	match event_type:
		"authentication":
			_handle_authentication(event)
		"achievements":
			_handle_achievements(event)
		"award_achievement", "post_score", "identity_verification_signature":
			_handle_standard_event(event_type, event)
		"save_game", "load_game", "list_saved_games", "delete_saved_game", "resolve_saved_game_conflict":
			_handle_saved_game_event(event_type, event)


func _handle_authentication(event: Dictionary) -> void:
	var item := _take_event("authentication")
	var succeeded: bool = event.get("result") == "ok"
	_authenticated = succeeded
	if succeeded:
		_player = {
			"id": str(event.get("player_id", "")),
			"display_name": str(event.get("displayName", "")),
			"alias": str(event.get("alias", "")),
			"provider": String(provider_name()),
			"raw": event.duplicate(true),
		}
	else:
		_player.clear()
	authentication_changed.emit(_authenticated, _player.duplicate(true))
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	if succeeded:
		request.complete(GameServicesResult.success(
			&"authenticate",
			{"authenticated": true, "player": _player.duplicate(true)},
			provider_name()
		))
	else:
		request.complete(GameServicesResult.failure(
			&"authenticate",
			GameServicesResult.Code.PLATFORM_ERROR,
			str(event.get("error_description", "Game Center authentication failed")),
			provider_name(),
			event.get("error_code"),
			{"raw": event.duplicate(true)}
		))


func _handle_achievements(event: Dictionary) -> void:
	var item := _take_event("achievements")
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	if event.get("result") != "ok":
		request.complete(_event_failure(request.operation, event))
		return
	var names: Variant = event.get("names", [])
	var percentages: Variant = event.get("progress", [])
	var achievements: Array[Dictionary] = []
	for index in mini(names.size(), percentages.size()):
		var progress := clampf(float(percentages[index]) / 100.0, 0.0, 1.0)
		achievements.append({
			"platform_id": str(names[index]),
			"progress": progress,
			"unlocked": progress >= 1.0,
		})
	request.complete(GameServicesResult.success(
		&"load_achievements",
		achievements,
		provider_name()
	))


func _handle_standard_event(event_type: String, event: Dictionary) -> void:
	var item: Dictionary
	var platform_id := str(event.get("platform_id", ""))
	if not platform_id.is_empty():
		item = _take_matching_event(event_type, "platform_id", platform_id)
	else:
		item = _take_event(event_type)
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var context: Dictionary = item["context"]
	if event.get("result") != "ok":
		request.complete(_event_failure(request.operation, event, context))
		return
	var data := context.duplicate(true)
	if event_type == "identity_verification_signature":
		data = {
			"kind": "game_center_identity_signature",
			"public_key_url": str(event.get("public_key_url", "")),
			"signature": str(event.get("signature", "")),
			"salt": str(event.get("salt", "")),
			"timestamp": event.get("timestamp"),
			"player_id": str(event.get("player_id", "")),
		}
	else:
		data["raw"] = event.duplicate(true)
	request.complete(GameServicesResult.success(request.operation, data, provider_name()))


func _handle_saved_game_event(event_type: String, event: Dictionary) -> void:
	var item: Dictionary
	match event_type:
		"save_game", "load_game":
			var name := str(event.get("name", event.get("saved_game", {}).get("name", "")))
			item = (
				_take_matching_event(event_type, "name", name)
				if not name.is_empty()
				else _take_event(event_type)
			)
		"delete_saved_game":
			var id := str(event.get("name", ""))
			item = (
				_take_matching_event(event_type, "id", id)
				if not id.is_empty()
				else _take_event(event_type)
			)
		"resolve_saved_game_conflict":
			var conflict_id := str(event.get("conflict_id", ""))
			item = (
				_take_matching_event(event_type, "conflict_id", conflict_id)
				if not conflict_id.is_empty()
				else _take_event(event_type)
			)
		_:
			item = _take_event(event_type)
	if item.is_empty():
		return
	var request: GameServicesRequest = item["request"]
	var context: Dictionary = item["context"]
	var event_result := str(event.get("result", "error"))
	if event_result == "conflict":
		var candidates: Array[Dictionary] = []
		for value: Variant in event.get("saved_games", []):
			if value is Dictionary:
				candidates.append(_normalize_conflict_snapshot(value))
		request.complete(GameServicesResult.failure(
			request.operation,
			GameServicesResult.Code.CONFLICT,
			"Cloud-save conflict requires resolution",
			provider_name(),
			null,
			{
				"conflict_id": str(event.get("conflict_id", "")),
				"snapshots": candidates,
				"raw": event.duplicate(true),
			}
		))
		return
	if event_result != "ok":
		var code := (
			GameServicesResult.Code.NOT_FOUND
			if event_result == "not_found"
			else GameServicesResult.Code.PLATFORM_ERROR
		)
		request.complete(GameServicesResult.failure(
			request.operation,
			code,
			str(event.get("error_description", "Game Center saved-game operation failed")),
			provider_name(),
			event.get("error_code"),
			{"raw": event.duplicate(true)}
		))
		return

	var data: Variant
	match event_type:
		"save_game":
			data = _normalize_saved_game(event.get("saved_game", {}))
		"load_game":
			data = {
				"data": event.get("data", PackedByteArray()),
				"metadata": _normalize_saved_game(event.get("saved_game", {})),
				"raw": event.duplicate(true),
			}
		"list_saved_games":
			var saves: Array[Dictionary] = []
			for value: Variant in event.get("saved_games", []):
				if value is Dictionary:
					saves.append(_normalize_saved_game(value))
			data = saves
		"delete_saved_game":
			data = {"id": str(context.get("id", event.get("name", ""))), "deleted": true}
		"resolve_saved_game_conflict":
			var resolved: Array[Dictionary] = []
			for value: Variant in event.get("saved_games", []):
				if value is Dictionary:
					resolved.append(_normalize_saved_game(value))
			data = {
				"conflict_id": str(event.get("conflict_id", context.get("conflict_id", ""))),
				"snapshots": resolved,
			}
	request.complete(GameServicesResult.success(request.operation, data, provider_name()))


func _normalize_saved_game(value: Dictionary) -> Dictionary:
	return {
		"id": str(value.get("id", value.get("name", ""))),
		"name": str(value.get("name", "")),
		"device_name": str(value.get("device_name", "")),
		"updated_at_msec": int(value.get("updated_at_msec", 0)),
		"raw": value.duplicate(true),
	}


func _normalize_conflict_snapshot(value: Dictionary) -> Dictionary:
	var metadata := _normalize_saved_game(value)
	return {
		"id": metadata.id,
		"data": value.get("data", PackedByteArray()),
		"metadata": metadata,
		"raw": value.duplicate(true),
	}


func _queue_event(
	event_type: String,
	request: GameServicesRequest,
	context: Dictionary = {}
) -> void:
	if not _pending_events.has(event_type):
		_pending_events[event_type] = []
	_pending_events[event_type].append({
		"request": request,
		"context": context.duplicate(true),
	})


func _take_event(event_type: String) -> Dictionary:
	if not _pending_events.has(event_type):
		return {}
	var queue: Array = _pending_events[event_type]
	if queue.is_empty():
		_pending_events.erase(event_type)
		return {}
	var item: Dictionary = queue.pop_front()
	if queue.is_empty():
		_pending_events.erase(event_type)
	return item


func _take_matching_event(event_type: String, key: String, value: Variant) -> Dictionary:
	if not _pending_events.has(event_type):
		return {}
	var queue: Array = _pending_events[event_type]
	for index in queue.size():
		var item: Dictionary = queue[index]
		if item["context"].get(key) == value:
			queue.remove_at(index)
			if queue.is_empty():
				_pending_events.erase(event_type)
			return item
	return {}


func _remove_request(event_type: String, request: GameServicesRequest) -> void:
	if not _pending_events.has(event_type):
		return
	var queue: Array = _pending_events[event_type]
	for index in range(queue.size() - 1, -1, -1):
		if queue[index]["request"] == request:
			queue.remove_at(index)
	if queue.is_empty():
		_pending_events.erase(event_type)


func _native_failure(
	operation: StringName,
	native_error: int,
	data: Variant = null
) -> GameServicesResult:
	return GameServicesResult.failure(
		operation,
		GameServicesResult.Code.PLATFORM_ERROR,
		"Game Center rejected %s with Godot error %d" % [operation, native_error],
		provider_name(),
		native_error,
		data
	)


func _event_failure(
	operation: StringName,
	event: Dictionary,
	context: Dictionary = {}
) -> GameServicesResult:
	var data := context.duplicate(true)
	data["raw"] = event.duplicate(true)
	return GameServicesResult.failure(
		operation,
		GameServicesResult.Code.PLATFORM_ERROR,
		str(event.get("error_description", "Game Center operation failed")),
		provider_name(),
		event.get("error_code"),
		data
	)
