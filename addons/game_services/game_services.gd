extends Node

## Normalized entry point for Apple Game Center and Google Play Games Services.

signal provider_changed(provider_name: StringName, capabilities: int)
signal authentication_changed(authenticated: bool, player: Dictionary)
signal request_finished(request: GameServicesRequest, result: GameServicesResult)

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

const DEFAULT_CONFIG_PATH := "res://game_services_config.tres"
const ALLOWED_SAVE_NAME_CHARACTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"

var auto_initialize: bool = true
var config: GameServicesConfig
var provider: GameServicesProvider
var cloud_saves: CloudSaveStore
var _provider_available: bool = false
var _active_requests: Dictionary[int, GameServicesRequest] = {}
var _request_notifications: Dictionary[int, bool] = {}


func _init() -> void:
	cloud_saves = CloudSaveStore.new(self)


func _ready() -> void:
	if auto_initialize:
		initialize()


func initialize(
	p_config: GameServicesConfig = null,
	provider_override: GameServicesProvider = null
) -> GameServicesResult:
	shutdown()
	config = p_config if p_config != null else _load_default_config()
	provider = provider_override if provider_override != null else _select_provider()
	add_child(provider)
	provider.authentication_changed.connect(_on_authentication_changed)
	var result := provider.initialize(config)
	_provider_available = result.ok
	provider_changed.emit(provider.provider_name(), capabilities())
	return result


func shutdown() -> void:
	cloud_saves._cancel_pending_requests(provider_name())
	_cancel_pending_requests(provider_name())
	_provider_available = false
	if not is_instance_valid(provider):
		provider = null
		return
	provider.shutdown()
	if provider.get_parent() == self:
		remove_child(provider)
	provider.queue_free()
	provider = null


func provider_name() -> StringName:
	return provider.provider_name() if is_instance_valid(provider) else &"unavailable"


func capabilities() -> int:
	return provider.capabilities() if _has_provider() else 0


func supports(capability: Capability) -> bool:
	return _has_provider() and provider.supports(capability as GameServicesProvider.Capability)


func is_authenticated() -> bool:
	return _has_provider() and provider.is_authenticated()


func authenticate() -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"authenticate")
	return _track(provider.authenticate())


func load_player() -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"load_player")
	return _track(provider.load_player())


func unlock_achievement(logical_id: StringName) -> GameServicesRequest:
	var resolution := _resolve_identifier(&"unlock_achievement", logical_id, true)
	if resolution is GameServicesRequest:
		return resolution
	var platform_id: String = resolution
	return _decorate_identifier(
		provider.unlock_achievement(platform_id),
		logical_id,
		platform_id
	)


func set_achievement_progress(
	logical_id: StringName,
	progress: float
) -> GameServicesRequest:
	if progress < 0.0 or progress > 1.0:
		return _invalid_request(
			&"set_achievement_progress",
			"Achievement progress must be between 0.0 and 1.0"
		)
	var resolution := _resolve_identifier(&"set_achievement_progress", logical_id, true)
	if resolution is GameServicesRequest:
		return resolution
	var platform_id: String = resolution
	var total_steps := config.achievement_total_steps(logical_id, provider_name())
	return _decorate_identifier(
		provider.set_achievement_progress(platform_id, progress, total_steps),
		logical_id,
		platform_id
	)


func load_achievements(force_reload: bool = false) -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"load_achievements")
	return _proxy_request(
		provider.load_achievements(force_reload),
		Callable(self, "_normalize_achievement_result")
	)


func submit_score(logical_id: StringName, score: int) -> GameServicesRequest:
	var resolution := _resolve_identifier(&"submit_score", logical_id, false)
	if resolution is GameServicesRequest:
		return resolution
	var platform_id: String = resolution
	return _decorate_identifier(
		provider.submit_score(platform_id, score),
		logical_id,
		platform_id
	)


func show_achievements() -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"show_achievements")
	return _track(provider.show_achievements())


func show_leaderboards(logical_id: StringName = &"") -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"show_leaderboards")
	if logical_id.is_empty():
		return _track(provider.show_leaderboards())
	var resolution := _resolve_identifier(&"show_leaderboards", logical_id, false)
	if resolution is GameServicesRequest:
		return resolution
	var platform_id: String = resolution
	return _decorate_identifier(
		provider.show_leaderboards(platform_id),
		logical_id,
		platform_id
	)


func request_server_credentials(options: Dictionary = {}) -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"request_server_credentials")
	return _track(provider.request_server_credentials(options))


func save_game(
	name: String,
	data: PackedByteArray,
	metadata: Dictionary = {}
) -> GameServicesRequest:
	if not _valid_save_name(name):
		return _invalid_request(
			&"save_game",
			"Save names must contain 1-100 URL-safe characters: A-Z, a-z, 0-9, -, ., _, or ~"
		)
	if not _has_provider():
		return _unavailable_request(&"save_game")
	return _track(provider.save_game(name, data, metadata))


func load_game(name: String) -> GameServicesRequest:
	if not _valid_save_name(name):
		return _invalid_request(
			&"load_game",
			"Save names must contain 1-100 URL-safe characters: A-Z, a-z, 0-9, -, ., _, or ~"
		)
	if not _has_provider():
		return _unavailable_request(&"load_game")
	return _track(provider.load_game(name))


