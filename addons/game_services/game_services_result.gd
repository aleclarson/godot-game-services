class_name GameServicesResult
extends RefCounted

## Portable result returned by every asynchronous game-services request.

enum Code {
	OK = 0,
	UNAVAILABLE = 1,
	UNSUPPORTED = 2,
	NOT_AUTHENTICATED = 3,
	INVALID_ARGUMENT = 4,
	NOT_CONFIGURED = 5,
	PLATFORM_ERROR = 6,
	CANCELLED = 7,
	CONFLICT = 8,
	NOT_FOUND = 9,
	INTERNAL_ERROR = 10,
	INVALID_DATA = 11,
}

var ok: bool = false
var operation: StringName = &""
var data: Variant
## The normalized value exposed through [member data]. This keeps the original
## provider payload available for diagnostics without making callers depend on
## transport dictionaries.
var raw_data: Variant
var error_code: Code = Code.OK
var error_message: String = ""
var platform_code: Variant
var provider: StringName = &""
## The request ID that produced this result. Helper wrappers keep the original
## value so diagnostics can be correlated with the native request.
var request_id: int = 0

var code: Code:
	get:
		return error_code

var message: String:
	get:
		return error_message

## Short alias for [member raw_data].
var raw: Variant:
	get:
		return raw_data
	set(value):
		raw_data = value

## Alias that makes successful result composition read naturally.
var value: Variant:
	get:
		return data
	set(new_value):
		data = new_value


func _init(
	p_ok: bool = false,
	p_operation: StringName = &"",
	p_data: Variant = null,
	p_error_code: Code = Code.OK,
	p_error_message: String = "",
	p_platform_code: Variant = null,
	p_provider: StringName = &"",
	p_raw_data: Variant = null
) -> void:
	ok = p_ok
	operation = p_operation
	data = p_data
	raw_data = p_raw_data if p_raw_data != null else _duplicate_value(p_data)
	error_code = p_error_code
	error_message = p_error_message
	platform_code = p_platform_code
	provider = p_provider


static func success(
	p_operation: StringName,
	p_data: Variant = null,
	p_provider: StringName = &"",
	p_raw_data: Variant = null
) -> GameServicesResult:
	return GameServicesResult.new(
		true,
		p_operation,
		p_data,
		Code.OK,
		"",
		null,
		p_provider,
		p_raw_data
	)


static func failure(
	p_operation: StringName,
	p_code: Code,
	p_message: String,
	p_provider: StringName = &"",
	p_platform_code: Variant = null,
	p_data: Variant = null,
	p_raw_data: Variant = null
) -> GameServicesResult:
	return GameServicesResult.new(
		false,
		p_operation,
		p_data,
		p_code,
		p_message,
		p_platform_code,
		p_provider,
		p_raw_data
	)


## Return whether the operation succeeded. The method form is useful when a
## result is passed through a callable chain and avoids reaching into fields.
func is_success() -> bool:
	return ok and error_code == Code.OK


func is_ok() -> bool:
	return is_success()


func succeeded() -> bool:
	return is_success()


func is_failure() -> bool:
	return not is_success()


func failed() -> bool:
	return is_failure()


func is_code(code: Code) -> bool:
	return error_code == code


func code_is(code: Code) -> bool:
	return is_code(code)


func has_code(code: Code) -> bool:
	return is_code(code)


func is_error_code(code: Code) -> bool:
	return not is_success() and is_code(code)


func is_cancelled() -> bool:
	return is_code(Code.CANCELLED)


func is_retryable() -> bool:
	return is_code(Code.UNAVAILABLE) or is_code(Code.PLATFORM_ERROR)


func has_value() -> bool:
	return is_success() and data != null


## Return the normalized value on success, or [param default_value] after a
## failed operation. This never changes the result's error metadata.
func value_or(default_value: Variant = null) -> Variant:
	return data if is_success() else default_value


func unwrap(default_value: Variant = null) -> Variant:
	return value_or(default_value)


func get_value(default_value: Variant = null) -> Variant:
	return value_or(default_value)


func typed_value(default_value: Variant = null) -> Variant:
	return value_or(default_value)


## Generic extraction counterpart to the specialized helpers below. The
## optional type argument is intentionally advisory: GDScript class values are
## not runtime-generic, while the returned payload remains a concrete typed
## value object from the facade.
func extract(_expected_type: Variant = null, default_value: Variant = null) -> Variant:
	return value_or(default_value)


## Extract the common typed payloads without requiring callers to inspect the
## operation name. A failed result always returns [param default_value].
func player_or(default_value: GameServicesPlayer = null) -> GameServicesPlayer:
	if not is_success():
		return default_value
	if data is GameServicesPlayer:
		return data
	if data is GameServicesAuthentication:
		return data.player
	return GameServicesPlayer.from_dictionary(data, provider)


