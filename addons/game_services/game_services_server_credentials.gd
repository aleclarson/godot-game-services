class_name GameServicesServerCredentials
extends RefCounted

## Discriminated server-verification credential.

var kind: String = ""
var authorization_code: String = ""
var token: String = ""
var public_key_url: String = ""
var signature: String = ""
var salt: String = ""
var timestamp: Variant
var player_id: String = ""
var provider: StringName = &""
var raw: Variant = {}

var server_auth_code: String:
	get:
		return authorization_code

var access_token: String:
	get:
		return token

var credential: String:
	get:
		return value()


func _init(
	p_kind: String = "",
	p_provider: StringName = &"",
	p_raw: Variant = null
) -> void:
	kind = p_kind
	provider = p_provider
	raw = p_raw if p_raw != null else {}


static func from_dictionary(
	value: Variant,
	fallback_provider: StringName = &""
) -> GameServicesServerCredentials:
	if value is GameServicesServerCredentials:
		return value
	var source: Dictionary = value if value is Dictionary else {}
	var credentials := GameServicesServerCredentials.new(
		str(source.get("kind", "")),
		StringName(str(source.get("provider", fallback_provider))),
		source.duplicate(true) if value is Dictionary else value
	)
	credentials.authorization_code = str(source.get("authorization_code", ""))
	credentials.token = str(source.get("token", ""))
	credentials.public_key_url = str(source.get("public_key_url", ""))
	credentials.signature = str(source.get("signature", ""))
	credentials.salt = str(source.get("salt", ""))
	credentials.timestamp = source.get("timestamp")
	credentials.player_id = str(source.get("player_id", ""))
	return credentials


func is_game_center() -> bool:
	return kind == "game_center_identity_signature"


func is_play_games() -> bool:
	return kind == "play_games_server_auth_code"


func value() -> String:
	return authorization_code if not authorization_code.is_empty() else token


func get(key: StringName, default_value: Variant = null) -> Variant:
	match key:
		&"kind":
			return kind
		&"authorization_code":
			return authorization_code
		&"token":
			return token
		&"public_key_url":
			return public_key_url
		&"signature":
			return signature
		&"salt":
			return salt
		&"timestamp":
			return timestamp
		&"player_id":
			return player_id
		&"provider":
			return String(provider)
	return default_value


func to_dictionary() -> Dictionary:
	return {
		"kind": kind,
		"authorization_code": authorization_code,
		"token": token,
		"public_key_url": public_key_url,
		"signature": signature,
		"salt": salt,
		"timestamp": timestamp,
		"player_id": player_id,
		"provider": String(provider),
		"raw": _duplicate_value(raw),
	}


func _get(property: StringName) -> Variant:
	return get(property)


func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