func list_saved_games(force_reload: bool = false) -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"list_saved_games")
	return _track(provider.list_saved_games(force_reload))


func delete_saved_game(id: String) -> GameServicesRequest:
	if id.is_empty():
		return _invalid_request(&"delete_saved_game", "A saved-game ID is required")
	if not _has_provider():
		return _unavailable_request(&"delete_saved_game")
	return _track(provider.delete_saved_game(id))


func resolve_saved_game_conflict(
	conflict_id: String,
	snapshot_id: String,
	data: PackedByteArray,
	metadata: Dictionary = {}
) -> GameServicesRequest:
	if conflict_id.is_empty():
		return _invalid_request(
			&"resolve_saved_game_conflict",
			"A cloud-save conflict ID is required"
		)
	if not _has_provider():
		return _unavailable_request(&"resolve_saved_game_conflict")
	return _track(provider.resolve_saved_game_conflict(
		conflict_id,
		snapshot_id,
		data,
		metadata
	))


func _cloud_save_save_transport(
	name: String,
	data: PackedByteArray,
	metadata: Dictionary = {}
) -> GameServicesRequest:
	if not _valid_save_name(name):
		return _silent_failure_request(
			&"save_game",
			GameServicesResult.Code.INVALID_ARGUMENT,
			"Save names must contain 1-100 URL-safe characters: A-Z, a-z, 0-9, -, ., _, or ~"
		)
	if not _has_provider():
		return _silent_unavailable_request(&"save_game")
	return _track(provider.save_game(name, data, metadata), false)


func _cloud_save_load_transport(name: String) -> GameServicesRequest:
	if not _valid_save_name(name):
		return _silent_failure_request(
			&"load_game",
			GameServicesResult.Code.INVALID_ARGUMENT,
			"Save names must contain 1-100 URL-safe characters: A-Z, a-z, 0-9, -, ., _, or ~"
		)
	if not _has_provider():
		return _silent_unavailable_request(&"load_game")
	return _track(provider.load_game(name), false)


func _cloud_save_list_transport(force_reload: bool = false) -> GameServicesRequest:
	if not _has_provider():
		return _silent_unavailable_request(&"list_saved_games")
	return _track(provider.list_saved_games(force_reload), false)


func _cloud_save_delete_transport(id: String) -> GameServicesRequest:
	if id.is_empty():
		return _silent_failure_request(
			&"delete_saved_game",
			GameServicesResult.Code.INVALID_ARGUMENT,
			"A saved-game ID is required"
		)
	if not _has_provider():
		return _silent_unavailable_request(&"delete_saved_game")
	return _track(provider.delete_saved_game(id), false)


func _cloud_save_resolve_transport(
	conflict_id: String,
	snapshot_id: String,
	data: PackedByteArray,
	metadata: Dictionary = {}
) -> GameServicesRequest:
	if conflict_id.is_empty():
		return _silent_failure_request(
			&"resolve_saved_game_conflict",
			GameServicesResult.Code.INVALID_ARGUMENT,
			"A cloud-save conflict ID is required"
		)
	if not _has_provider():
		return _silent_unavailable_request(&"resolve_saved_game_conflict")
	return _track(provider.resolve_saved_game_conflict(
		conflict_id,
		snapshot_id,
		data,
		metadata
	), false)


func _load_default_config() -> GameServicesConfig:
	if ResourceLoader.exists(DEFAULT_CONFIG_PATH):
		var loaded := load(DEFAULT_CONFIG_PATH)
		if loaded is GameServicesConfig:
			return loaded
	return GameServicesConfig.new()


func _select_provider() -> GameServicesProvider:
	match OS.get_name():
		"iOS":
			return AppleGameCenterProvider.new()
		"Android":
			return GooglePlayGamesProvider.new()
		_:
			if config.use_mock_in_editor:
				return MockGameServicesProvider.new()
			return GameServicesProvider.new()


func _has_provider() -> bool:
	return _provider_available and is_instance_valid(provider)


func _resolve_identifier(
	operation: StringName,
	logical_id: StringName,
	is_achievement: bool
) -> Variant:
	if not _has_provider():
		return _unavailable_request(operation)
	if logical_id.is_empty():
		return _invalid_request(operation, "A logical identifier is required")
	var platform_id := (
		config.achievement_id(logical_id, provider_name())
		if is_achievement
		else config.leaderboard_id(logical_id, provider_name())
	)
	if platform_id.is_empty():
		var kind := "achievement" if is_achievement else "leaderboard"
		return _not_configured_request(
			operation,
			"No %s mapping exists for '%s' on %s" % [kind, logical_id, provider_name()]
		)
	return platform_id


func _decorate_identifier(
	source: GameServicesRequest,
	logical_id: StringName,
	platform_id: String
) -> GameServicesRequest:
	return _proxy_request(
		source,
		Callable(self, "_identifier_result").bind(logical_id, platform_id)
	)


