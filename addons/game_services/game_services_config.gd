class_name GameServicesConfig
extends Resource

## Maps game-owned logical identifiers to the identifiers configured in each
## platform console.

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
	return int(google_achievement_steps.get(String(logical_id), 0))


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
		&"mock":
			return mock_store_review_url.strip_edges()
	return ""


func mock_player() -> Dictionary:
	return {
		"id": mock_player_id,
		"display_name": mock_player_display_name,
		"alias": mock_player_display_name,
		"provider": "mock",
	}


func _mapped_id(
	logical_id: StringName,
	provider_name: StringName,
	apple_ids: Dictionary,
	google_ids: Dictionary
) -> String:
	var key := String(logical_id)
	match provider_name:
		&"apple_game_center":
			return str(apple_ids.get(key, ""))
		&"google_play_games":
			return str(google_ids.get(key, ""))
		&"mock":
			return key
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
		&"mock":
			return platform_id
		_:
			return ""

	for logical_id: Variant in ids:
		if str(ids[logical_id]) == platform_id:
			return str(logical_id)
	return ""


func _digits_only(value: String) -> bool:
	if value.is_empty():
		return false
	for character in value:
		if "0123456789".find(character) < 0:
			return false
	return true
