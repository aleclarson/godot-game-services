class_name MockGameServicesProvider
extends GameServicesProvider

## Stateful provider used in the editor and in automated tests.

var _authenticated: bool = false
var _player: Dictionary = {}
var _achievement_progress: Dictionary = {}
var _scores: Dictionary = {}
var _saved_games: Dictionary = {}


func provider_name() -> StringName:
	return &"mock"


func capabilities() -> int:
	return (
		Capability.AUTHENTICATION
		| Capability.PLAYER_PROFILE
		| Capability.ACHIEVEMENTS
		| Capability.ACHIEVEMENT_PROGRESS
		| Capability.LEADERBOARDS
		| Capability.PLATFORM_UI
		| Capability.CLOUD_SAVES
		| Capability.SERVER_CREDENTIALS
	)


func initialize(p_config: GameServicesConfig) -> GameServicesResult:
	var result := super.initialize(p_config)
	_player = config.mock_player()
	return result


func is_authenticated() -> bool:
	return _authenticated


func authenticate() -> GameServicesRequest:
	var request := _new_request(&"authenticate")
	call_deferred("_finish_authentication", request)
	return request


func _finish_authentication(request: GameServicesRequest) -> void:
	_authenticated = true
	authentication_changed.emit(true, _player.duplicate(true))
	request.complete(GameServicesResult.success(
		&"authenticate",
		{"authenticated": true, "player": _player.duplicate(true)},
		provider_name()
	))


func load_player() -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"load_player")
	var request := _new_request(&"load_player")
	_complete_later(request, GameServicesResult.success(
		&"load_player",
		_player.duplicate(true),
		provider_name()
	))
	return request


func unlock_achievement(platform_id: String) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"unlock_achievement")
	_achievement_progress[platform_id] = 1.0
	return _deferred_success(&"unlock_achievement", {
		"platform_id": platform_id,
		"progress": 1.0,
		"unlocked": true,
	})


func set_achievement_progress(
	platform_id: String,
	progress: float,
	_total_steps: int = 0
) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"set_achievement_progress")
	var normalized_progress := clampf(progress, 0.0, 1.0)
	var previous := float(_achievement_progress.get(platform_id, 0.0))
	_achievement_progress[platform_id] = maxf(previous, normalized_progress)
	return _deferred_success(&"set_achievement_progress", {
		"platform_id": platform_id,
		"progress": _achievement_progress[platform_id],
		"unlocked": _achievement_progress[platform_id] >= 1.0,
	})


func load_achievements(_force_reload: bool = false) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"load_achievements")
	var achievements: Array[Dictionary] = []
	for platform_id: Variant in _achievement_progress:
		var progress := float(_achievement_progress[platform_id])
		achievements.append({
			"platform_id": str(platform_id),
			"progress": progress,
			"unlocked": progress >= 1.0,
		})
	return _deferred_success(&"load_achievements", achievements)


func submit_score(platform_id: String, score: int) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"submit_score")
	_scores[platform_id] = score
	return _deferred_success(&"submit_score", {
		"platform_id": platform_id,
		"score": score,
	})


func show_achievements() -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"show_achievements")
	return _deferred_success(&"show_achievements", {"presentation_accepted": true})


func show_leaderboards(platform_id: String = "") -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"show_leaderboards")
	return _deferred_success(&"show_leaderboards", {
		"presentation_accepted": true,
		"platform_id": platform_id,
	})


func request_server_credentials(_options: Dictionary = {}) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"request_server_credentials")
	return _deferred_success(&"request_server_credentials", {
		"kind": "mock",
		"token": "mock-server-credential",
	})


func save_game(name: String, data: PackedByteArray, metadata: Dictionary = {}) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"save_game")
	var saved_metadata := metadata.duplicate(true)
	saved_metadata.merge({
		"id": name,
		"name": name,
		"updated_at_msec": Time.get_unix_time_from_system() * 1000.0,
	}, true)
	_saved_games[name] = {
		"data": data.duplicate(),
		"metadata": saved_metadata,
	}
	return _deferred_success(&"save_game", saved_metadata.duplicate(true))


func load_game(name: String) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"load_game")
	if not _saved_games.has(name):
		var missing := _new_request(&"load_game")
		_complete_later(missing, GameServicesResult.failure(
			&"load_game",
			GameServicesResult.Code.NOT_FOUND,
			"Saved game '%s' does not exist" % name,
			provider_name()
		))
		return missing
	return _deferred_success(&"load_game", _saved_games[name].duplicate(true))


func list_saved_games(_force_reload: bool = false) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"list_saved_games")
	var saves: Array[Dictionary] = []
	for name: Variant in _saved_games:
		saves.append(_saved_games[name].metadata.duplicate(true))
	return _deferred_success(&"list_saved_games", saves)


func delete_saved_game(id: String) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"delete_saved_game")
	var existed := _saved_games.erase(id)
	return _deferred_success(&"delete_saved_game", {"id": id, "deleted": existed})


func resolve_saved_game_conflict(
	conflict_id: String,
	_snapshot_id: String,
	_data: PackedByteArray,
	_metadata: Dictionary = {}
) -> GameServicesRequest:
	if not _authenticated:
		return _not_authenticated(&"resolve_saved_game_conflict")
	var request := _new_request(&"resolve_saved_game_conflict")
	_complete_later(request, GameServicesResult.failure(
		&"resolve_saved_game_conflict",
		GameServicesResult.Code.NOT_FOUND,
		"Mock conflict '%s' does not exist" % conflict_id,
		provider_name()
	))
	return request


func _deferred_success(operation: StringName, data: Variant = null) -> GameServicesRequest:
	var request := _new_request(operation)
	_complete_later(request, GameServicesResult.success(operation, data, provider_name()))
	return request
