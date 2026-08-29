class_name CloudSaveCandidate
extends RefCounted

## One provider snapshot participating in a cloud-save conflict.

var provider_id: String = ""
var document: CloudSaveDocument
var updated_at_msec: int = 0
var device_name: String = ""
var raw_data: PackedByteArray = []
var raw_metadata: Dictionary = {}
var decode_error: GameServicesResult


func is_decoded() -> bool:
	return document != null and decode_error == null
