class_name GameServicesProvider
extends Node

## Adapter boundary implemented by native and mock providers.

signal authentication_changed(authenticated: bool, player: Dictionary)

enum Capability {
	AUTHENTICATION = 1 << 0,
	PLAYER_PROFILE = 1 << 1,
	ACHIEVEMENTS = 1 << 2,
	ACHIEVEMENT_PROGRESS = 1 << 3,
	LEADERBOARDS = 1 << 4,
	PLATFORM_UI = 1 << 5,
	CLOUD_SAVES = 1 << 6,
	SERVER_CREDENTIALS = 1 << 7,
}

var config: GameServicesConfig


func provider_name() -> StringName:
	return &"unavailable"


func capabilities() -> int:
	return 0


func supports(capability: Capability) -> bool:
	return (capabilities() & capability) == capability


func initialize(p_config: GameServicesConfig) -> GameServicesResult:
	config = p_config
	if provider_name() == &"unavailable":
		return GameServicesResult.failure(
			&"initialize",
			GameServicesResult.Code.UNAVAILABLE,
			"Game services are unavailable on this platform",
			provider_name()
		)
	return GameServicesResult.success(&"initialize", {"capabilities": capabilities()}, provider_name())


func shutdown() -> void:
	pass


func is_authenticated() -> bool:
	return false


func authenticate() -> GameServicesRequest:
	return _unsupported(&"authenticate")


func load_player() -> GameServicesRequest:
	return _unsupported(&"load_player")


func unlock_achievement(_platform_id: String) -> GameServicesRequest:
	return _unsupported(&"unlock_achievement")


func set_achievement_progress(
	_platform_id: String,
	_progress: float,
	_total_steps: int = 0
) -> GameServicesRequest:
	return _unsupported(&"set_achievement_progress")


func load_achievements(_force_reload: bool = false) -> GameServicesRequest:
	return _unsupported(&"load_achievements")


func submit_score(_platform_id: String, _score: int) -> GameServicesRequest:
	return _unsupported(&"submit_score")


func show_achievements() -> GameServicesRequest:
	return _unsupported(&"show_achievements")


func show_leaderboards(_platform_id: String = "") -> GameServicesRequest:
	return _unsupported(&"show_leaderboards")


func request_server_credentials(_options: Dictionary = {}) -> GameServicesRequest:
	return _unsupported(&"request_server_credentials")


func save_game(_name: String, _data: PackedByteArray, _metadata: Dictionary = {}) -> GameServicesRequest:
	return _unsupported(&"save_game")


func load_game(_name: String) -> GameServicesRequest:
	return _unsupported(&"load_game")


func list_saved_games(_force_reload: bool = false) -> GameServicesRequest:
	return _unsupported(&"list_saved_games")


func delete_saved_game(_id: String) -> GameServicesRequest:
	return _unsupported(&"delete_saved_game")


func resolve_saved_game_conflict(
	_conflict_id: String,
	_snapshot_id: String,
	_data: PackedByteArray,
	_metadata: Dictionary = {}
) -> GameServicesRequest:
	return _unsupported(&"resolve_saved_game_conflict")


func _new_request(operation: StringName) -> GameServicesRequest:
	return GameServicesRequest.new(operation)


func _unsupported(operation: StringName) -> GameServicesRequest:
	var request := _new_request(operation)
	request.complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.UNSUPPORTED,
		"%s does not support %s" % [provider_name(), operation],
		provider_name()
	))
	return request


func _not_authenticated(operation: StringName) -> GameServicesRequest:
	var request := _new_request(operation)
	request.complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.NOT_AUTHENTICATED,
		"Authenticate before calling %s" % operation,
		provider_name()
	))
	return request


func _complete_later(request: GameServicesRequest, result: GameServicesResult) -> void:
	call_deferred("_finish_request", request, result)


func _finish_request(request: GameServicesRequest, result: GameServicesResult) -> void:
	request.complete(result)
