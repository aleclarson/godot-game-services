class_name GameServicesAuthentication
extends RefCounted

## Result value for an explicit authentication attempt.

var authenticated: bool = false
var player: GameServicesPlayer
var provider: StringName = &""
var raw: Variant = {}

## Convenience proxies keep authentication results pleasant to use while the
## explicit `.player` member documents the nested payload.
var id: String:
	get:
		return player.id

var display_name: String:
	get:
		return player.display_name

var alias: String:
	get:
		return player.alias


func _init(
	p_authenticated: bool = false,
	p_player: GameServicesPlayer = null,
	p_provider: StringName = &"",
	p_raw: Variant = null
) -> void:
	authenticated = p_authenticated
	player = p_player if p_player != null else GameServicesPlayer.new()
	provider = p_provider
	raw = p_raw if p_raw != null else {}


static func from_dictionary(
	value: Variant,
	fallback_provider: StringName = &""
) -> GameServicesAuthentication:
	if value is GameServicesAuthentication:
		return value
	if value is GameServicesPlayer:
		return GameServicesAuthentication.new(true, value, fallback_provider, value.raw)
	if not value is Dictionary:
		return GameServicesAuthentication.new(false, null, fallback_provider, value)
	var source: Dictionary = value
	var player_value: Variant = source.get("player", source)
	var player := GameServicesPlayer.from_dictionary(player_value, fallback_provider)
	return GameServicesAuthentication.new(
		bool(source.get("authenticated", not player.is_empty())),
		player,
		StringName(str(source.get("provider", fallback_provider))),
		source.duplicate(true)
	)


func is_empty() -> bool:
	return not authenticated and player.is_empty()


func get(key: StringName, default_value: Variant = null) -> Variant:
	match key:
		&"authenticated":
			return authenticated
		&"player":
			return player
		&"id":
			return player.id
		&"display_name":
			return player.display_name
		&"alias":
			return player.alias
		&"provider":
			return String(provider)
	return default_value


func to_dictionary() -> Dictionary:
	return {
		"authenticated": authenticated,
		"player": player.to_dictionary(),
		"provider": String(provider),
		"raw": _duplicate_value(raw),
	}


func _get(property: StringName) -> Variant:
	return get(property)


func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
