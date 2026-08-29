class_name GameServicesRequest
extends RefCounted

## A single asynchronous operation. Use [method wait] instead of awaiting the
## signal directly so immediate validation failures cannot be missed.

signal completed(result: GameServicesResult)

static var _next_id: int = 1

var id: int
var operation: StringName
var is_completed: bool = false
var result: GameServicesResult


func _init(p_operation: StringName = &"") -> void:
	id = _next_id
	_next_id += 1
	operation = p_operation


func complete(p_result: GameServicesResult) -> void:
	if is_completed:
		return
	is_completed = true
	result = p_result
	completed.emit(result)


func wait() -> GameServicesResult:
	if is_completed:
		return result
	return await completed
