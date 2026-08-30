class_name MockGameServicesProvider
extends GameServicesProvider

## Stateful provider used in the editor and in automated tests.
##
## The mock intentionally has the same asynchronous request boundary as the
## native adapters, while exposing deterministic controls for tests. A script
## entry may be a GameServicesResult, a bool, or a dictionary containing
## `ok`/`success`, `data`/`payload`, `error_code`, `error_message`,
## `platform_code`, and `delay_seconds`. Array scripts are consumed in order;
## the final entry is reused after the array is exhausted.

const DEFAULT_CAPABILITIES := (
	Capability.AUTHENTICATION
	| Capability.PLAYER_PROFILE
	| Capability.ACHIEVEMENTS
	| Capability.ACHIEVEMENT_PROGRESS
	| Capability.LEADERBOARDS
	| Capability.PLATFORM_UI
	| Capability.CLOUD_SAVES
	| Capability.SERVER_CREDENTIALS
)

var _authenticated: bool = false
var _player: Dictionary = {}
var _achievement_progress: Dictionary = {}
var _scores: Dictionary = {}
var _saved_games: Dictionary = {}
var _capabilities: int = DEFAULT_CAPABILITIES

## Per-operation controls. String and StringName keys are both accepted.
var operation_scripts: Dictionary = {}
var operation_delays: Dictionary = {}
var operation_payloads: Dictionary = {}
var operation_failures: Dictionary = {}
var presentation_payloads: Dictionary = {}
var presentation_results: Dictionary = {}
var _script_positions: Dictionary = {}
var _delay_positions: Dictionary = {}

## Friendly aliases make the controls convenient from editor tooling while
## keeping the explicit operation_* names as the documented contract.
var scripts: Dictionary:
	get:
		return operation_scripts
	set(value):
		operation_scripts = value
		_script_positions.clear()

var outcomes: Dictionary:
	get:
		return operation_scripts
	set(value):
		operation_scripts = value
		_script_positions.clear()

var delays: Dictionary:
	get:
		return operation_delays
	set(value):
		operation_delays = value
		_delay_positions.clear()

var payloads: Dictionary:
	get:
		return operation_payloads
	set(value):
		operation_payloads = value

var failure_scripts: Dictionary:
	get:
		return operation_failures
	set(value):
		operation_failures = value
		_script_positions.clear()

var capabilities_override: int:
	get:
		return _capabilities
	set(value):
		_capabilities = value

## The mock's initial account is applied by initialize().
var initial_authenticated: bool = false
var initial_player: Dictionary = {}

## Legacy `calls` remains available; `call_log` is its defensive-copy alias.
var calls: Array[Dictionary] = []
var call_log: Array[Dictionary]:
	get:
		return calls.duplicate(true)
	set(value):
		calls = value.duplicate(true)

## Presentation payload used when an operation has no more specific payload.
var presentation_accepted: bool = true
var presentation_delay_seconds: float = 0.0

var capability_mask: int:
	get:
		return _capabilities
	set(value):
		_capabilities = value

var capabilities_mask: int:
	get:
		return _capabilities
	set(value):
		_capabilities = value

var authenticated: bool:
	get:
		return _authenticated
	set(value):
		set_authenticated(value)

var player: Dictionary:
	get:
		return _player.duplicate(true)
	set(value):
		if value is Dictionary:
			_player = value.duplicate(true)

var account: Dictionary:
	get:
		return _player.duplicate(true)
	set(value):
		if value is Dictionary:
			_player = value.duplicate(true)
			initial_player = value.duplicate(true)

var account_player: Dictionary:
	get:
		return _player.duplicate(true)
	set(value):
		account = value

var _pending_requests: Dictionary = {}


func provider_name() -> StringName:
	return &"mock"


func capabilities() -> int:
	return _capabilities


func initialize(p_config: GameServicesConfig) -> GameServicesResult:
	var result := super.initialize(p_config)
	_player = (
		initial_player.duplicate(true)
		if not initial_player.is_empty()
		else config.mock_player()
	)
	_authenticated = initial_authenticated
	_achievement_progress.clear()
	_scores.clear()
	_saved_games.clear()
	_script_positions.clear()
	_delay_positions.clear()
	return result


