class_name CloudSaveStore
extends RefCounted

## Typed, versioned cloud saves layered over the raw GameServices byte API.

signal request_finished(request: GameServicesRequest, result: GameServicesResult)

enum ConflictPolicy {
	MANUAL,
	NEWEST,
	HIGHEST_PROGRESS,
	CUSTOM,
}

const FORMAT_IDENTIFIER := "godot-game-services/cloud-save"
const FORMAT_VERSION := 1
const ALLOWED_SLOT_CHARACTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
const OP_SAVE := &"cloud_save_save"
const OP_LOAD := &"cloud_save_load"
const OP_LOAD_OR_CREATE := &"cloud_save_load_or_create"
const OP_LIST := &"cloud_save_list"
const OP_DELETE := &"cloud_save_delete"
const OP_RESOLVE := &"cloud_save_resolve"

var schema_version: int = 1:
	set(value):
		schema_version = maxi(value, 1)
var conflict_policy: ConflictPolicy = ConflictPolicy.MANUAL
var conflict_resolver: Callable
var max_conflict_attempts: int = 3:
	set(value):
		max_conflict_attempts = maxi(value, 1)

var _game_services: Node
var _migrations: Dictionary[int, Callable] = {}
var _active_requests: Dictionary[int, GameServicesRequest] = {}
var _crypto := Crypto.new()


func _init(p_game_services: Node = null) -> void:
	_game_services = p_game_services


func add_migration(from_version: int, migration: Callable) -> void:
	if from_version < 1:
		push_error("Cloud-save migration versions must be positive")
		return
	if not migration.is_valid():
		push_error("Cloud-save migrations must be valid callables")
		return
	_migrations[from_version] = migration


func remove_migration(from_version: int) -> void:
	_migrations.erase(from_version)


func clear_migrations() -> void:
	_migrations.clear()


func create(slot: String, value: Variant, metadata: Dictionary = {}) -> CloudSaveDocument:
	var document := CloudSaveDocument.new()
	document.slot = slot
	document.value = value
	document.schema_version = maxi(schema_version, 1)
	_apply_input_metadata(document, metadata)
	return document


func load(slot: String) -> GameServicesRequest:
	var target := _new_request(OP_LOAD)
	_start_load(target, slot, false, null)
	return target


func load_or_create(slot: String, default_value: Variant) -> GameServicesRequest:
	var target := _new_request(OP_LOAD_OR_CREATE)
	_start_load(target, slot, true, default_value)
	return target


func save(document: CloudSaveDocument) -> GameServicesRequest:
	var target := _new_request(OP_SAVE)
	if document == null:
		_complete_local_failure(
			target,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"A cloud-save document is required"
		)
		return target
	_start_save(target, document)
	return target


func list(force_reload: bool = false) -> GameServicesRequest:
	var target := _new_request(OP_LIST)
	var source := _transport(&"_cloud_save_list_transport", [force_reload])
	_bind(source, Callable(self, "_on_list_completed").bind(target))
	return target


func delete(slot: String) -> GameServicesRequest:
	var target := _new_request(OP_DELETE)
	if not _valid_slot(slot):
		_complete_local_failure(
			target,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"Cloud-save slots must contain 1-100 URL-safe characters"
		)
		return target
	var source := _transport(&"_cloud_save_list_transport", [true])
	_bind(source, Callable(self, "_on_delete_listed").bind(target, slot))
	return target


func resolve(
	conflict: CloudSaveConflict,
	resolution: CloudSaveResolution
) -> GameServicesRequest:
	var target := _new_request(OP_RESOLVE)
	if conflict == null or resolution == null:
		_complete_local_failure(
			target,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"A cloud-save conflict and resolution are required"
		)
		return target
	if conflict.provider != _provider_name():
		_complete_local_failure(
			target,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"The cloud-save conflict belongs to a different provider"
		)
		return target
	if resolution.kind == CloudSaveResolution.Kind.ABORT:
		target.complete(GameServicesResult.failure(
			target.operation,
			GameServicesResult.Code.CONFLICT,
			"Cloud-save conflict resolution was aborted",
			conflict.provider,
			null,
			conflict
		))
		return target
	_start_resolution(target, conflict, resolution, 1)
	return target


