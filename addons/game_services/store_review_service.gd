class_name StoreReviewService
extends RefCounted

## Platform review bridge kept independent from game-service authentication.

const NATIVE_PLUGIN_NAME := &"StoreReview"
const IOS_PLATFORM := &"ios"
const ANDROID_PLATFORM := &"android"
const MOCK_PLATFORM := &"mock"

var config: GameServicesConfig
var platform_override: StringName = &""
var native_plugin_override: Object
var url_opener: Callable
var calls: Array[Dictionary] = []
var opened_urls: PackedStringArray = []
var initialization_result: GameServicesResult

var _platform: StringName = &"unavailable"
var _native_plugin: Object
var _pending_review_requests: Array[GameServicesRequest] = []
var _connected_signal: StringName = &""
var _initialized: bool = false
var _mock_mode: bool = false


func initialize(p_config: GameServicesConfig) -> GameServicesResult:
	shutdown()
	config = p_config if p_config != null else GameServicesConfig.new()
	_platform = _normalize_platform(
		platform_override if not platform_override.is_empty() else StringName(OS.get_name())
	)
	_native_plugin = _resolve_native_plugin()
	_mock_mode = _platform == MOCK_PLATFORM and config.use_mock_in_editor
	_initialized = true

	if _mock_mode:
		initialization_result = GameServicesResult.success(
			&"initialize",
			{"platform": String(_platform), "mock": true},
			provider_name()
		)
		return initialization_result
	if _platform != IOS_PLATFORM and _platform != ANDROID_PLATFORM:
		initialization_result = GameServicesResult.failure(
			&"initialize",
			GameServicesResult.Code.UNSUPPORTED,
			"Store review is only supported on iOS and Android",
			provider_name()
		)
		return initialization_result
	if not is_instance_valid(_native_plugin):
		initialization_result = GameServicesResult.failure(
			&"initialize",
			GameServicesResult.Code.UNAVAILABLE,
			"The StoreReview native singleton is not installed",
			provider_name()
		)
		return initialization_result
	initialization_result = GameServicesResult.success(
		&"initialize",
		{"platform": String(_platform), "native": true},
		provider_name()
	)
	return initialization_result


func shutdown() -> void:
	_disconnect_review_signal()
	var owner := provider_name()
	for value: Variant in _pending_review_requests:
		var request := value as GameServicesRequest
		if request == null or request.is_completed:
			continue
		request.complete(GameServicesResult.failure(
			request.operation,
			GameServicesResult.Code.CANCELLED,
			"Store review shut down before the handoff completed",
			owner
		))
	_pending_review_requests.clear()
	_native_plugin = null
	_platform = &"unavailable"
	_initialized = false
	_mock_mode = false


func platform() -> StringName:
	return _platform


func provider_name() -> StringName:
	match _platform:
		IOS_PLATFORM:
			return &"apple_store_review"
		ANDROID_PLATFORM:
			return &"google_play_store_review"
		MOCK_PLATFORM:
			return &"mock"
	return &"store_review"


func supports_native_review() -> bool:
	return _initialized and (
		_mock_mode
		or (
			is_instance_valid(_native_plugin)
			and not _native_method(&"request_in_app_review").is_empty()
		)
	)


func request_in_app_review() -> GameServicesRequest:
	var request := GameServicesRequest.new(&"request_in_app_review")
	if not _initialized:
		return _complete_failure(
			request,
			GameServicesResult.Code.UNAVAILABLE,
			"Store review has not been initialized"
		)
	if _mock_mode:
		calls.append({"method": "request_in_app_review", "arguments": []})
		_complete_later(request, _success(request.operation, {
			"handoff": "mock_review_request",
			"mock": true,
		}))
		return request
	if _platform != IOS_PLATFORM and _platform != ANDROID_PLATFORM:
		return _complete_failure(
			request,
			GameServicesResult.Code.UNSUPPORTED,
			"Store review is only supported on iOS and Android"
		)
	if not is_instance_valid(_native_plugin):
		return _complete_failure(
			request,
			GameServicesResult.Code.UNAVAILABLE,
			"The StoreReview native singleton is not installed"
		)
	var request_method := _native_method(&"request_in_app_review")
	if request_method.is_empty():
		return _complete_failure(
			request,
			GameServicesResult.Code.UNSUPPORTED,
			"The installed StoreReview bridge does not support in-app review"
		)

	calls.append({"method": "request_in_app_review", "arguments": []})
	var signal_name := _review_completion_signal() if _platform == ANDROID_PLATFORM else &""
	if not signal_name.is_empty():
		_prune_completed_requests()
		_pending_review_requests.append(request)
		_connect_review_signal(signal_name)
	var native_error := _native_error_code(_native_plugin.call(request_method))
	if native_error != OK:
		if not signal_name.is_empty():
			_remove_pending_request(request)
		return _complete_failure(
			request,
			GameServicesResult.Code.PLATFORM_ERROR,
			"The native StoreReview bridge rejected the review request",
			native_error
		)
	if signal_name.is_empty():
		_complete_later(request, _success(request.operation, {
			"handoff": "native_review_request",
			"platform": String(_platform),
			"native": true,
		}))
	return request