func shutdown() -> void:
	_cancel_pending_requests()
	_authenticated = false
	_super_shutdown()


func _super_shutdown() -> void:
	# Kept as a separate method so shutdown remains easy to override in test
	# subclasses while the base provider's no-op lifecycle stays explicit.
	super.shutdown()


func is_authenticated() -> bool:
	return _authenticated


## Change the mock account and optionally emit the same provider event native
## adapters use. This is useful for account switching and sign-out tests.
func set_account(
	account: Variant,
	p_authenticated: bool = true,
	emit_event: bool = true
) -> void:
	if account is Dictionary:
		_player = account.duplicate(true)
	_authenticated = p_authenticated
	if emit_event:
		authentication_changed.emit(_authenticated, _player.duplicate(true) if _authenticated else {})


func change_account(account: Variant, p_authenticated: bool = true) -> void:
	set_account(account, p_authenticated, true)


func set_player(account: Variant, emit_event: bool = false) -> void:
	set_account(account, _authenticated, emit_event)


func set_authenticated(value: bool, account: Variant = null, emit_event: bool = true) -> void:
	if account != null:
		if account is Dictionary:
			_player = account.duplicate(true)
	_authenticated = value
	if emit_event:
		authentication_changed.emit(value, _player.duplicate(true) if value else {})


func sign_in(account: Variant = null) -> void:
	set_authenticated(true, account, true)


func sign_out() -> void:
	set_authenticated(false, null, true)


func emit_authentication_event(value: bool, account: Variant = null) -> void:
	set_authenticated(value, account, true)


func set_capabilities(mask: int) -> void:
	_capabilities = mask


func set_capability_mask(mask: int) -> void:
	set_capabilities(mask)


func set_capability(capability: Capability, enabled: bool) -> void:
	if enabled:
		_capabilities |= int(capability)
	else:
		_capabilities &= ~int(capability)


func set_capability_enabled(capability: Capability, enabled: bool) -> void:
	set_capability(capability, enabled)


func enable_capability(capability: Capability) -> void:
	set_capability(capability, true)


func disable_capability(capability: Capability) -> void:
	set_capability(capability, false)


## Replace one operation's deterministic outcome script. A scalar is a
## persistent outcome; an Array is consumed once per invocation.
func set_operation_script(operation: StringName, script: Variant) -> void:
	operation_scripts[String(operation)] = script
	_script_positions.erase(String(operation))


func script_operation(operation: StringName, script_value: Variant) -> void:
	set_operation_script(operation, script_value)


func set_result_script(operation: StringName, script_value: Variant) -> void:
	set_operation_script(operation, script_value)


func set_outcome_script(operation: StringName, script_value: Variant) -> void:
	set_operation_script(operation, script_value)


func set_operation_results(operation: StringName, script_value: Variant) -> void:
	set_operation_script(operation, script_value)


func set_operation_outcomes(operation: StringName, script_value: Variant) -> void:
	set_operation_script(operation, script_value)


func set_operation_response(operation: StringName, script_value: Variant) -> void:
	set_operation_script(operation, script_value)


func set_response(operation: StringName, script_value: Variant) -> void:
	set_operation_script(operation, script_value)


func script(operation: StringName, script_value: Variant) -> void:
	set_operation_script(operation, script_value)


func queue_operation_result(operation: StringName, outcome: Variant) -> void:
	var key := String(operation)
	var existing: Variant = operation_scripts.get(key, [])
	if not existing is Array:
		existing = [existing]
	var queued: Array = existing.duplicate(true)
	queued.append(outcome)
	operation_scripts[key] = queued


func queue_result(operation: StringName, outcome: Variant) -> void:
	queue_operation_result(operation, outcome)


func queue_response(operation: StringName, outcome: Variant) -> void:
	queue_operation_result(operation, outcome)


func set_operation_success(
	operation: StringName,
	payload: Variant = null,
	delay_seconds: float = 0.0
) -> void:
	var success := {"ok": true, "delay_seconds": delay_seconds}
	if payload != null:
		success["data"] = payload
	set_operation_script(operation, success)


