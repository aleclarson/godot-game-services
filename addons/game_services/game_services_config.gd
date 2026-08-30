class_name GameServicesConfig
extends Resource

## Maps game-owned logical identifiers to the identifiers configured in each
## platform console.

const LOGICAL_ID_CHARACTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
const PROVIDER_APPLE := &"apple_game_center"
const PROVIDER_GOOGLE := &"google_play_games"
const PROVIDER_MOCK := &"mock"

@export_category("Runtime")
@export var use_mock_in_editor: bool = true
@export_range(1.0, 120.0, 1.0, "or_greater") var request_timeout_seconds: float = 30.0

@export_category("Apple Game Center")
@export var apple_achievement_ids: Dictionary = {}
@export var apple_leaderboard_ids: Dictionary = {}

@export_category("Google Play Games Services")
@export var google_achievement_ids: Dictionary = {}
@export var google_achievement_steps: Dictionary = {}
@export var google_leaderboard_ids: Dictionary = {}
@export var google_server_client_id: String = ""

@export_category("Store Review")
@export var apple_app_store_id: String = ""
@export var apple_store_review_url: String = ""
@export var google_play_package_name: String = ""
@export var google_play_store_review_url: String = ""
@export var mock_store_review_url: String = ""

@export_category("Mock provider")
@export var mock_player_id: String = "mock-player"
@export var mock_player_display_name: String = "Mock Player"


func achievement_id(logical_id: StringName, provider_name: StringName) -> String:
	return _mapped_id(logical_id, provider_name, apple_achievement_ids, google_achievement_ids)


func leaderboard_id(logical_id: StringName, provider_name: StringName) -> String:
	return _mapped_id(logical_id, provider_name, apple_leaderboard_ids, google_leaderboard_ids)


func achievement_total_steps(logical_id: StringName, provider_name: StringName) -> int:
	if provider_name != &"google_play_games":
		return 0
	return int(_mapping_value(google_achievement_steps, String(logical_id)))


func logical_achievement_id(platform_id: String, provider_name: StringName) -> String:
	return _logical_id(platform_id, provider_name, apple_achievement_ids, google_achievement_ids)


func logical_leaderboard_id(platform_id: String, provider_name: StringName) -> String:
	return _logical_id(platform_id, provider_name, apple_leaderboard_ids, google_leaderboard_ids)


func store_review_url(platform: StringName) -> String:
	match platform:
		&"ios":
			if not apple_store_review_url.strip_edges().is_empty():
				return apple_store_review_url.strip_edges()
			var app_store_id := apple_app_store_id.strip_edges()
			if _digits_only(app_store_id):
				return "https://apps.apple.com/app/id%s?action=write-review" % app_store_id
		&"android":
			if not google_play_store_review_url.strip_edges().is_empty():
				return google_play_store_review_url.strip_edges()
			var package_name := google_play_package_name.strip_edges()
			if not package_name.is_empty():
				return "https://play.google.com/store/apps/details?id=%s" % package_name
		PROVIDER_MOCK:
			return mock_store_review_url.strip_edges()
	return ""


func mock_player() -> Dictionary:
	return {
		"id": mock_player_id,
		"display_name": mock_player_display_name,
		"alias": mock_player_display_name,
		"provider": "mock",
	}