func open_store_review_page() -> GameServicesRequest:
	var request := GameServicesRequest.new(&"open_store_review_page")
	if not _initialized:
		return _complete_failure(
			request,
			GameServicesResult.Code.UNAVAILABLE,
			"Store review has not been initialized"
		)
	var review_url := config.store_review_url(_platform)
	if review_url.is_empty():
		return _complete_failure(
			request,
			GameServicesResult.Code.NOT_CONFIGURED,
			"A store review URL or platform store identifier is required"
		)

	calls.append({"method": "open_store_review_page", "arguments": [review_url]})
	var open_page_method := _native_method(&"open_store_review_page")
	if not open_page_method.is_empty():
		var native_error := _native_error_code(
			_native_plugin.call(open_page_method, review_url)
		)
		if native_error == OK:
			_complete_later(request, _success(request.operation, {
				"handoff": "native_store_page",
				"url": review_url,
				"platform": String(_platform),
				"native": true,
			}))
			return request

	if _open_fallback_url(review_url):
		_complete_later(request, _success(request.operation, {
			"handoff": "store_page",
			"url": review_url,
			"platform": String(_platform),
			"native": false,
		}))
	else:
		_complete_failure(
			request,
			GameServicesResult.Code.PLATFORM_ERROR,
			"The configured store review page could not be opened"
		)
	return request


func _resolve_native_plugin() -> Object:
	if is_instance_valid(native_plugin_override):
		return native_plugin_override
	if not Engine.has_singleton(NATIVE_PLUGIN_NAME):
		return null
	return Engine.get_singleton(NATIVE_PLUGIN_NAME)


func _native_method(operation: StringName) -> StringName:
	if not is_instance_valid(_native_plugin):
		return &""
	var candidates: Array[StringName] = [operation]
	if _platform == ANDROID_PLATFORM:
		match operation:
			&"request_in_app_review":
				candidates.push_front(&"requestInAppReview")
			&"open_store_review_page":
				candidates.push_front(&"openStoreReviewPage")
	for candidate: StringName in candidates:
		if _native_plugin.has_method(candidate):
			return candidate
	return &""


func _normalize_platform(value: StringName) -> StringName:
	match String(value).to_lower():
		"ios", "iphone", "ipad":
			return IOS_PLATFORM
		"android":
			return ANDROID_PLATFORM
		"", "linux", "macos", "windows", "freebsd", "web":
			return MOCK_PLATFORM
	return StringName(value)


func _review_completion_signal() -> StringName:
	if not is_instance_valid(_native_plugin):
		return &""
	for signal_name in [&"reviewFlowCompleted", &"review_flow_completed"]:
		if _native_plugin.has_signal(signal_name):
			return signal_name
	return &""


func _connect_review_signal(signal_name: StringName) -> void:
	var callable := Callable(self, "_on_review_flow_completed")
	if _connected_signal == signal_name:
		return
	_disconnect_review_signal()
	if not _native_plugin.is_connected(signal_name, callable):
		_native_plugin.connect(signal_name, callable)
	_connected_signal = signal_name


func _disconnect_review_signal() -> void:
	if _connected_signal.is_empty() or not is_instance_valid(_native_plugin):
		_connected_signal = &""
		return
	var callable := Callable(self, "_on_review_flow_completed")
	if _native_plugin.is_connected(_connected_signal, callable):
		_native_plugin.disconnect(_connected_signal, callable)
	_connected_signal = &""


func _on_review_flow_completed(
	succeeded: bool,
	native_code: int = 0,
	message: String = ""
) -> void:
	while not _pending_review_requests.is_empty():
		var request := _pending_review_requests.pop_front()
		if request.is_completed:
			continue
		if _pending_review_requests.is_empty():
			_disconnect_review_signal()
		if succeeded:
			request.complete(_success(request.operation, {
				"handoff": "native_review_flow",
				"platform": String(_platform),
				"native": true,
			}))
			return
		request.complete(GameServicesResult.failure(
			request.operation,
			GameServicesResult.Code.PLATFORM_ERROR,
			message if not message.is_empty() else "The native StoreReview flow failed",
			provider_name(),
			native_code,
			{"handoff": "native_review_flow", "platform": String(_platform)}
		))
		return
	_disconnect_review_signal()


func _prune_completed_requests() -> void:
	for index in range(_pending_review_requests.size() - 1, -1, -1):
		if _pending_review_requests[index].is_completed:
			_pending_review_requests.remove_at(index)
	if _pending_review_requests.is_empty():
		_disconnect_review_signal()


func _remove_pending_request(request: GameServicesRequest) -> void:
	for index in range(_pending_review_requests.size() - 1, -1, -1):
		if _pending_review_requests[index] == request:
			_pending_review_requests.remove_at(index)
	if _pending_review_requests.is_empty():
		_disconnect_review_signal()


func _open_fallback_url(review_url: String) -> bool:
	var launch_result: Variant
	if url_opener.is_valid():
		launch_result = url_opener.call(review_url)
	else:
		if _mock_mode:
			opened_urls.append(review_url)
			return true
		launch_result = OS.shell_open(review_url)
	if launch_result is bool:
		if bool(launch_result):
			opened_urls.append(review_url)
		return bool(launch_result)
	var opened := _native_error_code(launch_result) == OK
	if opened:
		opened_urls.append(review_url)
	return opened


func _native_error_code(value: Variant) -> int:
	if value == null:
		return OK
	if value is bool:
		return 0 if bool(value) else FAILED
	if value is int or value is float:
		return int(value)
	return OK


func _success(operation: StringName, data: Dictionary) -> GameServicesResult:
	return GameServicesResult.success(operation, data, provider_name())


func _complete_failure(
	request: GameServicesRequest,
	code: GameServicesResult.Code,
	message: String,
	platform_code: Variant = null
) -> GameServicesRequest:
	request.complete(GameServicesResult.failure(
		request.operation,
		code,
		message,
		provider_name(),
		platform_code
	))
	return request


func _complete_later(request: GameServicesRequest, result: GameServicesResult) -> void:
	call_deferred("_finish_request", request, result)


func _finish_request(request: GameServicesRequest, result: GameServicesResult) -> void:
	request.complete(result)
