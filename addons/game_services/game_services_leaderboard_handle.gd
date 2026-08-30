class_name GameServicesLeaderboardHandle
extends RefCounted

## A scoped facade for one logical leaderboard identifier.

var logical_id: StringName = &""
var id: StringName:
	get:
		return logical_id

var leaderboard_id: StringName:
	get:
		return logical_id

var _game_services: Node


func _init(p_game_services: Node, p_logical_id: StringName) -> void:
	_game_services = p_game_services
	logical_id = p_logical_id


var platform_id: String:
	get:
		var service := _service()
		return service.resolve_leaderboard_id(logical_id) if service != null else ""

var resolved_id: String:
	get:
		return platform_id


var provider: StringName:
	get:
		var service := _service()
		return service.provider_name() if service != null else &"unavailable"


func is_configured() -> bool:
	return not platform_id.is_empty()


func supports() -> bool:
	var service := _service()
	return service != null and service.supports(service.Capability.LEADERBOARDS)


func supports_show() -> bool:
	var service := _service()
	return service != null and service.supports(service.Capability.PLATFORM_UI)


func submit_score(score: int) -> GameServicesRequest:
	return _call_service(&"submit_score", &"submit_score", [score])


func submit(score: int) -> GameServicesRequest:
	return submit_score(score)


func show() -> GameServicesRequest:
	return _call_service(&"show_leaderboards", &"show_leaderboards")


func show_leaderboard() -> GameServicesRequest:
	return show()


func show_ui() -> GameServicesRequest:
	return show()


func _service() -> GameServices:
	if _game_services == null or not is_instance_valid(_game_services):
		return null
	return _game_services as GameServices


func _call_service(
	method: StringName,
	operation: StringName,
	arguments: Array = []
) -> GameServicesRequest:
	var service := _service()
	if service == null:
		return _unavailable_request(operation)
	var callable := Callable(service, method)
	if not callable.is_valid():
		return _unavailable_request(operation)
	var value := callable.callv([logical_id] + arguments)
	if value is GameServicesRequest:
		return value
	return _unavailable_request(operation)


func _unavailable_request(operation: StringName) -> GameServicesRequest:
	var request := GameServicesRequest.new(operation)
	request.complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.UNAVAILABLE,
		"Game services have not been initialized",
		&"unavailable"
	))
	return request
