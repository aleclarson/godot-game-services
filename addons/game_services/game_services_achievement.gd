class_name GameServicesAchievement
extends RefCounted

## Normalized achievement state.

var id: String = ""
var logical_id: StringName = &""
var platform_id: String = ""
var progress: float = 0.0
var unlocked: bool = false
var name: String = ""
var description: String = ""
var hidden: bool = false
var current_steps: int = 0
var total_steps: int = 0
var submitted: bool = true
var provider: StringName = &""
var raw: Variant = {}

var achievement_id: StringName:
	get:
		return logical_id


func _init(
	p_id: String = "",
	p_platform_id: String = "",
	p_progress: float = 0.0,
	p_unlocked: bool = false,
	p_provider: StringName = &"",
	p_raw: Variant = null
) -> void:
	id = p_id
	logical_id = StringName(p_id)
	platform_id = p_platform_id
	progress = clampf(p_progress, 0.0, 1.0)
	unlocked = p_unlocked
	provider = p_provider
	raw = p_raw if p_raw != null else {}


static func from_dictionary(
	value: Variant,
	fallback_provider: StringName = &"",
	fallback_id: String = ""
) -> GameServicesAchievement:
	if value is GameServicesAchievement:
		return value
	if not value is Dictionary:
		return GameServicesAchievement.new(fallback_id, "", 0.0, false, fallback_provider, value)
	var source: Dictionary = value
	var logical := str(source.get("id", source.get("logical_id", fallback_id)))
	var platform := str(source.get("platform_id", source.get("achievementId", "")))
	var achievement := GameServicesAchievement.new(
		logical,
		platform,
		float(source.get("progress", 0.0)),
		bool(source.get("unlocked", false)),
		StringName(str(source.get("provider", fallback_provider))),
		source.duplicate(true)
	)
	achievement.logical_id = StringName(logical)
	achievement.name = str(source.get("name", ""))
	achievement.description = str(source.get("description", ""))
	achievement.hidden = bool(source.get("hidden", false))
	achievement.current_steps = int(source.get("current_steps", source.get("currentSteps", 0)))
	achievement.total_steps = int(source.get("total_steps", source.get("totalSteps", 0)))
	achievement.submitted = bool(source.get("submitted", true))
	return achievement


func is_complete() -> bool:
	return unlocked or progress >= 1.0


func get(key: StringName, default_value: Variant = null) -> Variant:
	match key:
		&"id", &"logical_id":
			return id
		&"platform_id":
			return platform_id
		&"progress":
			return progress
		&"unlocked":
			return unlocked
		&"name":
			return name
		&"description":
			return description
		&"hidden":
			return hidden
		&"current_steps":
			return current_steps
		&"total_steps":
			return total_steps
		&"submitted":
			return submitted
		&"provider":
			return String(provider)
	return default_value


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"platform_id": platform_id,
		"progress": progress,
		"unlocked": unlocked,
		"name": name,
		"description": description,
		"hidden": hidden,
		"current_steps": current_steps,
		"total_steps": total_steps,
		"submitted": submitted,
		"provider": String(provider),
		"raw": _duplicate_value(raw),
	}


func _get(property: StringName) -> Variant:
	return get(property)


func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
