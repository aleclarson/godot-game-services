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
	var example_slot := GameServices.cloud_saves.slot("example-slot")
	var document := example_slot.create(
		{"message": "Hello from Godot Game Services", "visits": 1},
		{"description": "Example save"}
	)
	var save := await example_slot.save(document).wait()
	if not save.ok:
		_show_result(save)
		return
	var loaded := await example_slot.load().wait()
	if not loaded.ok:
		_show_result(loaded)
		return
	var loaded_document: CloudSaveDocument = loaded.data
	_output.text = JSON.stringify({
		"slot": loaded_document.slot,
		"revision": loaded_document.revision,
		"value": loaded_document.value,
	}, "  ")


func _show_result(result: GameServicesResult) -> void:
	_output.text = JSON.stringify(result.to_dictionary(), "  ")
