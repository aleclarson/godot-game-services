class_name CloudSaveConflict
extends RefCounted

## Decoded candidates and provider identifiers needed to resolve a conflict.

var id: String = ""
var slot: String = ""
var provider: StringName = &""
var candidates: Array[CloudSaveCandidate] = []
var proposed_document: CloudSaveDocument
var raw: Dictionary = {}


func newest() -> CloudSaveCandidate:
	var selected: CloudSaveCandidate
	for candidate in candidates:
		if not candidate.is_decoded():
			continue
		if selected == null or candidate.updated_at_msec > selected.updated_at_msec:
			selected = candidate
	return selected


func highest_progress() -> CloudSaveCandidate:
	var selected: CloudSaveCandidate
	for candidate in candidates:
		if not candidate.is_decoded():
			continue
		if selected == null or candidate.document.progress_value > selected.document.progress_value:
			selected = candidate
	return selected
