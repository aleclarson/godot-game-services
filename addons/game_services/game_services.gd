extends Node

## Normalized entry point for Apple Game Center and Google Play Games Services.

signal provider_changed(provider_name: StringName, capabilities: int)
signal authentication_changed(authenticated: bool, player: Variant)
signal session_changed(state: SessionState, player: Variant)
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

## Lifecycle state owned by the facade rather than inferred from a provider.
##
## A provider can report authentication before its player profile is available,
## so AUTHENTICATING also covers the player-load part of ensure_authenticated().
enum SessionState {
	UNAVAILABLE,
	SIGNED_OUT,
	AUTHENTICATING,
	AUTHENTICATED,
}

const DEFAULT_CONFIG_PATH := "res://game_services_config.tres"
const ALLOWED_SAVE_NAME_CHARACTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"

var auto_initialize: bool = true
var config: GameServicesConfig
var provider: GameServicesProvider
var cloud_saves: CloudSaveStore
var store_review: StoreReviewService
var _provider_available: bool = false
var _active_requests: Dictionary[int, GameServicesRequest] = {}
var _request_notifications: Dictionary[int, bool] = {}
var session_state: SessionState = SessionState.UNAVAILABLE
var current_player: GameServicesPlayer = GameServicesPlayer.new()
var _ensure_request: GameServicesRequest
var _ensure_provider: GameServicesProvider
var _authentication_request_providers: Dictionary[int, GameServicesProvider] = {}
var _player_request_providers: Dictionary[int, GameServicesProvider] = {}


func _init() -> void:
	cloud_saves = CloudSaveStore.new(self)
	store_review = StoreReviewService.new()


func _ready() -> void:
	if auto_initialize:
		initialize()


func initialize(
	p_config: GameServicesConfig = null,
	provider_override: GameServicesProvider = null,
	store_review_override: StoreReviewService = null
) -> GameServicesResult:
	shutdown()
	config = p_config if p_config != null else _load_default_config()
	store_review = (
		store_review_override
		if store_review_override != null
		else StoreReviewService.new()
	)
	store_review.initialize(config)
	provider = provider_override if provider_override != null else _select_provider()
	add_child(provider)
	provider.authentication_changed.connect(_on_authentication_changed)
	var result := provider.initialize(config)
	_provider_available = result.ok
	if _provider_available:
		_set_session_state(
			SessionState.AUTHENTICATED if provider.is_authenticated() else SessionState.SIGNED_OUT,
			{},
			false
		)
	else:
		_set_session_state(SessionState.UNAVAILABLE, {}, false)
	provider_changed.emit(provider.provider_name(), capabilities())
	return result


func shutdown() -> void:
	var cancelled_provider := provider_name()
	cloud_saves._cancel_pending_requests(cancelled_provider)
	# Mark the facade unavailable before completing requests. Some providers
	# complete their transport request synchronously when they are cancelled;
	# those callbacks must not start a new ensure_authenticated chain.
	_provider_available = false
	_clear_session()
	_cancel_pending_requests(cancelled_provider)
	if is_instance_valid(store_review):
		store_review.shutdown()
	if not is_instance_valid(provider):
		provider = null
		return
	if provider.authentication_changed.is_connected(_on_authentication_changed):
		provider.authentication_changed.disconnect(_on_authentication_changed)
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
	return _has_provider() and session_state == SessionState.AUTHENTICATED


## Request-composition conveniences kept on the facade for code that prefers a
## single GameServices entry point. These helpers are opt-in and do not start
## authentication or retry a provider operation by themselves.
func with_timeout(request: GameServicesRequest, seconds: float) -> GameServicesRequest:
	if request == null:
		return _invalid_request(&"with_timeout", "A request is required")
	return request.with_timeout(seconds)


func retry_request(
	request: GameServicesRequest,
	operation_factory: Callable,
	policy: Variant = null
) -> GameServicesRequest:
	if request == null:
		return _invalid_request(&"retry_request", "A request is required")
	return request.with_retry(operation_factory, policy)


func chain_request(request: GameServicesRequest, next: Callable) -> GameServicesRequest:
	if request == null:
		return _invalid_request(&"chain_request", "A request is required")
	return request.then(next)


func cancel_request(
	request: GameServicesRequest,
	message: String = "Request cancelled"
) -> bool:
	if request == null:
		return false
	return request.cancel(message, provider_name())


## Returns a defensive copy of the most recently loaded normalized player.
func get_current_player() -> GameServicesPlayer:
	return current_player.duplicate_player()


