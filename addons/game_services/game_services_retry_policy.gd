class_name GameServicesRetryPolicy
extends RefCounted

## Explicit policy for replaying a request factory after portable failures.
##
## max_attempts counts the initial attempt. Retries are never enabled by the
## facade or by a normal GameServicesRequest; callers must opt into this policy.

var max_attempts: int = 3:
	set(value):
		max_attempts = maxi(value, 1)
var initial_delay_seconds: float = 0.0:
	set(value):
		initial_delay_seconds = maxf(value, 0.0)
var backoff_multiplier: float = 2.0:
	set(value):
		backoff_multiplier = maxf(value, 1.0)
var max_delay_seconds: float = 30.0:
	set(value):
		max_delay_seconds = maxf(value, 0.0)
var retry_codes: Array[GameServicesResult.Code] = [
	GameServicesResult.Code.UNAVAILABLE,
	GameServicesResult.Code.PLATFORM_ERROR,
]
var retry_if: Callable

var max_retries: int:
	get:
		return maxi(max_attempts - 1, 0)
	set(value):
		max_attempts = maxi(value, 0) + 1

var base_delay_seconds: float:
	get:
		return initial_delay_seconds
	set(value):
		initial_delay_seconds = value

var multiplier: float:
	get:
		return backoff_multiplier
	set(value):
		backoff_multiplier = value


func _init(p_max_attempts: int = 3) -> void:
	max_attempts = maxi(p_max_attempts, 1)


static func from_dictionary(options: Dictionary) -> GameServicesRetryPolicy:
	var policy := GameServicesRetryPolicy.new()
	if options.has("max_attempts"):
		policy.max_attempts = int(options["max_attempts"])
	elif options.has("max_retries"):
		policy.max_attempts = int(options["max_retries"]) + 1
	if options.has("initial_delay_seconds"):
		policy.initial_delay_seconds = float(options["initial_delay_seconds"])
	elif options.has("base_delay_seconds"):
		policy.initial_delay_seconds = float(options["base_delay_seconds"])
	elif options.has("delay_seconds"):
		policy.initial_delay_seconds = float(options["delay_seconds"])
	if options.has("backoff_multiplier"):
		policy.backoff_multiplier = float(options["backoff_multiplier"])
	elif options.has("multiplier"):
		policy.backoff_multiplier = float(options["multiplier"])
	if options.has("max_delay_seconds"):
		policy.max_delay_seconds = float(options["max_delay_seconds"])
	if options.has("retry_codes") and options["retry_codes"] is Array:
		policy.retry_codes.clear()
		for code: Variant in options["retry_codes"]:
			policy.retry_codes.append(_coerce_code(code))
	if options.get("retry_if") is Callable:
		policy.retry_if = options["retry_if"]
	return policy


func copy_policy() -> GameServicesRetryPolicy:
	var copy := GameServicesRetryPolicy.new(max_attempts)
	copy.initial_delay_seconds = initial_delay_seconds
	copy.backoff_multiplier = backoff_multiplier
	copy.max_delay_seconds = max_delay_seconds
	copy.retry_codes = retry_codes.duplicate()
	copy.retry_if = retry_if
	return copy


func should_retry(result: GameServicesResult, attempt_number: int) -> bool:
	if result == null or result.is_success() or attempt_number >= max_attempts:
		return false
	if retry_if.is_valid():
		return bool(retry_if.call(result))
	return retry_codes.has(result.error_code)


func delay_for_retry(retry_number: int) -> float:
	if retry_number <= 0:
		return 0.0
	var delay := initial_delay_seconds * pow(backoff_multiplier, retry_number - 1)
	return minf(delay, max_delay_seconds)


func to_dictionary() -> Dictionary:
	var codes: Array[int] = []
	for code: GameServicesResult.Code in retry_codes:
		codes.append(int(code))
	return {
		"max_attempts": max_attempts,
		"initial_delay_seconds": initial_delay_seconds,
		"backoff_multiplier": backoff_multiplier,
		"max_delay_seconds": max_delay_seconds,
		"retry_codes": codes,
	}


static func _coerce_code(value: Variant) -> GameServicesResult.Code:
	if value is String or value is StringName:
		var key: String = str(value).to_upper()
		var found := GameServicesResult.Code.keys().find(key)
		return GameServicesResult.Code.values()[found] if found >= 0 else GameServicesResult.Code.PLATFORM_ERROR
	return int(value)