func set_operation_failure(
	operation: StringName,
	code: Variant = GameServicesResult.Code.PLATFORM_ERROR,
	message: String = "",
	platform_code: Variant = null,
	delay_seconds: float = 0.0
) -> void:
	var failure := {
		"ok": false,
		"error_code": _coerce_code(code),
		"error_message": message,
		"delay_seconds": delay_seconds,
	}
	if platform_code != null:
		failure["platform_code"] = platform_code
	set_operation_script(operation, failure)


func set_failure_script(operation: StringName, script_value: Variant) -> void:
	operation_failures[String(operation)] = script_value
	_script_positions.erase(String(operation))


func set_operation_failure_script(operation: StringName, script_value: Variant) -> void:
	set_failure_script(operation, script_value)


func clear_operation_script(operation: StringName) -> void:
	operation_scripts.erase(String(operation))
	_script_positions.erase(String(operation))


func set_operation_delay(operation: StringName, seconds: float) -> void:
	operation_delays[String(operation)] = maxf(seconds, 0.0)
	_delay_positions.erase(String(operation))


func set_delay_seconds(operation: StringName, seconds: float) -> void:
	set_operation_delay(operation, seconds)


func set_delay(operation: StringName, seconds: float) -> void:
	set_operation_delay(operation, seconds)


func set_operation_payload(operation: StringName, payload: Variant) -> void:
	operation_payloads[String(operation)] = payload


func set_payload(operation: StringName, payload: Variant) -> void:
	set_operation_payload(operation, payload)


func configure_operation(
	operation: StringName,
	outcome: Variant = null,
	delay_seconds: float = 0.0
) -> void:
	set_operation_script(operation, outcome)
	set_operation_delay(operation, delay_seconds)


func set_presentation_outcome(operation: StringName, outcome: Variant) -> void:
	if outcome is GameServicesResult:
		presentation_results[String(operation)] = outcome
	elif outcome is bool:
		presentation_payloads[String(operation)] = {
			"presentation_accepted": outcome,
			"accepted": outcome,
		}
	else:
		presentation_payloads[String(operation)] = outcome


func set_presentation_payload(operation: StringName, payload: Variant) -> void:
	presentation_payloads[String(operation)] = payload


func set_presentation_response(operation: StringName, outcome: Variant) -> void:
	set_presentation_outcome(operation, outcome)


func set_presentation_result(operation: StringName, result: GameServicesResult) -> void:
	presentation_results[String(operation)] = result


func clear_call_log() -> void:
	calls.clear()


func clear_calls() -> void:
	clear_call_log()


func reset_call_log() -> void:
	clear_call_log()


func get_call_log() -> Array[Dictionary]:
	return calls.duplicate(true)


func get_calls() -> Array[Dictionary]:
	return get_call_log()


## Reset state and call inspection while preserving configured scripts by
## default. Pass false when a test also wants to remove all controls.
func reset(preserve_controls: bool = true) -> void:
	var was_authenticated := _authenticated
	_cancel_pending_requests()
	_authenticated = false
	_player = config.mock_player() if config != null else {}
	_achievement_progress.clear()
	_scores.clear()
	_saved_games.clear()
	clear_call_log()
	_script_positions.clear()
	_delay_positions.clear()
	if was_authenticated:
		authentication_changed.emit(false, {})
	if not preserve_controls:
		operation_scripts.clear()
		operation_delays.clear()
		operation_payloads.clear()
		operation_failures.clear()
		presentation_payloads.clear()
		presentation_results.clear()
		_capabilities = DEFAULT_CAPABILITIES
		presentation_accepted = true
		presentation_delay_seconds = 0.0
		initial_authenticated = false
		initial_player.clear()


func reset_state() -> void:
	reset(true)


func reset_controls() -> void:
	reset(false)


func authenticate() -> GameServicesRequest:
	var data := {
		"authenticated": true,
		"player": _player.duplicate(true),
	}
	return _request(
		&"authenticate",
		[],
		data,
		Capability.AUTHENTICATION,
		false,
		Callable(self, "_apply_authentication")
	)


func load_player() -> GameServicesRequest:
	return _request(
		&"load_player",
		[],
		_player.duplicate(true),
		Capability.PLAYER_PROFILE
	)


func unlock_achievement(platform_id: String) -> GameServicesRequest:
	var data := {
		"platform_id": platform_id,
		"progress": 1.0,
		"unlocked": true,
	}
	return _request(
		&"unlock_achievement",
		[platform_id],
		data,
		Capability.ACHIEVEMENTS,
		true,
		Callable(self, "_apply_unlock").bind(platform_id)
	)


