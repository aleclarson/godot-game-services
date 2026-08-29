extends Control

var _output: RichTextLabel


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Godot Game Services"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)

	var provider := Label.new()
	provider.text = "Provider: %s · capabilities: %d" % [
		GameServices.provider_name(),
		GameServices.capabilities(),
	]
	column.add_child(provider)

	var actions := HFlowContainer.new()
	column.add_child(actions)
	_add_action(actions, "Authenticate", _authenticate)
	_add_action(actions, "Unlock first_win", _unlock)
	_add_action(actions, "Submit score", _submit_score)
	_add_action(actions, "Save + load", _save_and_load)

	_output = RichTextLabel.new()
	_output.fit_content = true
	_output.custom_minimum_size = Vector2(0, 220)
	_output.text = "The desktop example uses the stateful mock provider."
	column.add_child(_output)


func _add_action(parent: Control, label: String, action: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	parent.add_child(button)


func _authenticate() -> void:
	_show_result(await GameServices.authenticate().wait())


func _unlock() -> void:
	_show_result(await GameServices.unlock_achievement(&"first_win").wait())


func _submit_score() -> void:
	_show_result(await GameServices.submit_score(&"high_score", 42_000).wait())


func _save_and_load() -> void:
	var save := await GameServices.save_game(
		"example-slot",
		"Hello from Godot Game Services".to_utf8_buffer(),
		{"description": "Example save"}
	).wait()
	if not save.ok:
		_show_result(save)
		return
	_show_result(await GameServices.load_game("example-slot").wait())


func _show_result(result: GameServicesResult) -> void:
	_output.text = JSON.stringify(result.to_dictionary(), "  ")