func authentication_or(default_value: GameServicesAuthentication = null) -> GameServicesAuthentication:
	if not is_success():
		return default_value
	if data is GameServicesAuthentication:
		return data
	return GameServicesAuthentication.from_dictionary(data, provider)


func achievement_or(default_value: GameServicesAchievement = null) -> GameServicesAchievement:
	if not is_success():
		return default_value
	if data is GameServicesAchievement:
		return data
	return GameServicesAchievement.from_dictionary(data, provider)


func achievements_or(default_value: GameServicesAchievementCollection = null) -> GameServicesAchievementCollection:
	if not is_success():
		return default_value
	if data is GameServicesAchievementCollection:
		return data
	if data is Array:
		return GameServicesAchievementCollection.new(data)
	return default_value


func score_or(default_value: GameServicesLeaderboardScore = null) -> GameServicesLeaderboardScore:
	if not is_success():
		return default_value
	if data is GameServicesLeaderboardScore:
		return data
	return GameServicesLeaderboardScore.from_dictionary(data, provider)


func credentials_or(default_value: GameServicesServerCredentials = null) -> GameServicesServerCredentials:
	if not is_success():
		return default_value
	if data is GameServicesServerCredentials:
		return data
	return GameServicesServerCredentials.from_dictionary(data, provider)


func presentation_or(default_value: GameServicesPresentationOutcome = null) -> GameServicesPresentationOutcome:
	if not is_success():
		return default_value
	if data is GameServicesPresentationOutcome:
		return data
	return GameServicesPresentationOutcome.from_dictionary(data, operation, provider)


func get_player(default_value: GameServicesPlayer = null) -> GameServicesPlayer:
	return player_or(default_value)


func get_achievement(default_value: GameServicesAchievement = null) -> GameServicesAchievement:
	return achievement_or(default_value)


func get_achievements(default_value: GameServicesAchievementCollection = null) -> GameServicesAchievementCollection:
	return achievements_or(default_value)


func get_score(default_value: GameServicesLeaderboardScore = null) -> GameServicesLeaderboardScore:
	return score_or(default_value)


func get_credentials(default_value: GameServicesServerCredentials = null) -> GameServicesServerCredentials:
	return credentials_or(default_value)


func get_presentation(default_value: GameServicesPresentationOutcome = null) -> GameServicesPresentationOutcome:
	return presentation_or(default_value)


## Synchronous value mapping. Failed results are returned unchanged, including
## operation, provider, portable code, platform code, and raw diagnostics.
func map_value(transform: Callable) -> GameServicesResult:
	if not is_success() or not transform.is_valid():
		return self
	var mapped := transform.call(data)
	return with_data(mapped)


func map(transform: Callable) -> GameServicesResult:
	return map_value(transform)


func with_data(new_data: Variant, new_raw_data: Variant = null) -> GameServicesResult:
	var copied := GameServicesResult.new(
		ok,
		operation,
		new_data,
		error_code,
		error_message,
		platform_code,
		provider,
		raw_data if new_raw_data == null else new_raw_data
	)
	copied.request_id = request_id
	return copied


func to_dictionary() -> Dictionary:
	return {
		"ok": ok,
		"operation": String(operation),
		"data": _serializable_value(data),
		"raw_data": _serializable_value(raw_data),
		"raw": _serializable_value(raw_data),
		"error_code": error_code,
		"error_name": Code.find_key(error_code),
		"error_message": error_message,
		"platform_code": platform_code,
		"provider": String(provider),
		"request_id": request_id,
	}


func _serializable_value(value_to_convert: Variant) -> Variant:
	if typeof(value_to_convert) == TYPE_OBJECT and value_to_convert.has_method("to_dictionary"):
		return value_to_convert.to_dictionary()
	if value_to_convert is Array:
		var converted: Array = []
		for item: Variant in value_to_convert:
			converted.append(_serializable_value(item))
		return converted
	if value_to_convert is Dictionary:
		var converted_dictionary: Dictionary = {}
		for key: Variant in value_to_convert:
			converted_dictionary[key] = _serializable_value(value_to_convert[key])
		return converted_dictionary
	return value_to_convert


func _duplicate_value(value_to_duplicate: Variant) -> Variant:
	if value_to_duplicate is Dictionary or value_to_duplicate is Array:
		return value_to_duplicate.duplicate(true)
	if typeof(value_to_duplicate) == TYPE_OBJECT and value_to_duplicate.has_method("duplicate_player"):
		return value_to_duplicate.duplicate_player()
	return value_to_duplicate