func resolve_with_candidate(
	conflict: CloudSaveConflict,
	candidate: CloudSaveCandidate
) -> GameServicesRequest:
	return resolve(conflict, CloudSaveResolution.choose(candidate))


func resolve_with_value(
	conflict: CloudSaveConflict,
	value: Variant,
	base: CloudSaveCandidate,
	metadata: Dictionary = {}
) -> GameServicesRequest:
	return resolve(conflict, CloudSaveResolution.merge(value, base, metadata))


func _start_load(
	target: GameServicesRequest,
	slot: String,
	use_default: bool,
	default_value: Variant
) -> void:
	var source := _transport(&"_cloud_save_load_transport", [slot])
	_bind(source, Callable(self, "_on_load_completed").bind(
		target,
		slot,
		use_default,
		default_value
	))


func _on_load_completed(
	result: GameServicesResult,
	target: GameServicesRequest,
	slot: String,
	use_default: bool,
	default_value: Variant
) -> void:
	if target.is_completed:
		return
	if result.ok:
		var loaded := _document_from_transport_result(result, target.operation, slot)
		if loaded is GameServicesResult:
			target.complete(loaded)
		else:
			target.complete(GameServicesResult.success(
				target.operation,
				loaded,
				result.provider
			))
		return
	if result.error_code == GameServicesResult.Code.NOT_FOUND and use_default:
		var cloned_default := _clone_value(default_value, target.operation)
		if cloned_default is GameServicesResult:
			target.complete(cloned_default)
			return
		target.complete(GameServicesResult.success(
			target.operation,
			create(slot, cloned_default),
			result.provider
		))
		return
	if result.error_code == GameServicesResult.Code.CONFLICT:
		_handle_conflict(result, target, slot, null, 0)
		return
	target.complete(_copy_failure(result, target.operation))


func _start_save(target: GameServicesRequest, source_document: CloudSaveDocument) -> void:
	var parents := PackedStringArray()
	if not source_document.revision.is_empty():
		parents.append(source_document.revision)
	var prepared := _prepare_document(source_document, parents, target.operation)
	if prepared is GameServicesResult:
		target.complete(prepared)
		return
	var document: CloudSaveDocument = prepared
	var encoded := _encode_document(document, target.operation)
	if encoded is GameServicesResult:
		target.complete(encoded)
		return
	var bytes: PackedByteArray = encoded
	var stable := _decode_document(bytes, target.operation, _provider_name(), document.slot)
	if stable is GameServicesResult:
		target.complete(stable)
		return
	var stable_document: CloudSaveDocument = stable
	var source := _transport(&"_cloud_save_save_transport", [
		stable_document.slot,
		bytes,
		stable_document.portable_metadata(),
	])
	_bind(source, Callable(self, "_on_save_completed").bind(target, stable_document))


func _on_save_completed(
	result: GameServicesResult,
	target: GameServicesRequest,
	document: CloudSaveDocument
) -> void:
	if target.is_completed:
		return
	if result.ok:
		_apply_provider_metadata(document, _metadata_from_result(result.data))
		target.complete(GameServicesResult.success(
			target.operation,
			document,
			result.provider
		))
		return
	if result.error_code == GameServicesResult.Code.CONFLICT:
		_handle_conflict(result, target, document.slot, document, 0)
		return
	target.complete(_copy_failure(result, target.operation))


func _on_list_completed(result: GameServicesResult, target: GameServicesRequest) -> void:
	if target.is_completed:
		return
	if not result.ok:
		target.complete(_copy_failure(result, target.operation))
		return
	if result.data is not Array:
		target.complete(_invalid_data(
			target.operation,
			"The provider returned an invalid cloud-save list",
			result.provider
		))
		return
	var saves: Array[CloudSaveInfo] = []
	for value: Variant in result.data:
		if value is Dictionary:
			saves.append(_info_from_metadata(value))
	target.complete(GameServicesResult.success(target.operation, saves, result.provider))