func set_achievement_progress(
	platform_id: String,
	progress: float,
	_total_steps: int = 0
) -> GameServicesRequest:
	var normalized_progress := clampf(progress, 0.0, 1.0)
	var previous := float(_achievement_progress.get(platform_id, 0.0))
	var next_progress := maxf(previous, normalized_progress)
	var data := {
		"platform_id": platform_id,
		"progress": next_progress,
		"unlocked": next_progress >= 1.0,
	}
	return _request(
		&"set_achievement_progress",
		[platform_id, progress],
		data,
		Capability.ACHIEVEMENT_PROGRESS,
		true,
		Callable(self, "_apply_progress").bind(platform_id, next_progress)
	)


func load_achievements(_force_reload: bool = false) -> GameServicesRequest:
	var achievements: Array[Dictionary] = []
	for platform_id: Variant in _achievement_progress:
		var progress := float(_achievement_progress[platform_id])
		achievements.append({
			"platform_id": str(platform_id),
			"progress": progress,
			"unlocked": progress >= 1.0,
		})
	return _request(
		&"load_achievements",
		[_force_reload],
		achievements,
		Capability.ACHIEVEMENTS
	)


func submit_score(platform_id: String, score: int) -> GameServicesRequest:
	return _request(
		&"submit_score",
		[platform_id, score],
		{"platform_id": platform_id, "score": score},
		Capability.LEADERBOARDS,
		true,
		Callable(self, "_apply_score").bind(platform_id, score)
	)


func show_achievements() -> GameServicesRequest:
	return _presentation_request(&"show_achievements", [])


func show_leaderboards(platform_id: String = "") -> GameServicesRequest:
	return _presentation_request(&"show_leaderboards", [platform_id], {
		"platform_id": platform_id,
	})


func request_server_credentials(_options: Dictionary = {}) -> GameServicesRequest:
	return _request(
		&"request_server_credentials",
		[_options],
		{"kind": "mock", "token": "mock-server-credential"},
		Capability.SERVER_CREDENTIALS
	)


func save_game(name: String, data: PackedByteArray, metadata: Dictionary = {}) -> GameServicesRequest:
	var saved_metadata := metadata.duplicate(true)
	saved_metadata.merge({
		"id": name,
		"name": name,
		"updated_at_msec": Time.get_unix_time_from_system() * 1000.0,
	}, true)
	return _request(
		&"save_game",
		[name, data, metadata],
		saved_metadata.duplicate(true),
		Capability.CLOUD_SAVES,
		true,
		Callable(self, "_apply_save").bind(name, data, saved_metadata)
	)


func load_game(name: String) -> GameServicesRequest:
	var default_result: GameServicesResult
	if _saved_games.has(name):
		default_result = GameServicesResult.success(
			&"load_game",
			_saved_games[name].duplicate(true),
			provider_name()
		)
	else:
		default_result = GameServicesResult.failure(
			&"load_game",
			GameServicesResult.Code.NOT_FOUND,
			"Saved game '%s' does not exist" % name,
			provider_name()
		)
	return _request(
		&"load_game",
		[name],
		null,
		Capability.CLOUD_SAVES,
		true,
		Callable(),
		default_result
	)


func list_saved_games(_force_reload: bool = false) -> GameServicesRequest:
	var saves: Array[Dictionary] = []
	for name: Variant in _saved_games:
		saves.append(_saved_games[name].metadata.duplicate(true))
	return _request(
		&"list_saved_games",
		[_force_reload],
		saves,
		Capability.CLOUD_SAVES
	)


func delete_saved_game(id: String) -> GameServicesRequest:
	return _request(
		&"delete_saved_game",
		[id],
		{"id": id, "deleted": _saved_games.has(id)},
		Capability.CLOUD_SAVES,
		true,
		Callable(self, "_apply_delete").bind(id)
	)