## Returns one request for the current authenticated player.
##
## Authentication and player loading are intentionally opt-in. Concurrent calls
## while this operation is pending receive the same request and therefore share
## both native work and its eventual lifecycle result.
func ensure_authenticated() -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"ensure_authenticated")
	if (
		_session_is_ready()
		and _ensure_request == null
	):
		return _completed_player_request()
	if is_instance_valid(_ensure_request) and not _ensure_request.is_completed:
		return _ensure_request

	_ensure_provider = provider
	var target := GameServicesRequest.new(&"ensure_authenticated")
	_ensure_request = target
	_track(target)
	_set_session_state(SessionState.AUTHENTICATING, current_player, false)
	# A provider may report authenticated before it has delivered a profile (for
	# example, Game Center can be authenticated at launch). Ask it for the
	# authentication event once so adapters can populate the current player;
	# _start_ensure_player_load() is used afterward only when that event omitted it.
	_start_ensure_authentication()
	return target


func supports_store_review() -> bool:
	return is_instance_valid(store_review) and store_review.supports_native_review()


func request_in_app_review() -> GameServicesRequest:
	if not is_instance_valid(store_review):
		return _unavailable_request(&"request_in_app_review")
	return _proxy_request(
		store_review.request_in_app_review(),
		Callable(self, "_normalize_presentation_result")
	)


func open_store_review_page() -> GameServicesRequest:
	if not is_instance_valid(store_review):
		return _unavailable_request(&"open_store_review_page")
	return _proxy_request(
		store_review.open_store_review_page(),
		Callable(self, "_normalize_presentation_result")
	)


func authenticate() -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"authenticate")
	_set_session_state(SessionState.AUTHENTICATING, current_player, false)
	var source := provider.authenticate()
	_observe_authentication_request(source, provider)
	return _proxy_request(source, Callable(self, "_normalize_authentication_result"))


func load_player() -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"load_player")
	var source := provider.load_player()
	_observe_player_request(source, provider)
	return _proxy_request(source, Callable(self, "_normalize_player_result"))


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
	return _proxy_request(
		provider.show_achievements(),
		Callable(self, "_normalize_presentation_result")
	)


func show_leaderboards(logical_id: StringName = &"") -> GameServicesRequest:
	if not _has_provider():
		return _unavailable_request(&"show_leaderboards")
	if logical_id.is_empty():
		return _proxy_request(
			provider.show_leaderboards(),
			Callable(self, "_normalize_presentation_result")
		)
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
	return _proxy_request(
		provider.request_server_credentials(options),
		Callable(self, "_normalize_credentials_result")
	)


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


func _session_is_ready() -> bool:
	return session_state == SessionState.AUTHENTICATED and not current_player.is_empty()


func _completed_player_request() -> GameServicesRequest:
	var request := GameServicesRequest.new(&"ensure_authenticated")
	request.complete(GameServicesResult.success(
		&"ensure_authenticated",
		current_player.duplicate_player(),
		provider_name()
	))
	return _track(request)


func _start_ensure_authentication() -> void:
	if not _ensure_is_active():
		return
	var owner := _ensure_provider
	var source := owner.authenticate()
	_track(source, false)
	if source.is_completed:
		_on_ensure_authentication_completed(source.result, source, owner)
	else:
		source.completed.connect(
			Callable(self, "_on_ensure_authentication_completed").bind(source, owner),
			CONNECT_ONE_SHOT
		)


func _start_ensure_player_load() -> void:
	if not _ensure_is_active():
		return
	if _session_is_ready():
		_complete_ensure_success()
		return
	var owner := _ensure_provider
	var source := owner.load_player()
	_track(source, false)
	if source.is_completed:
		_on_ensure_player_completed(source.result, source, owner)
	else:
		source.completed.connect(
			Callable(self, "_on_ensure_player_completed").bind(source, owner),
			CONNECT_ONE_SHOT
		)


func _on_ensure_authentication_completed(
	result: GameServicesResult,
	_source: GameServicesRequest,
	owner: GameServicesProvider
) -> void:
	if not _ensure_is_active() or owner != _ensure_provider or owner != provider:
		return
	_update_session_from_authentication_result(result)
	if not result.ok:
		_complete_ensure_result(_session_result(result))
		return
	_start_ensure_player_load()


func _on_ensure_player_completed(
	result: GameServicesResult,
	_source: GameServicesRequest,
	owner: GameServicesProvider
) -> void:
	if not _ensure_is_active() or owner != _ensure_provider or owner != provider:
		return
	if not result.ok:
		_set_session_state(SessionState.SIGNED_OUT, {}, false)
		_complete_ensure_result(_session_result(result))
		return
	var player := _player_from_result(result)
	if player.is_empty():
		_set_session_state(SessionState.SIGNED_OUT, {}, false)
		_complete_ensure_result(GameServicesResult.failure(
			&"ensure_authenticated",
			GameServicesResult.Code.INVALID_DATA,
			"The provider did not return a current player",
			owner.provider_name()
		))
		return
	_set_session_state(SessionState.AUTHENTICATED, player, false)
	_complete_ensure_success()