func _on_delete_listed(
	result: GameServicesResult,
	target: GameServicesRequest,
	slot: String
) -> void:
	if target.is_completed:
		return
	if not result.ok:
		target.complete(_copy_failure(result, target.operation))
		return
	if result.data is not Array:
		target.complete(_invalid_data(
			target.operation,
			"The provider returned an invalid cloud-save list",
			result.provider
		))
		return
	var provider_id := ""
	for value: Variant in result.data:
		if value is not Dictionary or str(value.get("name", "")) != slot:
			continue
		provider_id = str(value.get("id", slot))
		if provider_id.is_empty():
			provider_id = slot
		break
	if provider_id.is_empty():
		target.complete(GameServicesResult.failure(
			target.operation,
			GameServicesResult.Code.NOT_FOUND,
			"Cloud-save slot '%s' does not exist" % slot,
			result.provider
		))
		return
	var source := _transport(&"_cloud_save_delete_transport", [provider_id])
	_bind(source, Callable(self, "_on_delete_completed").bind(
		target,
		slot,
		provider_id
	))


func _on_delete_completed(
	result: GameServicesResult,
	target: GameServicesRequest,
	slot: String,
	provider_id: String
) -> void:
	if target.is_completed:
		return
	if not result.ok:
		target.complete(_copy_failure(result, target.operation))
		return
	var deleted := true
	if result.data is Dictionary:
		deleted = bool(result.data.get("deleted", true))
	target.complete(GameServicesResult.success(target.operation, {
		"slot": slot,
		"provider_id": provider_id,
		"deleted": deleted,
	}, result.provider))


func _handle_conflict(
	result: GameServicesResult,
	target: GameServicesRequest,
	slot: String,
	proposed_document: CloudSaveDocument,
	attempts: int
) -> void:
	var decoded := _decode_conflict(result, target.operation, slot, proposed_document)
	if decoded is GameServicesResult:
		target.complete(decoded)
		return
	var conflict: CloudSaveConflict = decoded
	if conflict_policy == ConflictPolicy.MANUAL or attempts >= maxi(max_conflict_attempts, 1):
		_complete_conflict(target, result, conflict)
		return
	var resolution := _automatic_resolution(conflict)
	if resolution == null or resolution.kind == CloudSaveResolution.Kind.ABORT:
		_complete_conflict(target, result, conflict)
		return
	_start_resolution(target, conflict, resolution, attempts + 1)


func _automatic_resolution(conflict: CloudSaveConflict) -> CloudSaveResolution:
	match conflict_policy:
		ConflictPolicy.NEWEST:
			var newest := conflict.newest()
			return CloudSaveResolution.choose(newest) if newest != null else null
		ConflictPolicy.HIGHEST_PROGRESS:
			var highest := conflict.highest_progress()
			return CloudSaveResolution.choose(highest) if highest != null else null
		ConflictPolicy.CUSTOM:
			if not conflict_resolver.is_valid():
				return null
			var value: Variant = conflict_resolver.call(conflict)
			if value is CloudSaveResolution:
				return value
			if value is CloudSaveCandidate:
				return CloudSaveResolution.choose(value)
	return null


func _start_resolution(
	target: GameServicesRequest,
	conflict: CloudSaveConflict,
	resolution: CloudSaveResolution,
	attempts: int
) -> void:
	if target.is_completed:
		return
	var base := resolution.candidate
	if base == null or not base.is_decoded() or not conflict.candidates.has(base):
		_complete_local_failure(
			target,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"Conflict resolution requires a decoded candidate from this conflict"
		)
		return
	var document := base.document.duplicate_document()
	if resolution.kind == CloudSaveResolution.Kind.MERGE:
		document.value = resolution.value
		_apply_input_metadata(document, resolution.metadata)
	elif resolution.kind != CloudSaveResolution.Kind.CHOOSE:
		_complete_local_failure(
			target,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"The cloud-save resolution was aborted"
		)
		return
	document.slot = conflict.slot
	var parents := PackedStringArray()
	for candidate in conflict.candidates:
		if candidate.document == null or candidate.document.revision.is_empty():
			continue
		if not parents.has(candidate.document.revision):
			parents.append(candidate.document.revision)
	var prepared := _prepare_document(document, parents, target.operation)
	if prepared is GameServicesResult:
		target.complete(prepared)
		return
	document = prepared
	var encoded := _encode_document(document, target.operation)
	if encoded is GameServicesResult:
		target.complete(encoded)
		return
	var bytes: PackedByteArray = encoded
	var stable := _decode_document(bytes, target.operation, _provider_name(), document.slot)
	if stable is GameServicesResult:
		target.complete(stable)
		return
	var stable_document: CloudSaveDocument = stable
	var source := _transport(&"_cloud_save_resolve_transport", [
		conflict.id,
		base.provider_id,
		bytes,
		stable_document.portable_metadata(),
	])
	_bind(source, Callable(self, "_on_resolution_completed").bind(
		target,
		stable_document,
		attempts
	))