## Validate values synchronously without loading or contacting a native plugin.
##
## Empty optional mappings and destinations are warnings at most. A mapping
## that is present but malformed is an error and blocks GameServices
## initialization. [param provider_name] scopes optional warnings to a provider;
## structural checks still cover every configured platform mapping so a headless
## CI run catches mistakes before a device build.
func validate(provider_name: StringName = &"") -> GameServicesConfigValidation:
	var diagnostics := GameServicesConfigValidation.new(provider_name)
	_validate_runtime(diagnostics)
	_validate_mapping(
		diagnostics,
		"Apple Game Center achievements",
		apple_achievement_ids,
		PROVIDER_APPLE,
		"achievement"
	)
	_validate_mapping(
		diagnostics,
		"Apple Game Center leaderboards",
		apple_leaderboard_ids,
		PROVIDER_APPLE,
		"leaderboard"
	)
	_validate_mapping(
		diagnostics,
		"Google Play Games achievements",
		google_achievement_ids,
		PROVIDER_GOOGLE,
		"achievement"
	)
	_validate_mapping(
		diagnostics,
		"Google Play Games leaderboards",
		google_leaderboard_ids,
		PROVIDER_GOOGLE,
		"leaderboard"
	)
	_validate_google_steps(diagnostics)
	_validate_server_credentials(diagnostics)
	_validate_store_review(diagnostics)
	_validate_optional_warnings(diagnostics, provider_name)
	return diagnostics


## Alias for callers that prefer an explicitly named diagnostics method.
func validate_configuration(provider_name: StringName = &"") -> GameServicesConfigValidation:
	return validate(provider_name)


func validate_for_provider(provider_name: StringName) -> GameServicesConfigValidation:
	return validate(provider_name)


func validation(provider_name: StringName = &"") -> GameServicesConfigValidation:
	return validate(provider_name)


func is_valid(provider_name: StringName = &"") -> bool:
	return validate(provider_name).is_valid()


func _validate_runtime(diagnostics: GameServicesConfigDiagnostics) -> void:
	if is_nan(request_timeout_seconds) or is_inf(request_timeout_seconds):
		diagnostics.add_error(
			"Runtime request_timeout_seconds must be finite"
		)
	elif request_timeout_seconds <= 0.0:
		diagnostics.add_error(
			"Runtime request_timeout_seconds must be greater than zero"
		)


func _validate_mapping(
	diagnostics: GameServicesConfigDiagnostics,
	label: String,
	mapping: Dictionary,
	provider_name: StringName,
	kind: String
) -> void:
	if typeof(mapping) != TYPE_DICTIONARY:
		diagnostics.add_error("%s must be a dictionary" % label)
		return

	var seen_platform_ids: Dictionary = {}
	for key: Variant in mapping:
		var logical_id := _logical_id_value(key)
		if logical_id.is_empty():
			diagnostics.add_error((
				"%s has an invalid logical %s ID '%s'; use a non-empty "
				+ "identifier containing only A-Z, a-z, 0-9, -, ., _, or ~"
			) % [label, kind, str(key)])
			continue
		var platform_value: Variant = mapping[key]
		if typeof(platform_value) != TYPE_STRING and typeof(platform_value) != TYPE_STRING_NAME:
			diagnostics.add_error(
				"%s mapping for '%s' must be a string platform ID (got %s)"
				% [label, logical_id, type_string(typeof(platform_value))]
			)
			continue
		var platform_id := str(platform_value)
		var trimmed_platform_id := platform_id.strip_edges()
		if trimmed_platform_id.is_empty():
			diagnostics.add_error(
				"%s mapping for '%s' must contain a non-empty platform ID"
				% [label, logical_id]
			)
			continue
		if trimmed_platform_id != platform_id or _contains_whitespace(platform_id):
			diagnostics.add_error(
				"%s mapping for '%s' must not contain whitespace"
				% [label, logical_id]
			)
			continue
		if seen_platform_ids.has(trimmed_platform_id):
			diagnostics.add_error(
				"%s maps logical IDs '%s' and '%s' to the same platform ID '%s'"
				% [
					label,
					str(seen_platform_ids[trimmed_platform_id]),
					logical_id,
					trimmed_platform_id,
				]
			)
			continue
		seen_platform_ids[trimmed_platform_id] = logical_id

		if provider_name == PROVIDER_GOOGLE and kind == "achievement":
			if not _mapping_has_id(google_achievement_steps, logical_id):
				diagnostics.add_warning(
					"Google Play Games achievement '%s' has no total-step count; "
					+ "incremental progress will return NOT_CONFIGURED" % logical_id
				)