func resolve_saved_game_conflict(
	conflict_id: String,
	_snapshot_id: String,
	_data: PackedByteArray,
	_metadata: Dictionary = {}
) -> GameServicesRequest:
	var missing := GameServicesResult.failure(
		&"resolve_saved_game_conflict",
		GameServicesResult.Code.NOT_FOUND,
		"Mock conflict '%s' does not exist" % conflict_id,
		provider_name()
	)
	return _request(
		&"resolve_saved_game_conflict",
		[conflict_id, _snapshot_id, _data, _metadata],
		null,
		Capability.CLOUD_SAVES,
		true,
		Callable(),
		missing
	)


func _presentation_request(operation: StringName, arguments: Array, extra: Variant = null) -> GameServicesRequest:
	var default_data: Variant = {
		"presentation_accepted": presentation_accepted,
		"accepted": presentation_accepted,
	}
	if extra is Dictionary:
		default_data.merge(extra, true)
	return _request(
		operation,
		arguments,
		default_data,
		Capability.PLATFORM_UI
	)


func _request(
	operation: StringName,
	arguments: Array,
	default_data: Variant,
	required_capability: int = -1,
	needs_authentication: bool = true,
	on_success: Callable = Callable(),
	default_result: GameServicesResult = null
) -> GameServicesRequest:
	_record_call(operation, arguments)
	if required_capability >= 0 and not supports(required_capability as Capability):
		return _unsupported(operation)
	if needs_authentication and not _authenticated:
		return _not_authenticated(operation)

	var script_present := _has_operation_script(operation)
	var script_value := _next_operation_script(operation) if script_present else null
	var result := _result_for(
		operation,
		default_data,
		default_result,
		script_present,
		script_value
	)
	if result.ok and on_success.is_valid():
		on_success.call(result)
	var delay := _delay_for(operation, script_value if script_present else null)
	return _schedule(result, operation, delay)


func _result_for(
	operation: StringName,
	default_data: Variant,
	default_result: GameServicesResult,
	script_present: bool,
	script_value: Variant
) -> GameServicesResult:
	var configured_result := _presentation_result_for(operation)
	if not script_present and configured_result != null:
		return _copy_result_for_operation(configured_result, operation)
	if not script_present and default_result != null:
		var result_without_script := _copy_result_for_operation(default_result, operation)
		var configured_payload := _payload_for(operation)
		if configured_payload != null:
			return GameServicesResult.success(operation, configured_payload, provider_name())
		return result_without_script
	if not script_present:
		var default_payload := _payload_for(operation)
		if default_payload != null:
			default_data = default_payload

	if script_value is GameServicesResult:
		return _copy_result_for_operation(script_value, operation)

	var data := default_data
	var successful := true
	var code := GameServicesResult.Code.OK
	var message := ""
	var platform_code: Variant = null
	if script_value is Dictionary:
		var script: Dictionary = script_value
		if script.has("data"):
			data = script["data"]
		elif script.has("payload"):
			data = script["payload"]
		if script.has("ok"):
			successful = bool(script["ok"])
		elif script.has("success"):
			successful = bool(script["success"])
		elif script.has("succeeded"):
			successful = bool(script["succeeded"])
		elif script.has("failure"):
			successful = not bool(script["failure"])
		elif script.has("result"):
			successful = str(script["result"]).to_lower() not in ["failure", "failed", "error"]
		elif script.has("error_code") or script.has("code") or script.has("error_message"):
			successful = false
		if script.has("error_code"):
			code = _coerce_code(script["error_code"])
		elif script.has("code"):
			code = _coerce_code(script["code"])
		if script.has("error_message"):
			message = str(script["error_message"])
		elif script.has("message"):
			message = str(script["message"])
		if script.has("platform_code"):
			platform_code = script["platform_code"]
		var configured_payload := _payload_for(operation)
		if not script.has("data") and not script.has("payload"):
			var has_outcome_fields := (
				script.has("ok")
				or script.has("success")
				or script.has("failure")
				or script.has("error_code")
				or script.has("code")
				or script.has("error_message")
				or script.has("message")
				or script.has("platform_code")
				or script.has("delay_seconds")
				or script.has("delay")
			)
			if not has_outcome_fields:
				data = script
			elif configured_payload != null:
				data = configured_payload
	elif script_value is bool:
		successful = bool(script_value)
		var configured_payload := _payload_for(operation)
		if configured_payload != null:
			data = configured_payload
	elif script_value is String or script_value is StringName:
		var marker := str(script_value).to_lower()
		if marker in ["failure", "failed", "error"]:
			successful = false
		elif marker not in ["success", "ok", "pass"]:
			data = script_value
		else:
			var configured_payload := _payload_for(operation)
			if configured_payload != null:
				data = configured_payload
	else:
		if script_value != null:
			data = script_value
		var configured_payload := _payload_for(operation)
		if configured_payload != null:
			data = configured_payload

	if successful:
		return GameServicesResult.success(operation, data, provider_name())
	if code == GameServicesResult.Code.OK:
		code = GameServicesResult.Code.PLATFORM_ERROR
	if message.is_empty():
		message = "Mock scripted failure for %s" % operation
	return GameServicesResult.failure(
		operation,
		code,
		message,
		provider_name(),
		platform_code,
		data
	)


