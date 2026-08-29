@tool
extends EditorPlugin


func _enter_tree() -> void:
	call_deferred("_wait_for_filesystem_scan")


func _wait_for_filesystem_scan() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem.is_scanning():
		filesystem.filesystem_changed.connect(_wait_for_filesystem_scan, CONNECT_ONE_SHOT)
		return
	_enable_game_services()


func _enable_game_services() -> void:
	if not EditorInterface.is_plugin_enabled("game_services"):
		EditorInterface.set_plugin_enabled("game_services", true)
	if not ProjectSettings.has_setting("autoload/GameServices"):
		push_error("Enabling game_services did not register its autoload")
		get_tree().quit(1)
		return
	var save_error := ProjectSettings.save()
	if save_error != OK:
		push_error("Could not persist the clean-install project settings")
		get_tree().quit(1)
		return
	get_tree().create_timer(0.25).timeout.connect(_quit_editor)


func _quit_editor() -> void:
	get_tree().quit()
