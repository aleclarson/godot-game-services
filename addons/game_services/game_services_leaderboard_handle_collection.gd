class_name GameServicesLeaderboardHandleCollection
extends RefCounted

## Cached collection of handles bound to logical leaderboard IDs.

var _game_services: Node
var _handles: Dictionary[String, GameServicesLeaderboardHandle] = {}


func _init(p_game_services: Node) -> void:
	_game_services = p_game_services


func get(logical_id: StringName) -> GameServicesLeaderboardHandle:
	return _get_handle(logical_id)


func _get_handle(logical_id: StringName) -> GameServicesLeaderboardHandle:
	var key := String(logical_id)
	if not _handles.has(key):
		_handles[key] = GameServicesLeaderboardHandle.new(_game_services, logical_id)
	return _handles[key]


func handle(logical_id: StringName) -> GameServicesLeaderboardHandle:
	return _get_handle(logical_id)


func leaderboard(logical_id: StringName) -> GameServicesLeaderboardHandle:
	return _get_handle(logical_id)


func for_id(logical_id: StringName) -> GameServicesLeaderboardHandle:
	return _get_handle(logical_id)


func get_or_create(logical_id: StringName) -> GameServicesLeaderboardHandle:
	return _get_handle(logical_id)


func has(logical_id: StringName) -> bool:
	return _handles.has(String(logical_id))


func size() -> int:
	return _handles.size()


func is_empty() -> bool:
	return _handles.is_empty()


func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: Variant in _handles:
		result.append(StringName(str(key)))
	return result


func values() -> Array[GameServicesLeaderboardHandle]:
	var result: Array[GameServicesLeaderboardHandle] = []
	for value: Variant in _handles.values():
		result.append(value)
	return result


func all() -> Array[GameServicesLeaderboardHandle]:
	return values()


func _get(key: StringName) -> Variant:
	return _get_handle(key)


func _iter_init(state: Variant) -> bool:
	state[0] = 0
	return not _handles.is_empty()


func _iter_next(state: Variant) -> bool:
	state[0] += 1
	return state[0] < _handles.size()


func _iter_get(state: Variant) -> Variant:
	return values()[state[0]]