func _copy_result_for_operation(result: GameServicesResult, operation: StringName) -> GameServicesResult:
	if result.ok:
		return GameServicesResult.success(
			operation,
			result.data,
			provider_name(),
			result.raw_data
		)
	return GameServicesResult.failure(
		operation,
		result.error_code,
		result.error_message,
		provider_name(),
		result.platform_code,
		result.data,
		result.raw_data
	)


func _presentation_result_for(operation: StringName) -> GameServicesResult:
	var key := String(operation)
	var value: Variant = _control_value(presentation_results, key, null)
	return value as GameServicesResult if value is GameServicesResult else null


func _payload_for(operation: StringName) -> Variant:
	var key := String(operation)
	if _has_control(operation_payloads, key):
		return _duplicate_value(_control_value(operation_payloads, key))
	if _has_control(presentation_payloads, key):
		return _duplicate_value(_control_value(presentation_payloads, key))
	if operation in [&"show_achievements", &"show_leaderboards"]:
		return {
			"presentation_accepted": presentation_accepted,
			"accepted": presentation_accepted,
		}
	return null


func _has_operation_script(operation: StringName) -> bool:
	var key := String(operation)
	return _has_control(operation_scripts, key) or _has_control(operation_failures, key)


func _next_operation_script(operation: StringName) -> Variant:
	var key := String(operation)
	var from_failure_script := not _has_control(operation_scripts, key) and _has_control(operation_failures, key)
	var value: Variant = _control_value(
		operation_scripts,
		key,
		_control_value(operation_failures, key, null)
	)
	if not value is Array:
		return {
			"ok": false,
			"error_code": value,
		} if from_failure_script and not value is GameServicesResult and not value is Dictionary else value
	var entries: Array = value
	if entries.is_empty():
		return null
	var index := int(_script_positions.get(key, 0))
	var selected_index := mini(index, entries.size() - 1)
	_script_positions[key] = index + 1
	var entry: Variant = entries[selected_index]
	return {
		"ok": false,
		"error_code": entry,
	} if from_failure_script and not entry is GameServicesResult and not entry is Dictionary else entry


func _delay_for(operation: StringName, script_value: Variant) -> float:
	var key := String(operation)
	var configured: Variant = _control_value(operation_delays, key, null)
	if configured is Array:
		var entries: Array = configured
		if not entries.is_empty():
			var index := int(_delay_positions.get(key, 0))
			configured = entries[mini(index, entries.size() - 1)]
			_delay_positions[key] = index + 1
	if script_value is Dictionary:
		var script: Dictionary = script_value
		if script.has("delay_seconds"):
			configured = script["delay_seconds"]
		elif script.has("delay"):
			configured = script["delay"]
	if configured == null and operation in [&"show_achievements", &"show_leaderboards"]:
		configured = presentation_delay_seconds
	return maxf(float(configured if configured != null else 0.0), 0.0)


func _has_control(mapping: Dictionary, key: String) -> bool:
	return mapping.has(key) or mapping.has(StringName(key))


func _control_value(
	mapping: Dictionary,
	key: String,
	default_value: Variant = null
) -> Variant:
	if mapping.has(key):
		return mapping[key]
	var string_name := StringName(key)
	return mapping[string_name] if mapping.has(string_name) else default_value


