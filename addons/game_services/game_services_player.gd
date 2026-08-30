class_name GameServicesPlayer
extends RefCounted

## Normalized player profile returned by authentication and player-loading calls.

var id: String = ""
var display_name: String = ""
var alias: String = ""
var provider: StringName = &""
var avatar_uri: String = ""
var title: String = ""
var raw: Variant = {}

var player_id: String:
	get:
		return id

var logical_id: StringName:
	get:
		return StringName(id)


func _init(
	p_id: String = "",
	p_display_name: String = "",
	p_alias: String = "",
	p_provider: StringName = &"",
	p_avatar_uri: String = "",
	p_title: String = "",
	p_raw: Variant = null
) -> void:
	id = p_id
	display_name = p_display_name
	alias = p_alias
	provider = p_provider
	avatar_uri = p_avatar_uri
	title = p_title
	raw = p_raw if p_raw != null else {}


static func from_dictionary(value: Variant, fallback_provider: StringName = &"") -> GameServicesPlayer:
	if value is GameServicesPlayer:
		return value
	if not value is Dictionary:
		return GameServicesPlayer.new()
	var source: Dictionary = value
	var source_provider := StringName(str(source.get("provider", fallback_provider)))
	return GameServicesPlayer.new(
		str(source.get("id", source.get("player_id", source.get("playerId", "")))),
		str(source.get("display_name", source.get("displayName", ""))),
		str(source.get("alias", source.get("player_alias", ""))),
		source_provider,
		str(source.get("avatar_uri", source.get("iconImageUri", ""))),
		str(source.get("title", "")),
		source.duplicate(true)
	)


func is_empty() -> bool:
	return id.is_empty()


func has(key: StringName) -> bool:
	match key:
		&"id":
			return not id.is_empty()
		&"display_name":
			return not display_name.is_empty()
		&"alias":
			return not alias.is_empty()
		&"provider":
			return not provider.is_empty()
		&"avatar_uri":
			return not avatar_uri.is_empty()
		&"title":
			return not title.is_empty()
	return false


func get(key: StringName, default_value: Variant = null) -> Variant:
	match key:
		&"id":
			return id
		&"display_name":
			return display_name
		&"alias":
			return alias
		&"provider":
			return String(provider)
		&"avatar_uri":
			return avatar_uri
		&"title":
			return title
	return default_value


func duplicate_player() -> GameServicesPlayer:
	return GameServicesPlayer.new(
		id,
		display_name,
		alias,
		provider,
		avatar_uri,
		title,
		_duplicate_value(raw)
	)


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"alias": alias,
		"provider": String(provider),
		"avatar_uri": avatar_uri,
		"title": title,
		"raw": _duplicate_value(raw),
	}


func _get(property: StringName) -> Variant:
	return get(property)


func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
