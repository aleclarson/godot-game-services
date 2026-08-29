class_name CloudSaveDocument
extends RefCounted

## A decoded cloud-save value plus portable and provider metadata.

var slot: String = ""
var value: Variant

var schema_version: int = 1
var revision: String = ""
var parent_revisions: PackedStringArray = []
var saved_at_msec: int = 0

var description: String = ""
var played_time_msec: int = 0
var progress_value: int = 0
var custom_metadata: Dictionary = {}

var provider_id: String = ""
var updated_at_msec: int = 0
var device_name: String = ""
var raw_metadata: Dictionary = {}

## True when a migration changed [member value] but the upgraded document has
## not been written back yet.
var needs_save: bool = false


func duplicate_document() -> CloudSaveDocument:
	var copy := CloudSaveDocument.new()
	copy.slot = slot
	copy.value = _duplicate_value(value)
	copy.schema_version = schema_version
	copy.revision = revision
	copy.parent_revisions = parent_revisions.duplicate()
	copy.saved_at_msec = saved_at_msec
	copy.description = description
	copy.played_time_msec = played_time_msec
	copy.progress_value = progress_value
	copy.custom_metadata = custom_metadata.duplicate(true)
	copy.provider_id = provider_id
	copy.updated_at_msec = updated_at_msec
	copy.device_name = device_name
	copy.raw_metadata = raw_metadata.duplicate(true)
	copy.needs_save = needs_save
	return copy


func portable_metadata() -> Dictionary:
	return {
		"description": description,
		"played_time_msec": played_time_msec,
		"progress_value": progress_value,
	}


func all_metadata() -> Dictionary:
	var metadata := custom_metadata.duplicate(true)
	metadata["description"] = description
	metadata["played_time_msec"] = played_time_msec
	metadata["progress_value"] = progress_value
	return metadata


func _duplicate_value(source: Variant) -> Variant:
	match typeof(source):
		TYPE_ARRAY, TYPE_DICTIONARY:
			return source.duplicate(true)
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, \
		TYPE_PACKED_VECTOR4_ARRAY:
			return source.duplicate()
	return source