func _validate_google_steps(diagnostics: GameServicesConfigDiagnostics) -> void:
	if typeof(google_achievement_steps) != TYPE_DICTIONARY:
		diagnostics.add_error("Google Play Games achievement steps must be a dictionary")
		return
	for key: Variant in google_achievement_steps:
		var logical_id := _logical_id_value(key)
		if logical_id.is_empty():
			diagnostics.add_error(
				"Google Play Games achievement steps has an invalid logical ID '%s'"
				% str(key)
			)
			continue
		if not _mapping_has_id(google_achievement_ids, logical_id):
			diagnostics.add_error(
				"Google Play Games achievement steps for '%s' have no achievement mapping"
				% logical_id
			)
		var steps: Variant = _mapping_value(google_achievement_steps, logical_id)
		if typeof(steps) != TYPE_INT:
			diagnostics.add_error(
				"Google Play Games achievement '%s' total steps must be a positive integer"
				% logical_id
			)
		elif int(steps) <= 0:
			diagnostics.add_error(
				"Google Play Games achievement '%s' total steps must be greater than zero"
				% logical_id
			)


func _validate_server_credentials(diagnostics: GameServicesConfigDiagnostics) -> void:
	var client_id := google_server_client_id
	if typeof(client_id) != TYPE_STRING:
		diagnostics.add_error("Google Play Games server client ID must be a string")
		return
	if client_id.is_empty():
		diagnostics.add_warning(
			"Google Play Games server credentials are not configured; "
			+ "request_server_credentials() will return NOT_CONFIGURED"
		)
		return
	if client_id != client_id.strip_edges() or _contains_whitespace(client_id):
		diagnostics.add_error(
			"Google Play Games server client ID must not contain whitespace"
		)


func _validate_store_review(diagnostics: GameServicesConfigDiagnostics) -> void:
	_validate_store_url(
		diagnostics,
		"Apple Store Review URL",
		apple_store_review_url
	)
	_validate_store_url(
		diagnostics,
		"Google Play Store Review URL",
		google_play_store_review_url
	)
	_validate_store_url(
		diagnostics,
		"Mock Store Review URL",
		mock_store_review_url
	)

	if not apple_app_store_id.is_empty() and not _digits_only(apple_app_store_id):
		diagnostics.add_error(
			"Apple App Store ID must contain digits only when configured"
		)
	if not google_play_package_name.is_empty():
		var package_name := google_play_package_name.strip_edges()
		if package_name != google_play_package_name or not _valid_package_name(package_name):
			diagnostics.add_error(
				"Google Play package name must be a dot-separated Android identifier"
			)
	if apple_store_review_url.is_empty() and apple_app_store_id.is_empty():
		diagnostics.add_warning(
			"Apple Store Review has no URL or App Store ID; explicit store-page "
			+ "handoff will return NOT_CONFIGURED"
		)
	if google_play_store_review_url.is_empty() and google_play_package_name.is_empty():
		diagnostics.add_warning(
			"Google Play Store Review has no URL or package name; explicit store-page "
			+ "handoff will return NOT_CONFIGURED"
		)
	if mock_store_review_url.is_empty():
		diagnostics.add_warning(
			"Mock Store Review has no URL; explicit store-page handoff will return NOT_CONFIGURED"
		)
	if mock_player_id.is_empty() or mock_player_id != mock_player_id.strip_edges() or _contains_whitespace(mock_player_id):
		diagnostics.add_error(
			"Mock provider player ID must contain a non-empty value without whitespace"
		)


func _validate_store_url(
	diagnostics: GameServicesConfigDiagnostics,
	label: String,
	value: String
) -> void:
	if value.is_empty():
		return
	var trimmed := value.strip_edges()
	var scheme_separator := trimmed.find("://")
	var destination := trimmed.substr(scheme_separator + 3) if scheme_separator >= 0 else ""
	if (
		trimmed != value
		or _contains_whitespace(trimmed)
		or destination.is_empty()
		or destination.begins_with("/")
		or not (
		trimmed.begins_with("https://")
		or trimmed.begins_with("http://")
		or trimmed.begins_with("itms-apps://")
		)
	):
		diagnostics.add_error(
			"%s must be an absolute http(s) or itms-apps URL" % label
		)