func _on_resolution_completed(
	result: GameServicesResult,
	target: GameServicesRequest,
	document: CloudSaveDocument,
	attempts: int
) -> void:
	if target.is_completed:
		return
	if result.ok:
		_apply_provider_metadata(document, _metadata_from_result(result.data))
		target.complete(GameServicesResult.success(
			target.operation,
			document,
			result.provider
		))
		return
	if result.error_code == GameServicesResult.Code.CONFLICT:
		_handle_conflict(result, target, document.slot, document, attempts)
		return
	target.complete(_copy_failure(result, target.operation))


func _prepare_document(
	source: CloudSaveDocument,
	parents: PackedStringArray,
	operation: StringName
) -> Variant:
	if source.slot.is_empty():
		return GameServicesResult.failure(
			operation,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"A cloud-save slot is required",
			_provider_name()
		)
	var document := source.duplicate_document()
	var cloned_value := _clone_value(document.value, operation)
	if cloned_value is GameServicesResult:
		return cloned_value
	document.value = cloned_value
	var migrated := _migrate_document(document, operation, _provider_name())
	if migrated is GameServicesResult:
		return migrated
	document = migrated
	document.schema_version = maxi(schema_version, 1)
	document.revision = _new_revision()
	document.parent_revisions = parents.duplicate()
	document.saved_at_msec = _now_msec()
	document.needs_save = false
	return document


func _clone_value(value: Variant, operation: StringName) -> Variant:
	var validation_error := _serialization_error(value)
	if not validation_error.is_empty():
		return GameServicesResult.failure(
			operation,
			GameServicesResult.Code.INVALID_ARGUMENT,
			validation_error,
			_provider_name()
		)
	var encoded := var_to_bytes(value)
	if encoded.is_empty():
		return GameServicesResult.failure(
			operation,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"The cloud-save value could not be serialized safely",
			_provider_name()
		)
	return bytes_to_var(encoded)


func _serialization_error(value: Variant, depth: int = 0) -> String:
	if depth > 64:
		return "Cloud-save values cannot be cyclic or nested more than 64 levels"
	match typeof(value):
		TYPE_OBJECT:
			return "Cloud-save values cannot contain objects"
		TYPE_CALLABLE:
			return "Cloud-save values cannot contain callables"
		TYPE_SIGNAL:
			return "Cloud-save values cannot contain signals"
		TYPE_ARRAY:
			for item: Variant in value:
				var item_error := _serialization_error(item, depth + 1)
				if not item_error.is_empty():
					return item_error
		TYPE_DICTIONARY:
			for key: Variant in value:
				var key_error := _serialization_error(key, depth + 1)
				if not key_error.is_empty():
					return key_error
				var value_error := _serialization_error(value[key], depth + 1)
				if not value_error.is_empty():
					return value_error
	return ""


func _encode_document(document: CloudSaveDocument, operation: StringName) -> Variant:
	var envelope := {
		"format": FORMAT_IDENTIFIER,
		"format_version": FORMAT_VERSION,
		"slot": document.slot,
		"schema_version": document.schema_version,
		"revision": document.revision,
		"parent_revisions": document.parent_revisions,
		"saved_at_msec": document.saved_at_msec,
		"metadata": document.all_metadata(),
		"value": document.value,
	}
	var validation_error := _serialization_error(envelope)
	if not validation_error.is_empty():
		return GameServicesResult.failure(
			operation,
			GameServicesResult.Code.INVALID_ARGUMENT,
			validation_error,
			_provider_name()
		)
	var encoded := var_to_bytes(envelope)
	if encoded.is_empty():
		return GameServicesResult.failure(
			operation,
			GameServicesResult.Code.INVALID_ARGUMENT,
			"The cloud-save value could not be serialized safely",
			_provider_name()
		)
	return encoded