func _complete_ensure_success() -> void:
	if not _ensure_is_active():
		return
	_ensure_request.complete(GameServicesResult.success(
		&"ensure_authenticated",
		current_player.duplicate_player(),
		provider_name()
	))


func _complete_ensure_result(result: GameServicesResult) -> void:
	if not _ensure_is_active():
		return
	_ensure_request.complete(result)


func _session_result(result: GameServicesResult) -> GameServicesResult:
	if result.ok:
		return GameServicesResult.success(
			&"ensure_authenticated",
			current_player.duplicate_player(),
			result.provider
		)
	return GameServicesResult.failure(
		&"ensure_authenticated",
		result.error_code,
		result.error_message,
		result.provider,
		result.platform_code,
		result.data
	)


func _ensure_is_active() -> bool:
	return (
		is_instance_valid(_ensure_request)
		and not _ensure_request.is_completed
		and is_instance_valid(_ensure_provider)
		and _ensure_provider == provider
		and _has_provider()
	)


func _observe_authentication_request(
	request: GameServicesRequest,
	owner: GameServicesProvider
) -> void:
	_authentication_request_providers[request.id] = owner
	if request.is_completed:
		_on_authentication_request_completed(request.result, request, owner)
	else:
		request.completed.connect(
			Callable(self, "_on_authentication_request_completed").bind(request, owner),
			CONNECT_ONE_SHOT
		)


func _on_authentication_request_completed(
	result: GameServicesResult,
	request: GameServicesRequest,
	owner: GameServicesProvider
) -> void:
	_authentication_request_providers.erase(request.id)
	if owner != provider or not _has_provider():
		return
	_update_session_from_authentication_result(result)


func _update_session_from_authentication_result(
	result: GameServicesResult
) -> void:
	if result.ok:
		var player := _player_from_authentication_result(result)
		_set_session_state(
			SessionState.AUTHENTICATED,
			player if not player.is_empty() else current_player,
			false
		)
	else:
		_set_session_state(SessionState.SIGNED_OUT, {}, false)


func _player_from_authentication_result(result: GameServicesResult) -> GameServicesPlayer:
	if result.data is GameServicesAuthentication:
		return result.data.player
	if result.data is GameServicesPlayer:
		return result.data
	if result.data is Dictionary:
		var payload: Dictionary = result.data
		if payload.get("player") is Dictionary:
			return GameServicesPlayer.from_dictionary(payload["player"], result.provider)
		if payload.has("id"):
			return GameServicesPlayer.from_dictionary(payload, result.provider)
	return GameServicesPlayer.new()


func _player_from_result(result: GameServicesResult) -> GameServicesPlayer:
	return _player_from_authentication_result(result)


func _observe_player_request(
	request: GameServicesRequest,
	owner: GameServicesProvider
) -> void:
	_player_request_providers[request.id] = owner
	if request.is_completed:
		_on_player_request_completed(request.result, request, owner)
	else:
		request.completed.connect(
			Callable(self, "_on_player_request_completed").bind(request, owner),
			CONNECT_ONE_SHOT
		)


func _on_player_request_completed(
	result: GameServicesResult,
	request: GameServicesRequest,
	owner: GameServicesProvider
) -> void:
	_player_request_providers.erase(request.id)
	if owner != provider or not _has_provider() or not result.ok:
		return
	var player := _player_from_result(result)
	if not player.is_empty():
		_set_session_state(SessionState.AUTHENTICATED, player, false)


func _set_session_state(
	state: SessionState,
	player: Variant,
	emit_authentication: bool
) -> void:
	var next_player := GameServicesPlayer.from_dictionary(player, provider_name())
	var changed := (
		session_state != state
		or current_player.to_dictionary() != next_player.to_dictionary()
	)
	session_state = state
	current_player = next_player
	if changed:
		session_changed.emit(session_state, current_player.duplicate_player())
	if emit_authentication:
		authentication_changed.emit(
			session_state == SessionState.AUTHENTICATED,
		current_player.duplicate_player()
		)


