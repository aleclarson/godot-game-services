class_name GameServicesPresentationOutcome
extends RefCounted

## Outcome for an accepted UI/review handoff.

var accepted: bool = false
var presentation_accepted: bool = false
var handoff: String = ""
var operation: StringName = &""
var platform: StringName = &""
var platform_id: String = ""
var url: String = ""
var native: bool = false
var provider: StringName = &""
var raw: Variant = {}

var destination_url: String:
	get:
		return url

var handoff_accepted: bool:
	get:
		return accepted


func _init(
	p_accepted: bool = false,
	p_handoff: String = "",
	p_operation: StringName = &"",
	p_provider: StringName = &"",
	p_raw: Variant = null
) -> void:
	accepted = p_accepted
	presentation_accepted = p_accepted
	handoff = p_handoff
	operation = p_operation
	provider = p_provider
	raw = p_raw if p_raw != null else {}


static func from_dictionary(
	value: Variant,
	p_operation: StringName = &"",
	fallback_provider: StringName = &""
) -> GameServicesPresentationOutcome:
	if value is GameServicesPresentationOutcome:
		return value
	var source: Dictionary = value if value is Dictionary else {}
	var accepted := bool(source.get(
		"accepted",
		source.get("presentation_accepted", source.get("handoff_accepted", true))
	))
	var handoff := str(source.get("handoff", ""))
	var outcome := GameServicesPresentationOutcome.new(
		accepted,
		handoff,
		p_operation,
		StringName(str(source.get("provider", fallback_provider))),
		source.duplicate(true) if value is Dictionary else value
	)
	outcome.platform = StringName(str(source.get("platform", "")))
	outcome.platform_id = str(source.get("platform_id", ""))
	outcome.url = str(source.get("url", source.get("destination_url", "")))
	outcome.native = bool(source.get("native", false))
	return outcome


func is_handoff_accepted() -> bool:
	return accepted


func get(key: StringName, default_value: Variant = null) -> Variant:
	match key:
		&"accepted", &"presentation_accepted", &"handoff_accepted":
			return accepted
		&"handoff":
			return handoff
		&"operation":
			return operation
		&"platform":
			return String(platform)
		&"platform_id":
			return platform_id
		&"url", &"destination_url":
			return url
		&"native":
			return native
		&"provider":
			return String(provider)
	return default_value


func to_dictionary() -> Dictionary:
	return {
		"accepted": accepted,
		"presentation_accepted": accepted,
		"handoff": handoff,
		"operation": String(operation),
		"platform": String(platform),
		"platform_id": platform_id,
		"url": url,
		"native": native,
		"provider": String(provider),
		"raw": _duplicate_value(raw),
	}


func _get(property: StringName) -> Variant:
	return get(property)


func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
