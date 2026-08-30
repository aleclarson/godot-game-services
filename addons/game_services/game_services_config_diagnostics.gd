class_name GameServicesConfigDiagnostics
extends RefCounted

## Synchronous diagnostics produced by [GameServicesConfig.validate].
##
## Configuration warnings describe optional features that are not configured;
## errors describe values that cannot be used by a provider.  Only errors block
## GameServices.initialize().

var provider: StringName = &""
var errors: Array[String] = []
var warnings: Array[String] = []

var valid: bool:
	get:
		return errors.is_empty()

var ok: bool:
	get:
		return valid

var has_errors: bool:
	get:
		return not errors.is_empty()

var has_warnings: bool:
	get:
		return not warnings.is_empty()

var error_count: int:
	get:
		return errors.size()

var warning_count: int:
	get:
		return warnings.size()


func _init(p_provider: StringName = &"") -> void:
	provider = p_provider


func is_valid() -> bool:
	return valid


func is_ok() -> bool:
	return valid


func error_messages() -> Array[String]:
	return errors.duplicate()


func warning_messages() -> Array[String]:
	return warnings.duplicate()


func add_error(message: String) -> void:
	if not message.is_empty() and not errors.has(message):
		errors.append(message)


func add_warning(message: String) -> void:
	if not message.is_empty() and not warnings.has(message):
		warnings.append(message)


func summary() -> String:
	if errors.is_empty():
		return "Game services configuration is valid"
	return "Game services configuration is invalid: %s" % "; ".join(errors)


func to_dictionary() -> Dictionary:
	return {
		"provider": String(provider),
		"valid": valid,
		"ok": valid,
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"summary": summary(),
	}


func _get(key: StringName) -> Variant:
	match key:
		&"provider":
			return String(provider)
		&"valid", &"ok":
			return valid
		&"errors":
			return errors
		&"warnings":
			return warnings
		&"summary":
			return summary()
	return null
