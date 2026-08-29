class_name CloudSaveSlot
extends RefCounted

## A configured handle for one logical cloud-save slot.

signal request_finished(request: GameServicesRequest, result: GameServicesResult)

var slot: String = ""
var default_value: Variant

var schema_version: int:
	get:
		return _store.schema_version
	set(value):
		_store.schema_version = value

var conflict_policy:
	get:
		return _store.conflict_policy
	set(value):
		_store.conflict_policy = value

var conflict_resolver: Callable:
	get:
		return _store.conflict_resolver
	set(value):
		_store.conflict_resolver = value

var validator: Callable:
	get:
		return _store.validator
	set(value):
		_store.validator = value

var max_conflict_attempts: int:
	get:
		return _store.max_conflict_attempts
	set(value):
		_store.max_conflict_attempts = value

var _store: CloudSaveStore


func _init(
	p_store: CloudSaveStore,
	p_slot: String,
	p_default_value: Variant = null
) -> void:
	_store = p_store
	slot = p_slot
	default_value = p_default_value
	if _store != null:
		_store.request_finished.connect(_on_store_request_finished)


func add_migration(from_version: int, migration: Callable) -> void:
	_store.add_migration(from_version, migration)


func remove_migration(from_version: int) -> void:
	_store.remove_migration(from_version)


func clear_migrations() -> void:
	_store.clear_migrations()


func create(value: Variant = null, metadata: Dictionary = {}) -> CloudSaveDocument:
	return _store.create(slot, value, metadata)


func load() -> GameServicesRequest:
	return _store.load(slot)


func load_or_create(default_override: Variant = null) -> GameServicesRequest:
	var value := default_value if default_override == null else default_override
	return _store.load_or_create(slot, value)


func update(mutator: Callable, metadata: Dictionary = {}) -> GameServicesRequest:
	return _store.update(slot, default_value, mutator, metadata)


func exists() -> GameServicesRequest:
	return _store.exists(slot)


func save(document: CloudSaveDocument) -> GameServicesRequest:
	var document_error := _document_slot_error(document)
	if not document_error.is_empty():
		return _store._local_failure_request(
			CloudSaveStore.OP_SAVE,
			GameServicesResult.Code.INVALID_ARGUMENT,
			document_error
		)
	return _store.save(document)


func delete() -> GameServicesRequest:
	return _store.delete(slot)


func validate(document: CloudSaveDocument) -> GameServicesResult:
	var document_error := _document_slot_error(document)
	if not document_error.is_empty():
		return GameServicesResult.failure(
			CloudSaveStore.OP_VALIDATE,
			GameServicesResult.Code.INVALID_ARGUMENT,
			document_error
		)
	return _store.validate(document)


func encoded_size(document: CloudSaveDocument) -> GameServicesResult:
	var document_error := _document_slot_error(document)
	if not document_error.is_empty():
		return GameServicesResult.failure(
			CloudSaveStore.OP_ENCODED_SIZE,
			GameServicesResult.Code.INVALID_ARGUMENT,
			document_error
		)
	return _store.encoded_size(document)


func resolve(
	conflict: CloudSaveConflict,
	resolution: CloudSaveResolution
) -> GameServicesRequest:
	var conflict_error := _conflict_slot_error(conflict)
	if not conflict_error.is_empty():
		return _store._local_failure_request(
			CloudSaveStore.OP_RESOLVE,
			GameServicesResult.Code.INVALID_ARGUMENT,
			conflict_error
		)
	return _store.resolve(conflict, resolution)


func resolve_with_candidate(
	conflict: CloudSaveConflict,
	candidate: CloudSaveCandidate
) -> GameServicesRequest:
	var conflict_error := _conflict_slot_error(conflict)
	if not conflict_error.is_empty():
		return _store._local_failure_request(
			CloudSaveStore.OP_RESOLVE,
			GameServicesResult.Code.INVALID_ARGUMENT,
			conflict_error
		)
	return _store.resolve_with_candidate(conflict, candidate)


func resolve_with_value(
	conflict: CloudSaveConflict,
	value: Variant,
	base: CloudSaveCandidate = null,
	metadata: Dictionary = {}
) -> GameServicesRequest:
	var conflict_error := _conflict_slot_error(conflict)
	if not conflict_error.is_empty():
		return _store._local_failure_request(
			CloudSaveStore.OP_RESOLVE,
			GameServicesResult.Code.INVALID_ARGUMENT,
			conflict_error
		)
	return _store.resolve_with_value(conflict, value, base, metadata)


func _document_slot_error(document: CloudSaveDocument) -> String:
	if document == null:
		return "A cloud-save document is required"
	if document.slot != slot:
		return "The cloud-save document belongs to slot '%s', not '%s'" % [
			document.slot,
			slot,
		]
	return ""


func _conflict_slot_error(conflict: CloudSaveConflict) -> String:
	if conflict == null:
		return "A cloud-save conflict is required"
	if conflict.slot != slot:
		return "The cloud-save conflict belongs to slot '%s', not '%s'" % [
			conflict.slot,
			slot,
		]
	return ""


func _on_store_request_finished(
	request: GameServicesRequest,
	result: GameServicesResult
) -> void:
	request_finished.emit(request, result)