func _decode_document(
	data: PackedByteArray,
	operation: StringName,
	provider: StringName,
	expected_slot: String = ""
) -> Variant:
	var decoded := bytes_to_var(data)
	if decoded is not Dictionary:
		return _invalid_data(operation, "The cloud save is not a portable save envelope", provider)
	var envelope: Dictionary = decoded
	var validation_error := _serialization_error(envelope)
	if not validation_error.is_empty():
		return _invalid_data(operation, validation_error, provider)
	if typeof(envelope.get("format")) != TYPE_STRING:
		return _invalid_data(operation, "The cloud save has no valid format identifier", provider)
	if str(envelope.get("format", "")) != FORMAT_IDENTIFIER:
		return _invalid_data(operation, "The cloud save uses an unknown format", provider)
	if typeof(envelope.get("format_version")) != TYPE_INT:
		return _invalid_data(operation, "The cloud save has no valid format version", provider)
	if int(envelope.get("format_version", 0)) != FORMAT_VERSION:
		return _invalid_data(operation, "The cloud-save format version is unsupported", provider)
	if typeof(envelope.get("slot")) != TYPE_STRING:
		return _invalid_data(operation, "The cloud save has no valid slot", provider)
	var slot := str(envelope.get("slot", ""))
	if slot.is_empty() or (not expected_slot.is_empty() and slot != expected_slot):
		return _invalid_data(operation, "The cloud-save slot does not match its envelope", provider)
	if typeof(envelope.get("schema_version")) != TYPE_INT:
		return _invalid_data(operation, "The cloud save has no valid schema version", provider)
	var stored_schema := int(envelope.get("schema_version", 0))
	var current_schema := maxi(schema_version, 1)
	if stored_schema < 1:
		return _invalid_data(operation, "The cloud save has no valid schema version", provider)
	if stored_schema > current_schema:
		return _invalid_data(
			operation,
			"Cloud-save schema %d is newer than supported schema %d" % [
				stored_schema,
				current_schema,
			],
			provider
		)
	if typeof(envelope.get("revision")) != TYPE_STRING:
		return _invalid_data(operation, "The cloud save has no valid revision identifier", provider)
	if envelope.get("parent_revisions") is not PackedStringArray \
	and envelope.get("parent_revisions") is not Array:
		return _invalid_data(operation, "The cloud save has invalid revision ancestry", provider)
	var parent_revisions := PackedStringArray()
	for parent: Variant in envelope.parent_revisions:
		if typeof(parent) != TYPE_STRING:
			return _invalid_data(operation, "The cloud save has invalid revision ancestry", provider)
		parent_revisions.append(parent)
	if typeof(envelope.get("saved_at_msec")) != TYPE_INT:
		return _invalid_data(operation, "The cloud save has no valid save timestamp", provider)
	if envelope.get("metadata") is not Dictionary:
		return _invalid_data(operation, "The cloud save has invalid metadata", provider)
	if not envelope.has("value"):
		return _invalid_data(operation, "The cloud save has no value", provider)
	var metadata: Dictionary = envelope.metadata
	var document := CloudSaveDocument.new()
	document.slot = slot
	document.value = envelope.get("value")
	document.schema_version = stored_schema
	document.revision = str(envelope.get("revision", ""))
	document.parent_revisions = parent_revisions
	document.saved_at_msec = int(envelope.get("saved_at_msec", 0))
	_apply_input_metadata(document, metadata)
	if document.revision.is_empty():
		return _invalid_data(operation, "The cloud save has no revision identifier", provider)
	return _migrate_document(document, operation, provider)


