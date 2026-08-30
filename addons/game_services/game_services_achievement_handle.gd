class_name GameServicesAchievementHandle
extends RefCounted

## A scoped facade for one logical achievement identifier.
##
## The handle stores only the game-owned ID. Platform mappings and provider
## capabilities are resolved by GameServices for every call, so a handle stays
## valid when the provider is replaced or shut down.

var logical_id: StringName = &""
var id: StringName:
	get:
		return logical_id

var achievement_id: StringName:
	get:
		return logical_id

var _game_services: Node


func _init(p_game_services: Node, p_logical_id: StringName) -> void:
	_game_services = p_game_services
	logical_id = p_logical_id


var platform_id: String:
	get:
		var service := _service()
		return service.resolve_achievement_id(logical_id) if service != null else ""

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
	return service != null and service.supports(service.Capability.ACHIEVEMENTS)


func supports_progress() -> bool:
	var service := _service()
	return service != null and service.supports(service.Capability.ACHIEVEMENT_PROGRESS)


func supports_load() -> bool:
	return supports()


func unlock() -> GameServicesRequest:
	return _call_service(&"unlock_achievement", &"unlock_achievement")


func unlock_achievement() -> GameServicesRequest:
	return unlock()


func set_progress(progress: float) -> GameServicesRequest:
	return _call_service(
		&"set_achievement_progress",
		&"set_achievement_progress",
		[progress]
	)


func set_achievement_progress(progress: float) -> GameServicesRequest:
	return set_progress(progress)


func progress(progress: float) -> GameServicesRequest:
	return set_progress(progress)


func load(force_reload: bool = false) -> GameServicesRequest:
	return _call_service(&"load_achievement", &"load_achievement", [force_reload])


func load_achievement(force_reload: bool = false) -> GameServicesRequest:
	return _load_scoped(force_reload)


func load_state(force_reload: bool = false) -> GameServicesRequest:
	return _load_scoped(force_reload)


func _load_scoped(force_reload: bool = false) -> GameServicesRequest:
	return _call_service(&"load_achievement", &"load_achievement", [force_reload])


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
