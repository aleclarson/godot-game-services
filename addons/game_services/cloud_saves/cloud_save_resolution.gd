class_name CloudSaveResolution
extends RefCounted

## Decision returned by a custom automatic conflict resolver.

enum Kind {
	ABORT,
	CHOOSE,
	MERGE,
}

var kind: Kind = Kind.ABORT
var candidate: CloudSaveCandidate
var value: Variant
var metadata: Dictionary = {}


static func abort() -> CloudSaveResolution:
	return CloudSaveResolution.new()


static func choose(p_candidate: CloudSaveCandidate) -> CloudSaveResolution:
	var resolution := CloudSaveResolution.new()
	resolution.kind = Kind.CHOOSE
	resolution.candidate = p_candidate
	return resolution


static func merge(
	p_value: Variant,
	base_candidate: CloudSaveCandidate,
	p_metadata: Dictionary = {}
) -> CloudSaveResolution:
	var resolution := CloudSaveResolution.new()
	resolution.kind = Kind.MERGE
	resolution.value = p_value
	resolution.candidate = base_candidate
	resolution.metadata = p_metadata.duplicate(true)
	return resolution