func _identifier_result(
	result: GameServicesResult,
	logical_id: StringName,
	platform_id: String
) -> GameServicesResult:
	var data: Dictionary = result.data.duplicate(true) if result.data is Dictionary else {}
	data["id"] = String(logical_id)
	data["platform_id"] = platform_id
	return _copy_result_with_data(result, data)


func _normalize_achievement_result(result: GameServicesResult) -> GameServicesResult:
	if not result.ok or result.data is not Array:
		return result
	var achievements: Array[Dictionary] = []
	for value: Variant in result.data:
		if value is not Dictionary:
			continue
		var achievement: Dictionary = value.duplicate(true)
		var platform_id := str(achievement.get("platform_id", ""))
		achievement["id"] = config.logical_achievement_id(platform_id, provider_name())
		achievements.append(achievement)
	return _copy_result_with_data(result, achievements)


func _copy_result_with_data(
	result: GameServicesResult,
	data: Variant
) -> GameServicesResult:
	if result.ok:
		return GameServicesResult.success(result.operation, data, result.provider)
	return GameServicesResult.failure(
		result.operation,
		result.error_code,
		result.error_message,
		result.provider,
		result.platform_code,
		data
	)


func _proxy_request(source: GameServicesRequest, transform: Callable) -> GameServicesRequest:
	var target := GameServicesRequest.new(source.operation)
	if source.is_completed:
		call_deferred("_finish_proxy_request", source.result, target, transform)
	else:
		source.completed.connect(
			Callable(self, "_finish_proxy_request").bind(target, transform),
			CONNECT_ONE_SHOT
		)
	return _track(target)


func _finish_proxy_request(
	result: GameServicesResult,
	target: GameServicesRequest,
	transform: Callable
) -> void:
	if target.is_completed:
		return
	target.complete(transform.call(result))


func _track(
	request: GameServicesRequest,
	emit_finished: bool = true
) -> GameServicesRequest:
	if request.is_completed:
		if emit_finished:
			call_deferred("_emit_request_finished", request, request.result)
	else:
		_active_requests[request.id] = request
		_request_notifications[request.id] = emit_finished
		request.completed.connect(
			Callable(self, "_on_request_completed").bind(request),
			CONNECT_ONE_SHOT
		)
		var timer := get_tree().create_timer(config.request_timeout_seconds)
		timer.timeout.connect(Callable(self, "_on_request_timeout").bind(request))
	return request


func _on_request_completed(result: GameServicesResult, request: GameServicesRequest) -> void:
	var emit_finished := bool(_request_notifications.get(request.id, true))
	_active_requests.erase(request.id)
	_request_notifications.erase(request.id)
	if emit_finished:
		request_finished.emit(request, result)


func _emit_request_finished(request: GameServicesRequest, result: GameServicesResult) -> void:
	request_finished.emit(request, result)


func _on_request_timeout(request: GameServicesRequest) -> void:
	if request.is_completed:
		return
	request.complete(GameServicesResult.failure(
		request.operation,
		GameServicesResult.Code.PLATFORM_ERROR,
		"%s timed out after %.1f seconds" % [request.operation, config.request_timeout_seconds],
		provider_name()
	))


func _cancel_pending_requests(cancelled_provider: StringName) -> void:
	var requests := _active_requests.values()
	for value: Variant in requests:
		var request := value as GameServicesRequest
		if request == null or request.is_completed:
			continue
		request.complete(GameServicesResult.failure(
			request.operation,
			GameServicesResult.Code.CANCELLED,
			"Game services shut down before the request completed",
			cancelled_provider
		))
	_active_requests.clear()
	_request_notifications.clear()


func _on_authentication_changed(authenticated: bool, player: Dictionary) -> void:
	authentication_changed.emit(authenticated, player)


func _unavailable_request(operation: StringName) -> GameServicesRequest:
	var request := GameServicesRequest.new(operation)
	request.complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.UNAVAILABLE,
		"Game services have not been initialized",
		provider_name()
	))
	return _track(request)


func _invalid_request(operation: StringName, message: String) -> GameServicesRequest:
	var request := GameServicesRequest.new(operation)
	request.complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.INVALID_ARGUMENT,
		message,
		provider_name()
	))
	return _track(request)


func _not_configured_request(operation: StringName, message: String) -> GameServicesRequest:
	var request := GameServicesRequest.new(operation)
	request.complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.NOT_CONFIGURED,
		message,
		provider_name()
	))
	return _track(request)


func _silent_unavailable_request(operation: StringName) -> GameServicesRequest:
	return _silent_failure_request(
		operation,
		GameServicesResult.Code.UNAVAILABLE,
		"Game services have not been initialized"
	)


func _silent_failure_request(
	operation: StringName,
	code: GameServicesResult.Code,
	message: String
) -> GameServicesRequest:
	var request := GameServicesRequest.new(operation)
	request.complete(GameServicesResult.failure(
		operation,
		code,
		message,
		provider_name()
	))
	return _track(request, false)


func _valid_save_name(name: String) -> bool:
	if name.is_empty() or name.length() > 100:
		return false
	for character in name:
		if ALLOWED_SAVE_NAME_CHARACTERS.find(character) < 0:
			return false
	return true
