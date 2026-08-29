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
}

var ok: bool = false
var operation: StringName = &""
var data: Variant
var error_code: Code = Code.OK
var error_message: String = ""
var platform_code: Variant
var provider: StringName = &""


func _init(
	p_ok: bool = false,
	p_operation: StringName = &"",
	p_data: Variant = null,
	p_error_code: Code = Code.OK,
	p_error_message: String = "",
	p_platform_code: Variant = null,
	p_provider: StringName = &""
) -> void:
	ok = p_ok
	operation = p_operation
	data = p_data
	error_code = p_error_code
	error_message = p_error_message
	platform_code = p_platform_code
	provider = p_provider


static func success(
	p_operation: StringName,
	p_data: Variant = null,
	p_provider: StringName = &""
) -> GameServicesResult:
	return GameServicesResult.new(
		true,
		p_operation,
		p_data,
		Code.OK,
		"",
		null,
		p_provider
	)


static func failure(
	p_operation: StringName,
	p_code: Code,
	p_message: String,
	p_provider: StringName = &"",
	p_platform_code: Variant = null,
	p_data: Variant = null
) -> GameServicesResult:
	return GameServicesResult.new(
		false,
		p_operation,
		p_data,
		p_code,
		p_message,
		p_platform_code,
		p_provider
	)


func to_dictionary() -> Dictionary:
	return {
		"ok": ok,
		"operation": String(operation),
		"data": data,
		"error_code": error_code,
		"error_name": Code.find_key(error_code),
		"error_message": error_message,
		"platform_code": platform_code,
		"provider": String(provider),
	}
