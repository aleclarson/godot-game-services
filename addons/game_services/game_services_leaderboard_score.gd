class_name GameServicesLeaderboardScore
extends RefCounted

## Normalized result for a leaderboard score submission.

var id: String = ""
var logical_id: StringName = &""
var leaderboard_id: StringName = &""
var platform_id: String = ""
var score: int = 0
var submitted: bool = true
var rank: int = 0
var provider: StringName = &""
var raw: Variant = {}

var score_id: StringName:
	get:
		return logical_id


func _init(
	p_id: String = "",
	p_platform_id: String = "",
	p_score: int = 0,
	p_submitted: bool = true,
	p_provider: StringName = &"",
	p_raw: Variant = null
) -> void:
	id = p_id
	logical_id = StringName(p_id)
	leaderboard_id = StringName(p_id)
	platform_id = p_platform_id
	score = p_score
	submitted = p_submitted
	provider = p_provider
	raw = p_raw if p_raw != null else {}


static func from_dictionary(
	value: Variant,
	fallback_provider: StringName = &"",
	fallback_id: String = ""
) -> GameServicesLeaderboardScore:
	if value is GameServicesLeaderboardScore:
		return value
	if not value is Dictionary:
		return GameServicesLeaderboardScore.new(fallback_id, "", 0, false, fallback_provider, value)
	var source: Dictionary = value
	var logical := str(source.get("id", source.get("logical_id", fallback_id)))
	var score := GameServicesLeaderboardScore.new(
		logical,
		str(source.get("platform_id", source.get("leaderboard_id", ""))),
		int(source.get("score", 0)),
		bool(source.get("submitted", true)),
		StringName(str(source.get("provider", fallback_provider))),
		source.duplicate(true)
	)
	score.logical_id = StringName(logical)
	score.leaderboard_id = StringName(logical)
	score.rank = int(source.get("rank", 0))
	return score


func get(key: StringName, default_value: Variant = null) -> Variant:
	match key:
		&"id", &"logical_id", &"leaderboard_id":
			return id
		&"platform_id":
			return platform_id
		&"score":
			return score
		&"submitted":
			return submitted
		&"rank":
			return rank
		&"provider":
			return String(provider)
	return default_value


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"platform_id": platform_id,
		"score": score,
		"submitted": submitted,
		"rank": rank,
		"provider": String(provider),
		"raw": _duplicate_value(raw),
	}


func _get(property: StringName) -> Variant:
	return get(property)


func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
