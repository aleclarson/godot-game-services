class_name GameServicesRequest
extends RefCounted

## A single asynchronous operation. Use [method wait] instead of awaiting the
## signal directly so immediate validation failures cannot be missed.

signal completed(result: GameServicesResult)

static var _next_id: int = 1

var id: int
var operation: StringName
## Provider is filled from the completion result when the transport exposes it.
## Facades may set it earlier so cancellation and timeout helpers can retain the
## owner even when a request has not completed yet.
var provider: StringName = &""
var parent_id: int = 0
var origin_id: int = 0
var is_completed: bool = false
var result: GameServicesResult

var _timeout_timer: SceneTreeTimer
var _retry_timer: SceneTreeTimer
var _retry_factory: Callable
var _retry_policy: GameServicesRetryPolicy
var _retry_attempt: int = 0
var _retry_child: GameServicesRequest
var _helper_cancelled: bool = false


func _init(p_operation: StringName = &"") -> void:
	id = _next_id
	_next_id += 1
	operation = p_operation
	origin_id = id


var request_id: int:
	get:
		return origin_id if origin_id > 0 else id


func complete(p_result: GameServicesResult) -> void:
	if is_completed:
		return
	is_completed = true
	result = p_result
	if p_result != null:
		p_result.request_id = origin_id if origin_id > 0 else id
	if p_result != null and not p_result.provider.is_empty():
		provider = p_result.provider
	completed.emit(result)


func wait() -> GameServicesResult:
	if is_completed:
		return result
	return await completed


func is_pending() -> bool:
	return not is_completed


## Complete this request locally as cancelled. Native transports do not expose
## a common cancellation primitive, so wrappers stop observing the request;
## providers are never retried or re-authenticated as a side effect.
func cancel(
	p_message: String = "Request cancelled",
	p_provider: StringName = &""
) -> bool:
	if is_completed:
		return false
	_helper_cancelled = true
	var owner := p_provider if not p_provider.is_empty() else provider
	complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.CANCELLED,
		p_message,
		owner
	))
	return true


func is_cancelled() -> bool:
	return is_completed and result != null and result.is_cancelled()


## Map a successful result's typed value while preserving its operation,
## provider, error metadata, request identity, and raw diagnostics.
func map(transform: Callable) -> GameServicesRequest:
	var target := GameServicesRequest.new(operation)
	target.parent_id = id
	target.origin_id = origin_id
	target.provider = provider
	if not transform.is_valid():
		target.complete(_helper_failure(
			"A value-mapping callable is required",
			GameServicesResult.Code.INVALID_ARGUMENT
		))
		return target
	if is_completed:
		target._finish_map(result, transform)
	else:
		completed.connect(
			Callable(target, "_finish_map").bind(transform),
			CONNECT_ONE_SHOT
		)
	return target


func map_value(transform: Callable) -> GameServicesRequest:
	return map(transform)


## Chain a dependent request after this request succeeds. The callable receives
## the complete GameServicesResult and must return another request or result.
func then(next: Callable) -> GameServicesRequest:
	var target := GameServicesRequest.new(operation)
	target.parent_id = id
	target.origin_id = origin_id
	target.provider = provider
	if not next.is_valid():
		target.complete(_helper_failure(
			"A dependent-request callable is required",
			GameServicesResult.Code.INVALID_ARGUMENT
		))
		return target
	if is_completed:
		target._finish_chain(result, next)
	else:
		completed.connect(
			Callable(target, "_finish_chain").bind(next),
			CONNECT_ONE_SHOT
		)
	return target


func chain(next: Callable) -> GameServicesRequest:
	return then(next)


func flat_map(next: Callable) -> GameServicesRequest:
	return then(next)


func and_then(next: Callable) -> GameServicesRequest:
	return then(next)


