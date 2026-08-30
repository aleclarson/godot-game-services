class_name GameServicesAchievementCollection
extends RefCounted

## Typed collection returned by load_achievements().

var items: Array[GameServicesAchievement] = []


func _init(values: Array = []) -> void:
	for value: Variant in values:
		append(value)


func append(value: Variant) -> GameServicesAchievement:
	var achievement := (
		value
		if value is GameServicesAchievement
		else GameServicesAchievement.from_dictionary(value)
	) as GameServicesAchievement
	if achievement != null:
		items.append(achievement)
	return achievement


func size() -> int:
	return items.size()


func is_empty() -> bool:
	return items.is_empty()


func get(index: StringName) -> Variant:
	var numeric_index := int(String(index))
	if numeric_index < 0 or numeric_index >= items.size():
		return null
	return items[numeric_index]


func get_at(index: int) -> GameServicesAchievement:
	if index < 0 or index >= items.size():
		return null
	return items[index]


func find_by_id(logical_id: StringName) -> GameServicesAchievement:
	for achievement: GameServicesAchievement in items:
		if achievement.id == String(logical_id) or achievement.platform_id == String(logical_id):
			return achievement
	return null


func to_array() -> Array[GameServicesAchievement]:
	return items.duplicate()


func to_dictionary() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for achievement: GameServicesAchievement in items:
		result.append(achievement.to_dictionary())
	return result


func _get(index: StringName) -> Variant:
	return get_at(int(String(index)))


func _iter_init(state: Variant) -> bool:
	state[0] = 0
	return not items.is_empty()


func _iter_next(state: Variant) -> bool:
	state[0] += 1
	return state[0] < items.size()


func _iter_get(state: Variant) -> Variant:
	return items[state[0]]