func _migrate_document(
	document: CloudSaveDocument,
	operation: StringName,
	provider: StringName
) -> Variant:
	var current_schema := maxi(schema_version, 1)
	if document.schema_version > current_schema:
		return _invalid_data(
			operation,
			"Cloud-save schema %d is newer than supported schema %d" % [
				document.schema_version,
				current_schema,
			],
			provider
		)
	while document.schema_version < current_schema:
		var from_version := document.schema_version
		var migration: Callable = _migrations.get(document.schema_version, Callable())
		if not migration.is_valid():
			return _invalid_data(
				operation,
				"No migration exists from cloud-save schema %d" % document.schema_version,
				provider
			)
		document.value = migration.call(document.value)
		var validation_error := _serialization_error(document.value)
		if not validation_error.is_empty():
			return _invalid_data(
				operation,
				"Cloud-save migration from schema %d produced an unsupported value: %s" % [
					from_version,
					validation_error,
				],
				provider
			)
		document.schema_version += 1
		document.needs_save = true
	return document


func _document_from_transport_result(
	result: GameServicesResult,
	operation: StringName,
	slot: String
) -> Variant:
	if result.data is not Dictionary or result.data.get("data") is not PackedByteArray:
		return _invalid_data(operation, "The provider returned invalid cloud-save data", result.provider)
	var decoded := _decode_document(result.data.data, operation, result.provider, slot)
	if decoded is GameServicesResult:
		return decoded
	var document: CloudSaveDocument = decoded
	_apply_provider_metadata(document, result.data.get("metadata", {}))
	return document


func _decode_conflict(
	result: GameServicesResult,
	operation: StringName,
	slot: String,
	proposed_document: CloudSaveDocument
) -> Variant:
	if result.data is not Dictionary or result.data.get("snapshots") is not Array:
		return _invalid_data(operation, "The provider returned an invalid conflict", result.provider)
	var conflict := CloudSaveConflict.new()
	conflict.id = str(result.data.get("conflict_id", ""))
	conflict.slot = slot
	conflict.provider = result.provider
	conflict.proposed_document = proposed_document
	conflict.raw = result.data.duplicate(true)
	if conflict.id.is_empty():
		return _invalid_data(operation, "The provider conflict has no identifier", result.provider)
	for value: Variant in result.data.snapshots:
		if value is not Dictionary:
			continue
		var candidate := CloudSaveCandidate.new()
		var metadata: Dictionary = (
			value.get("metadata", {}) if value.get("metadata", {}) is Dictionary else {}
		)
		candidate.provider_id = str(value.get("id", metadata.get("id", "")))
		candidate.updated_at_msec = int(metadata.get("updated_at_msec", 0))
		candidate.device_name = str(metadata.get("device_name", ""))
		candidate.raw_metadata = metadata.duplicate(true)
		candidate.raw_data = value.get("data", PackedByteArray())
		var decoded := _decode_document(
			candidate.raw_data,
			operation,
			result.provider,
			slot
		)
		if decoded is GameServicesResult:
			candidate.decode_error = decoded
		else:
			candidate.document = decoded
			_apply_provider_metadata(candidate.document, metadata)
		conflict.candidates.append(candidate)
	if conflict.candidates.is_empty():
		return _invalid_data(operation, "The provider conflict has no candidates", result.provider)
	return conflict


func _info_from_metadata(metadata: Dictionary) -> CloudSaveInfo:
	var info := CloudSaveInfo.new()
	info.slot = str(metadata.get("name", ""))
	info.provider_id = str(metadata.get("id", info.slot))
	if info.provider_id.is_empty():
		info.provider_id = info.slot
	info.updated_at_msec = int(metadata.get("updated_at_msec", 0))
	info.device_name = str(metadata.get("device_name", ""))
	info.description = str(metadata.get("description", ""))
	info.played_time_msec = int(metadata.get("played_time_msec", 0))
	info.progress_value = int(metadata.get("progress_value", 0))
	info.raw_metadata = metadata.duplicate(true)
	return info


func _apply_input_metadata(document: CloudSaveDocument, metadata: Dictionary) -> void:
	if metadata.has("description"):
		document.description = str(metadata.description)
	if metadata.has("played_time_msec"):
		document.played_time_msec = int(metadata.played_time_msec)
	if metadata.has("progress_value"):
		document.progress_value = int(metadata.progress_value)
	var custom := metadata.duplicate(true)
	custom.erase("description")
	custom.erase("played_time_msec")
	custom.erase("progress_value")
	var nested: Variant = custom.get("custom_metadata", {})
	custom.erase("custom_metadata")
	if nested is Dictionary:
		custom.merge(nested, true)
	document.custom_metadata.merge(custom, true)


