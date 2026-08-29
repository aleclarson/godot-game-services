class_name CloudSaveInfo
extends RefCounted

## Provider summary returned without downloading and decoding the save body.

var slot: String = ""
var provider_id: String = ""
var updated_at_msec: int = 0
var device_name: String = ""
var description: String = ""
var played_time_msec: int = 0
var progress_value: int = 0

## Provider summaries cannot expose metadata stored inside the portable save
## envelope. Load the document when complete metadata is required.
var details_complete: bool = false
var raw_metadata: Dictionary = {}
