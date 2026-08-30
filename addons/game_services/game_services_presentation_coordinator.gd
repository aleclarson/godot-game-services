class_name GameServicesPresentationCoordinator
extends RefCounted

## Owns the single native-presentation slot shared by platform UI and review.
##
## Providers still decide how a handoff is performed. This object only makes
## ownership explicit at the public boundary, so an achievement screen cannot
## race a leaderboard screen (or an in-app review/store-page handoff).

signal active_changed(active: bool, operation: StringName)

const BUSY_MESSAGE := "Another presentation request is already active"
const CANCELLED_MESSAGE := "Presentation cancelled before it completed"

var _active_request: GameServicesRequest
var _active_source: GameServicesRequest
var _active_operation: StringName = &""
var _active_provider: StringName = &""


var active_request: GameServicesRequest:
	get:
		return _active_request

var active_operation: StringName:
	get:
		return _active_operation

var active_provider: StringName:
	get:
		return _active_provider

var is_active: bool:
	get:
		return is_instance_valid(_active_request) and not _active_request.is_completed


## Return the stable overlap result without invoking a source. This lets a
## facade reject a request before doing feature-specific validation as well.
func busy_request(
	operation: StringName,
	provider: StringName = &""
) -> GameServicesRequest:
	return _busy_request(operation, provider) if is_active else null


func is_busy() -> bool:
	return is_active


## Start one coordinated handoff. The source factory is invoked only after the
## busy check succeeds. [param transform] is applied to the source result and
## is intentionally optional so callers can retain provider payloads exactly.
func start(
	operation: StringName,
	source_factory: Callable,
	transform: Callable = Callable(),
	provider: StringName = &""
) -> GameServicesRequest:
	if is_active:
		return _busy_request(operation, provider)

	var target := GameServicesRequest.new(operation)
	target.provider = provider
	if not source_factory.is_valid():
		target.complete(GameServicesResult.failure(
			operation,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"A presentation source factory is required",
			provider
		))
		return target

	_active_request = target
	_active_operation = operation
	_active_provider = provider
	target.completed.connect(
		Callable(self, "_on_target_completed").bind(target),
		CONNECT_ONE_SHOT
	)
	active_changed.emit(true, operation)

	var source_value: Variant = source_factory.call()
	if not source_value is GameServicesRequest:
		_finish_target(GameServicesResult.failure(
			operation,
			GameServicesResult.Code.INVALID_DATA,
			"The presentation source did not return a GameServicesRequest",
			provider
		), target)
		return target

	_active_source = source_value
	if target.provider.is_empty():
		target.provider = source_value.provider
	if source_value.is_completed:
		_finish_source(source_value.result, target, transform)
	else:
		source_value.completed.connect(
			Callable(self, "_finish_source").bind(target, transform),
			CONNECT_ONE_SHOT
		)
	return target


## Alias for callers that describe the operation as a presentation request.
func request(
	operation: StringName,
	source_factory: Callable,
	transform: Callable = Callable(),
	provider: StringName = &""
) -> GameServicesRequest:
	return start(operation, source_factory, transform, provider)


func cancel_active(
	message: String = CANCELLED_MESSAGE,
	provider: StringName = &""
) -> bool:
	if not is_active:
		return false
	var target := _active_request
	var owner := provider
	if owner.is_empty():
		owner = _active_provider
	if owner.is_empty() and is_instance_valid(_active_source):
		owner = _active_source.provider
	if is_instance_valid(_active_source) and not _active_source.is_completed:
		# This is local cancellation of the observation wrapper. Native work may
		# still finish later, but it can no longer complete the public request.
		_active_source.cancel(message, owner)
	target.complete(GameServicesResult.failure(
		target.operation,
		GameServicesResult.Code.CANCELLED,
		message,
		owner
	))
	_clear_active(target)
	return true


func cancel(
	message: String = CANCELLED_MESSAGE,
	provider: StringName = &""
) -> bool:
	return cancel_active(message, provider)


func reset(
	message: String = CANCELLED_MESSAGE,
	provider: StringName = &""
) -> bool:
	return cancel_active(message, provider)


func _finish_source(
	result: GameServicesResult,
	target: GameServicesRequest,
	transform: Callable
) -> void:
	if target.is_completed:
		_clear_active(target)
		return
	var final_result := result
	if final_result == null:
		final_result = GameServicesResult.failure(
			target.operation,
			GameServicesResult.Code.INVALID_DATA,
			"The presentation source completed without a result",
			target.provider
		)
	if transform.is_valid():
		var transformed: Variant = transform.call(final_result)
		if transformed is GameServicesResult:
			final_result = transformed
		else:
			final_result = GameServicesResult.failure(
				target.operation,
				GameServicesResult.Code.INVALID_DATA,
				"The presentation result transform did not return a GameServicesResult",
				target.provider
			)
	_finish_target(final_result, target)


func _finish_target(result: GameServicesResult, target: GameServicesRequest) -> void:
	if not target.is_completed:
		target.complete(result)
	_clear_active(target)


func _on_target_completed(_result: GameServicesResult, target: GameServicesRequest) -> void:
	if _active_request != target:
		return
	if is_instance_valid(_active_source) and not _active_source.is_completed:
		_active_source.cancel("Presentation observation cancelled", _active_provider)
	_clear_active(target)


func _clear_active(target: GameServicesRequest) -> void:
	if _active_request != target:
		return
	_active_request = null
	_active_source = null
	var operation := _active_operation
	_active_operation = &""
	_active_provider = &""
	active_changed.emit(false, operation)


func _busy_request(operation: StringName, provider: StringName) -> GameServicesRequest:
	var request := GameServicesRequest.new(operation)
	# The active owner is the useful diagnostic provider for an overlap. The
	# requested provider is only a fallback when the owner was not supplied.
	request.provider = _active_provider if not _active_provider.is_empty() else provider
	request.complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.BUSY,
		BUSY_MESSAGE,
		request.provider,
		null,
		{"active_operation": String(_active_operation)}
	))
	return request