func _validate_optional_warnings(
	diagnostics: GameServicesConfigDiagnostics,
	provider_name: StringName
) -> void:
	if (
		(provider_name.is_empty() or provider_name == PROVIDER_APPLE)
		and apple_achievement_ids.is_empty()
		and apple_leaderboard_ids.is_empty()
	):
		diagnostics.add_warning(
			"Apple Game Center has no achievement or leaderboard mappings; "
			+ "those optional features will return NOT_CONFIGURED"
		)
	if (
		(provider_name.is_empty() or provider_name == PROVIDER_GOOGLE)
		and google_achievement_ids.is_empty()
		and google_leaderboard_ids.is_empty()
	):
		diagnostics.add_warning(
			"Google Play Games has no achievement or leaderboard mappings; "
			+ "those optional features will return NOT_CONFIGURED"
		)


func _logical_id_value(value: Variant) -> String:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return ""
	var logical_id := str(value)
	if logical_id.is_empty() or logical_id != logical_id.strip_edges():
		return ""
	for character in logical_id:
		if LOGICAL_ID_CHARACTERS.find(character) < 0:
			return ""
	return logical_id


func _valid_package_name(value: String) -> bool:
	if value.is_empty() or value.begins_with(".") or value.ends_with("."):
		return false
	for part in value.split("."):
		if part.is_empty() or not _valid_package_character(part[0], true):
			return false
		for character in part:
			if not _valid_package_character(character, false):
				return false
	return true


func _valid_package_character(character: String, first: bool) -> bool:
	var letters := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	if letters.find(character) >= 0 or character == "_":
		return true
	return not first and "0123456789".find(character) >= 0


func _contains_whitespace(value: String) -> bool:
	for character in value:
		if character == " " or character == "\t" or character == "\n" or character == "\r":
			return true
	return false


func _mapped_id(
	logical_id: StringName,
	provider_name: StringName,
	apple_ids: Dictionary,
	google_ids: Dictionary
) -> String:
	var key := String(logical_id)
	match provider_name:
		&"apple_game_center":
			return str(_mapping_value(apple_ids, key))
		&"google_play_games":
			return str(_mapping_value(google_ids, key))
		PROVIDER_MOCK:
			# The mock provider uses logical IDs as its native IDs, but still
			# requires the logical feature to be declared in one platform map.
			# This keeps missing optional features observable in headless tests.
			return key if _mapping_has_id(apple_ids, key) or _mapping_has_id(google_ids, key) else ""
		_:
			return ""


func _logical_id(
	platform_id: String,
	provider_name: StringName,
	apple_ids: Dictionary,
	google_ids: Dictionary
) -> String:
	var ids: Dictionary
	match provider_name:
		&"apple_game_center":
			ids = apple_ids
		&"google_play_games":
			ids = google_ids
		PROVIDER_MOCK:
			return platform_id
		_:
			return ""

	for logical_id: Variant in ids:
		if str(ids[logical_id]) == platform_id:
			return str(logical_id)
	return ""


func _mapping_has_id(mapping: Dictionary, logical_id: String) -> bool:
	if mapping.has(logical_id):
		return true
	for key: Variant in mapping:
		if str(key) == logical_id:
			return true
	return false


func _mapping_value(mapping: Dictionary, logical_id: String) -> Variant:
	if mapping.has(logical_id):
		return mapping[logical_id]
	for key: Variant in mapping:
		if str(key) == logical_id:
			return mapping[key]
	return ""


func _digits_only(value: String) -> bool:
	if value.is_empty():
		return false
	for character in value:
		if "0123456789".find(character) < 0:
			return false
	return true