func _schedule(
	result: GameServicesResult,
	operation: StringName,
	delay_seconds: float
) -> GameServicesRequest:
	var request := _new_request(operation)
	request.provider = provider_name()
	_pending_requests[request.id] = request
	if delay_seconds <= 0.0:
		call_deferred("_finish_scheduled", request, result)
		return request
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		(main_loop as SceneTree).create_timer(delay_seconds).timeout.connect(
			Callable(self, "_finish_scheduled").bind(request, result),
			CONNECT_ONE_SHOT
		)
	else:
		call_deferred("_finish_scheduled", request, result)
	return request


func _finish_scheduled(request: GameServicesRequest, result: GameServicesResult) -> void:
	_pending_requests.erase(request.id)
	if not request.is_completed:
		request.complete(result)


func _cancel_pending_requests() -> void:
	var pending := _pending_requests.values()
	_pending_requests.clear()
	for value: Variant in pending:
		var request := value as GameServicesRequest
		if request == null or request.is_completed:
			continue
		request.complete(GameServicesResult.failure(
			request.operation,
			GameServicesResult.Code.CANCELLED,
			"Mock provider shut down before the request completed",
			provider_name()
		))


func _record_call(operation: StringName, arguments: Array) -> void:
	var copied_arguments: Array = []
	for argument: Variant in arguments:
		copied_arguments.append(_duplicate_value(argument))
	calls.append({
			"sequence": calls.size() + 1,
			"operation": String(operation),
			"method": String(operation),
			"name": String(operation),
			"arguments": copied_arguments,
	})


func _apply_authentication(result: GameServicesResult) -> void:
	var payload: Variant = result.data
	if payload is Dictionary and payload.get("player") is Dictionary:
		_player = payload["player"].duplicate(true)
		_authenticated = bool(payload.get("authenticated", true))
	else:
		_authenticated = true
	authentication_changed.emit(true, _player.duplicate(true))


func _apply_unlock(_result: GameServicesResult, platform_id: String) -> void:
	_achievement_progress[platform_id] = 1.0


func _apply_progress(
	_result: GameServicesResult,
	platform_id: String,
	progress: float
) -> void:
	_achievement_progress[platform_id] = progress


func _apply_score(_result: GameServicesResult, platform_id: String, score: int) -> void:
	_scores[platform_id] = score


func _apply_save(
	_result: GameServicesResult,
	name: String,
	data: PackedByteArray,
	metadata: Dictionary
) -> void:
	_saved_games[name] = {
		"data": data.duplicate(),
		"metadata": metadata.duplicate(true),
	}


func _apply_delete(_result: GameServicesResult, id: String) -> void:
	_saved_games.erase(id)


func _unsupported(operation: StringName) -> GameServicesRequest:
	var request := _new_request(operation)
	request.provider = provider_name()
	request.complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.UNSUPPORTED,
		"The mock provider does not support %s" % operation,
		provider_name()
	))
	return request


func _not_authenticated(operation: StringName) -> GameServicesRequest:
	var request := _new_request(operation)
	request.provider = provider_name()
	request.complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.NOT_AUTHENTICATED,
		"Authenticate before calling %s" % operation,
		provider_name()
	))
	return request


func _coerce_code(value: Variant) -> GameServicesResult.Code:
	if value is String or value is StringName:
		match str(value).to_lower():
			"ok", "success":
				return GameServicesResult.Code.OK
			"unavailable":
				return GameServicesResult.Code.UNAVAILABLE
			"unsupported":
				return GameServicesResult.Code.UNSUPPORTED
			"not_authenticated", "notauthenticated":
				return GameServicesResult.Code.NOT_AUTHENTICATED
			"invalid_argument", "invalidargument":
				return GameServicesResult.Code.INVALID_ARGUMENT
			"not_configured", "notconfigured":
				return GameServicesResult.Code.NOT_CONFIGURED
			"platform_error", "platformerror":
				return GameServicesResult.Code.PLATFORM_ERROR
			"cancelled", "canceled":
				return GameServicesResult.Code.CANCELLED
			"busy":
				return GameServicesResult.Code.BUSY
			"not_found", "notfound":
				return GameServicesResult.Code.NOT_FOUND
			"invalid_data", "invaliddata":
				return GameServicesResult.Code.INVALID_DATA
	return int(value) as GameServicesResult.Code


func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	if value is PackedByteArray:
		return value.duplicate()
	return value