## Variant of [method then] for callers that only need the successful typed
## value. A failure is still forwarded unchanged.
func then_value(next: Callable) -> GameServicesRequest:
	var target := GameServicesRequest.new(operation)
	target.parent_id = id
	target.origin_id = origin_id
	target.provider = provider
	if not next.is_valid():
		target.complete(_helper_failure(
			"A dependent-request callable is required",
			GameServicesResult.Code.INVALID_ARGUMENT
		))
		return target
	var callback := func(source_result: GameServicesResult):
		if not source_result.is_success():
			return source_result
		return next.call(source_result.data)
	if is_completed:
		target._finish_chain(result, callback)
	else:
		completed.connect(
			Callable(target, "_finish_chain").bind(callback),
			CONNECT_ONE_SHOT
		)
	return target


## Bound this request to a local timeout. The underlying provider operation is
## intentionally left alone; only the returned wrapper is completed. Use
## [method cancel] when the caller wants cancellation instead of a timeout.
func with_timeout(seconds: float) -> GameServicesRequest:
	var target := GameServicesRequest.new(operation)
	target.parent_id = id
	target.origin_id = origin_id
	target.provider = provider
	if is_completed:
		target.complete(result)
		return target
	completed.connect(
		Callable(target, "_finish_timeout_source"),
		CONNECT_ONE_SHOT
	)
	var duration := maxf(seconds, 0.0)
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		target._timeout_timer = (main_loop as SceneTree).create_timer(duration)
		target._timeout_timer.timeout.connect(
			Callable(target, "_on_timeout").bind(duration),
			CONNECT_ONE_SHOT
		)
	return target


func timeout(seconds: float) -> GameServicesRequest:
	return with_timeout(seconds)


func with_bounded_timeout(seconds: float) -> GameServicesRequest:
	return with_timeout(seconds)


func limit_time(seconds: float) -> GameServicesRequest:
	return with_timeout(seconds)


## Retry this request only after a failure and only by invoking the explicit
## operation factory. The first request is not replayed automatically. This
## preserves mutation safety and makes authentication/retry decisions visible
## at the call site.
func retry(
	operation_factory: Callable = Callable(),
	policy: Variant = null
) -> GameServicesRequest:
	return with_retry(operation_factory, policy)


func with_retry(
	operation_factory: Callable,
	policy: Variant = null
) -> GameServicesRequest:
	var target := GameServicesRequest.new(operation)
	target.parent_id = id
	target.origin_id = origin_id
	target.provider = provider
	target._retry_factory = operation_factory
	target._retry_policy = _coerce_retry_policy(policy)
	if not operation_factory.is_valid():
		target.complete(_helper_failure(
			"An explicit retry operation factory is required",
			GameServicesResult.Code.INVALID_ARGUMENT
		))
		return target
	if is_completed:
		target._finish_retry_source(result)
	else:
		completed.connect(
			Callable(target, "_finish_retry_source"),
			CONNECT_ONE_SHOT
		)
	return target


func retry_with(
	operation_factory: Callable,
	policy: Variant = null
) -> GameServicesRequest:
	return with_retry(operation_factory, policy)


## Start a retryable operation without first creating an unwrapped request.
## This is still opt-in and requires an operation factory.
static func run_with_retry(
	operation_factory: Callable,
	policy: Variant = null,
	p_operation: StringName = &""
) -> GameServicesRequest:
	var target := GameServicesRequest.new(p_operation)
	target._retry_factory = operation_factory
	target._retry_policy = _coerce_retry_policy(policy)
	if not operation_factory.is_valid():
		target.complete(GameServicesResult.failure(
			p_operation,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"An explicit retry operation factory is required"
		))
		return target
	target._retry_attempt = 1
	target._start_retry_attempt()
	return target


static func retry_factory(
	operation_factory: Callable,
	policy: Variant = null,
	p_operation: StringName = &""
) -> GameServicesRequest:
	return run_with_retry(operation_factory, policy, p_operation)


