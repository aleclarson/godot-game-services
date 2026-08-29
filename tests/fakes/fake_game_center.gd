extends Node

var calls: Array[Dictionary] = []
var pending_events: Array[Dictionary] = []
var authenticated: bool = false


func is_authenticated() -> bool:
	return authenticated


func authenticate() -> int:
	_record("authenticate")
	return OK


func post_score(score: Dictionary) -> int:
	_record("post_score", [score])
	return OK


func award_achievement(achievement: Dictionary) -> int:
	_record("award_achievement", [achievement])
	return OK


func request_achievements() -> void:
	_record("request_achievements")


func show_game_center(options: Dictionary) -> int:
	_record("show_game_center", [options])
	return OK


func request_identity_verification_signature() -> int:
	_record("request_identity_verification_signature")
	return OK


func save_game(save: Dictionary) -> int:
	_record("save_game", [save])
	return OK


func load_game(name: String) -> void:
	_record("load_game", [name])


func list_saved_games() -> void:
	_record("list_saved_games")


func delete_saved_game(name: String) -> void:
	_record("delete_saved_game", [name])


func resolve_saved_game_conflict(resolution: Dictionary) -> int:
	_record("resolve_saved_game_conflict", [resolution])
	return OK


func get_pending_event_count() -> int:
	return pending_events.size()


func pop_pending_event() -> Dictionary:
	return pending_events.pop_front()


func push_event(event: Dictionary) -> void:
	pending_events.append(event)


func _record(method: String, arguments: Array = []) -> void:
	calls.append({"method": method, "arguments": arguments})
