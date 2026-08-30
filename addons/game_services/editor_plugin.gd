@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GameServices"
const AUTOLOAD_PATH := "res://addons/game_services/game_services.gd"

var _android_export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	_android_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_android_export_plugin)


func _exit_tree() -> void:
	if is_instance_valid(_android_export_plugin):
		remove_export_plugin(_android_export_plugin)
	_android_export_plugin = null


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


class AndroidExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME := &"GodotPlayGameServices"
	const STORE_REVIEW_PLUGIN_NAME := &"StoreReview"
	const OPTION_NAME := &"game_services/google_game_id"
	const VALUES_DIRECTORY := "res://android/build/res/values"
	const DIGITS := "0123456789"


	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid


	func _get_name() -> String:
		return String(PLUGIN_NAME)


	func _get_android_libraries(
		platform: EditorExportPlatform,
		debug: bool
	) -> PackedStringArray:
		if not _supports_platform(platform):
			return PackedStringArray()
		var variant := "debug" if debug else "release"
		return PackedStringArray([
			"game_services/bin/android/%s/%s-%s.aar" % [variant, PLUGIN_NAME, variant],
			"game_services/bin/android/%s/%s-%s.aar" % [variant, STORE_REVIEW_PLUGIN_NAME, variant],
		])


	func _get_android_dependencies(
		platform: EditorExportPlatform,
		_debug: bool
	) -> PackedStringArray:
		if not _supports_platform(platform):
			return PackedStringArray()
		return PackedStringArray([
			"com.google.code.gson:gson:2.11.0",
			"com.google.android.gms:play-services-games-v2:22.0.0",
			"com.google.android.play:review:2.0.2",
		])


	func _get_android_manifest_application_element_contents(
		platform: EditorExportPlatform,
		_debug: bool
	) -> String:
		if not _supports_platform(platform):
			return ""
		return (
			"<meta-data android:name=\"com.google.android.gms.games.APP_ID\" "
			+ "android:value=\"@string/game_services_project_id\"/>"
		)


	func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
		if not _supports_platform(platform):
			return []
		return [{
			"option": {
				"name": OPTION_NAME,
				"type": TYPE_STRING,
				"hint_string": "Google Play Games Services game ID",
			},
			"default_value": "",
		}]


	func _get_export_option_warning(
		platform: EditorExportPlatform,
		option: String
	) -> String:
		if _supports_platform(platform) and option == OPTION_NAME and not _valid_game_id(_game_id()):
			return "Enter the numeric Google Play Games Services project ID."
		return ""


	func _export_begin(
		features: PackedStringArray,
		_is_debug: bool,
		_path: String,
		_flags: int
	) -> void:
		if not features.has("android"):
			return
		var game_id := _game_id()
		if not _valid_game_id(game_id):
			push_error("[Game Services] Android export requires a numeric Google game ID.")
			return

		var values_path := ProjectSettings.globalize_path(VALUES_DIRECTORY)
		var directory_error := DirAccess.make_dir_recursive_absolute(values_path)
		if directory_error != OK:
			push_error("[Game Services] Could not create %s (error %d)." % [values_path, directory_error])
			return

		var resource_path := values_path.path_join("game_services.xml")
		var file := FileAccess.open(resource_path, FileAccess.WRITE)
		if file == null:
			push_error("[Game Services] Could not write %s (error %d)." % [
				resource_path,
				FileAccess.get_open_error(),
			])
			return
		var resource_xml := (
			"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
			+ "<resources>\n"
			+ "    <string translatable=\"false\" name=\"game_services_project_id\">%s</string>\n"
			+ "</resources>\n"
		) % game_id.xml_escape()
		file.store_string(resource_xml)


	func _game_id() -> String:
		return str(get_option(OPTION_NAME)).strip_edges()


	func _valid_game_id(game_id: String) -> bool:
		if game_id.is_empty():
			return false
		for character in game_id:
			if DIGITS.find(character) < 0:
				return false
		return true
