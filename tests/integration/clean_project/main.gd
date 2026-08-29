extends Node


func _ready() -> void:
	if not has_node("/root/GameServices"):
		push_error("GameServices autoload was not installed")
		get_tree().quit(1)
		return
	var game_services := get_node("/root/GameServices")
	var result: GameServicesResult = game_services.initialize(
		GameServicesConfig.new(),
		MockGameServicesProvider.new()
	)
	if not result.ok or game_services.provider_name() != &"mock":
		push_error("GameServices mock provider did not initialize")
		get_tree().quit(1)
		return
	print("PASS: clean project loaded GameServices")
	get_tree().quit()