func _apply_provider_metadata(document: CloudSaveDocument, metadata: Variant) -> void:
	if metadata is not Dictionary:
		return
	document.provider_id = str(metadata.get("id", metadata.get("name", document.slot)))
	if document.provider_id.is_empty():
		document.provider_id = document.slot
	document.updated_at_msec = int(metadata.get("updated_at_msec", document.saved_at_msec))
	document.device_name = str(metadata.get("device_name", ""))
	document.raw_metadata = metadata.duplicate(true)


func _metadata_from_result(data: Variant) -> Dictionary:
	if data is not Dictionary:
		return {}
	if data.get("metadata") is Dictionary:
		return data.metadata
	if data.get("snapshots") is Array and not data.snapshots.is_empty():
		var first: Variant = data.snapshots[0]
		if first is Dictionary:
			return first
	return data


func _complete_conflict(
	target: GameServicesRequest,
	source_result: GameServicesResult,
	conflict: CloudSaveConflict
) -> void:
	target.complete(GameServicesResult.failure(
		target.operation,
		GameServicesResult.Code.CONFLICT,
		"Cloud-save conflict requires resolution",
		source_result.provider,
		source_result.platform_code,
		conflict
	))


func _copy_failure(result: GameServicesResult, operation: StringName) -> GameServicesResult:
	return GameServicesResult.failure(
		operation,
		result.error_code,
		result.error_message,
		result.provider,
		result.platform_code,
		result.data
	)


func _invalid_data(
	operation: StringName,
	message: String,
	provider: StringName
) -> GameServicesResult:
	return GameServicesResult.failure(
		operation,
		GameServicesResult.Code.INVALID_DATA,
		message,
		provider
	)


func _new_request(operation: StringName) -> GameServicesRequest:
	var request := GameServicesRequest.new(operation)
	_active_requests[request.id] = request
	request.completed.connect(
		Callable(self, "_on_request_completed").bind(request),
		CONNECT_ONE_SHOT
	)
	return request


func _on_request_completed(result: GameServicesResult, request: GameServicesRequest) -> void:
	_active_requests.erase(request.id)
	request_finished.emit(request, result)


func _complete_local_failure(
	target: GameServicesRequest,
	code: GameServicesResult.Code,
	message: String
) -> void:
	target.complete(GameServicesResult.failure(
		target.operation,
		code,
		message,
		_provider_name()
	))


func _transport(method: StringName, arguments: Array) -> GameServicesRequest:
	if not is_instance_valid(_game_services) or not _game_services.has_method(method):
		var unavailable := GameServicesRequest.new(method)
		unavailable.complete(GameServicesResult.failure(
			method,
			GameServicesResult.Code.UNAVAILABLE,
			"Game services are unavailable",
			&"unavailable"
		))
		return unavailable
	var request := _game_services.callv(method, arguments) as GameServicesRequest
	if request != null:
		return request
	var invalid := GameServicesRequest.new(method)
	invalid.complete(GameServicesResult.failure(
		method,
		GameServicesResult.Code.INTERNAL_ERROR,
		"The cloud-save transport did not return a request",
		_provider_name()
	))
	return invalid


func _bind(source: GameServicesRequest, callback: Callable) -> void:
	if source.is_completed:
		callback.call(source.result)
	else:
		source.completed.connect(callback, CONNECT_ONE_SHOT)


func _provider_name() -> StringName:
	if is_instance_valid(_game_services) and _game_services.has_method("provider_name"):
		return _game_services.call("provider_name")
	return &"unavailable"


func _new_revision() -> String:
	return _crypto.generate_random_bytes(16).hex_encode()


func _now_msec() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 100:
		return false
	for character in slot:
		if ALLOWED_SLOT_CHARACTERS.find(character) < 0:
			return false
	return true


func _cancel_pending_requests(cancelled_provider: StringName) -> void:
	var requests := _active_requests.values()
	for value: Variant in requests:
		var request := value as GameServicesRequest
		if request == null or request.is_completed:
			continue
		request.complete(GameServicesResult.failure(
			request.operation,
			GameServicesResult.Code.CANCELLED,
			"Game services shut down before the cloud-save request completed",
			cancelled_provider
		))
	_active_requests.clear()