func _finish_map(source_result: GameServicesResult, transform: Callable) -> void:
	if is_completed:
		return
	if not source_result.is_success():
		complete(source_result)
		return
	var mapped := transform.call(source_result.data)
	if mapped is GameServicesResult:
		complete(mapped)
	else:
		complete(source_result.with_data(mapped))


func _finish_chain(source_result: GameServicesResult, next: Callable) -> void:
	if is_completed:
		return
	if not source_result.is_success():
		complete(source_result)
		return
	var next_value := next.call(source_result)
	if next_value is GameServicesRequest:
		var child: GameServicesRequest = next_value
		operation = child.operation if not child.operation.is_empty() else operation
		provider = child.provider
		if child.is_completed:
			complete(child.result)
		else:
			child.completed.connect(
				Callable(self, "_finish_child_request"),
				CONNECT_ONE_SHOT
			)
	elif next_value is GameServicesResult:
		complete(next_value)
	else:
		complete(_helper_failure(
			"A dependent callable must return a GameServicesRequest or GameServicesResult",
			GameServicesResult.Code.INVALID_DATA,
			source_result.provider
		))


func _finish_child_request(child_result: GameServicesResult) -> void:
	if not is_completed:
		complete(child_result)


func _finish_timeout_source(source_result: GameServicesResult) -> void:
	if not is_completed:
		complete(source_result)


func _on_timeout(duration: float) -> void:
	if is_completed:
		return
	complete(GameServicesResult.failure(
		operation,
		GameServicesResult.Code.PLATFORM_ERROR,
		"%s timed out after %.3f seconds" % [operation, duration],
		provider,
		null,
		{"timeout_seconds": duration}
	))


func _finish_retry_source(source_result: GameServicesResult) -> void:
	if is_completed:
		return
	if operation.is_empty():
		operation = source_result.operation
	if not source_result.provider.is_empty():
		provider = source_result.provider
	_retry_attempt = 1
	_handle_retry_result(source_result)


func _handle_retry_result(source_result: GameServicesResult) -> void:
	if is_completed:
		return
	if source_result.is_success() or not _retry_policy.should_retry(source_result, _retry_attempt):
		complete(source_result)
		return
	var retry_number := _retry_attempt
	_retry_attempt += 1
	var delay := _retry_policy.delay_for_retry(retry_number)
	if delay <= 0.0:
		_start_retry_attempt()
		return
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		_start_retry_attempt()
		return
	_retry_timer = (main_loop as SceneTree).create_timer(delay)
	_retry_timer.timeout.connect(
		Callable(self, "_on_retry_delay_elapsed"),
		CONNECT_ONE_SHOT
	)


func _on_retry_delay_elapsed() -> void:
	if not is_completed:
		_start_retry_attempt()


func _start_retry_attempt() -> void:
	if is_completed:
		return
	var value := _retry_factory.call()
	if not value is GameServicesRequest:
		complete(_helper_failure(
			"The retry operation factory must return a GameServicesRequest",
			GameServicesResult.Code.INVALID_DATA,
			provider
		))
		return
	var child: GameServicesRequest = value
	_retry_child = child
	if operation.is_empty():
		operation = child.operation
	if not child.provider.is_empty():
		provider = child.provider
	if child.is_completed:
		_handle_retry_result(child.result)
	else:
		child.completed.connect(
			Callable(self, "_handle_retry_result"),
			CONNECT_ONE_SHOT
		)


static func _coerce_retry_policy(value: Variant) -> GameServicesRetryPolicy:
	if value is GameServicesRetryPolicy:
		return value.copy_policy()
	if value is Dictionary:
		return GameServicesRetryPolicy.from_dictionary(value)
	return GameServicesRetryPolicy.new()


func _helper_failure(
	message: String,
	code: GameServicesResult.Code = GameServicesResult.Code.INTERNAL_ERROR,
	p_provider: StringName = &""
) -> GameServicesResult:
	return GameServicesResult.failure(
		operation,
		code,
		message,
		p_provider if not p_provider.is_empty() else provider
	)