func _clear_session() -> void:
	var had_session := session_state != SessionState.UNAVAILABLE or not current_player.is_empty()
	_set_session_state(SessionState.UNAVAILABLE, {}, false)
	if had_session:
		authentication_changed.emit(false, current_player.duplicate_player())


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
	if not result.ok:
		return result
	var data: Dictionary = result.data.duplicate(true) if result.data is Dictionary else {}
	data["id"] = String(logical_id)
	data["platform_id"] = platform_id
	match result.operation:
		&"unlock_achievement", &"set_achievement_progress":
			return _copy_result_with_data(
				result,
				GameServicesAchievement.from_dictionary(data, result.provider, String(logical_id)),
				result.raw_data
			)
		&"submit_score":
			return _copy_result_with_data(
				result,
				GameServicesLeaderboardScore.from_dictionary(data, result.provider, String(logical_id)),
				result.raw_data
			)
		&"show_leaderboards":
			return _copy_result_with_data(
				result,
				GameServicesPresentationOutcome.from_dictionary(data, result.operation, result.provider),
				result.raw_data
			)
	return _copy_result_with_data(result, data, result.raw_data)


func _normalize_achievement_result(result: GameServicesResult) -> GameServicesResult:
	if not result.ok or result.data is GameServicesAchievementCollection:
		return result
	if result.data is not Array:
		return result
	var achievements: Array[GameServicesAchievement] = []
	for value: Variant in result.data:
		if value is GameServicesAchievement:
			achievements.append(value)
			continue
		if not value is Dictionary:
			continue
		var achievement: Dictionary = value
		var platform_id := str(achievement.get("platform_id", ""))
		var logical_id := (
			config.logical_achievement_id(platform_id, provider_name())
			if config != null
			else str(achievement.get("id", ""))
		)
		achievements.append(GameServicesAchievement.from_dictionary(
			achievement,
			result.provider,
			logical_id
		))
	return _copy_result_with_data(result, achievements, result.raw_data)


func _normalize_player_result(result: GameServicesResult) -> GameServicesResult:
	if not result.ok or result.data is GameServicesPlayer:
		return result
	return _copy_result_with_data(
		result,
		GameServicesPlayer.from_dictionary(result.data, result.provider),
		result.raw_data
	)


func _normalize_authentication_result(result: GameServicesResult) -> GameServicesResult:
	if not result.ok or result.data is GameServicesAuthentication:
		return result
	return _copy_result_with_data(
		result,
		GameServicesAuthentication.from_dictionary(result.data, result.provider),
		result.raw_data
	)


func _normalize_credentials_result(result: GameServicesResult) -> GameServicesResult:
	if not result.ok or result.data is GameServicesServerCredentials:
		return result
	return _copy_result_with_data(
		result,
		GameServicesServerCredentials.from_dictionary(result.data, result.provider),
		result.raw_data
	)


func _normalize_presentation_result(result: GameServicesResult) -> GameServicesResult:
	if not result.ok or result.data is GameServicesPresentationOutcome:
		return result
	return _copy_result_with_data(
		result,
		GameServicesPresentationOutcome.from_dictionary(
			result.data,
			result.operation,
			result.provider
		),
		result.raw_data
	)


func _copy_result_with_data(
	result: GameServicesResult,
	data: Variant,
	raw_data: Variant = null
) -> GameServicesResult:
	var diagnostics := result.raw_data if raw_data == null else raw_data
	if result.ok:
		var success := GameServicesResult.success(result.operation, data, result.provider, diagnostics)
		success.request_id = result.request_id
		return success
	var failure := GameServicesResult.failure(
		result.operation,
		result.error_code,
		result.error_message,
		result.provider,
		result.platform_code,
		data,
		diagnostics
	)
	failure.request_id = result.request_id
	return failure


func _proxy_request(source: GameServicesRequest, transform: Callable) -> GameServicesRequest:
	var target := GameServicesRequest.new(source.operation)
	target.parent_id = source.id
	target.origin_id = source.origin_id
	target.provider = source.provider
	_track(source, false)
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
	if request.provider.is_empty():
		request.provider = provider_name()
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
		var timeout_seconds := config.request_timeout_seconds if config != null else 30.0
		var timer := get_tree().create_timer(timeout_seconds)
		timer.timeout.connect(Callable(self, "_on_request_timeout").bind(request))
	return request


func _on_request_completed(result: GameServicesResult, request: GameServicesRequest) -> void:
	var emit_finished := bool(_request_notifications.get(request.id, true))
	_active_requests.erase(request.id)
	_request_notifications.erase(request.id)
	_authentication_request_providers.erase(request.id)
	_player_request_providers.erase(request.id)
	if request == _ensure_request:
		_ensure_request = null
		_ensure_provider = null
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
	_authentication_request_providers.clear()
	_player_request_providers.clear()
	_ensure_request = null
	_ensure_provider = null


func _on_authentication_changed(authenticated: bool, player: Variant) -> void:
	if not _has_provider():
		return
	if authenticated:
		_set_session_state(SessionState.AUTHENTICATED, player, false)
	else:
		_set_session_state(SessionState.SIGNED_OUT, {}, false)
	authentication_changed.emit(authenticated, current_player.duplicate_player())


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
