extends SceneTree

const GameServicesScript := preload("res://addons/game_services/game_services.gd")
const FakeGameCenter := preload("res://tests/fakes/fake_game_center.gd")
const FakeGooglePlayGames := preload("res://tests/fakes/fake_google_play_games.gd")

var _failures: PackedStringArray = []


class UnavailableProvider extends GameServicesProvider:
	func provider_name() -> StringName:
		return &"unavailable_test"


	func initialize(p_config: GameServicesConfig) -> GameServicesResult:
		config = p_config
		return GameServicesResult.failure(
			&"initialize",
			GameServicesResult.Code.UNAVAILABLE,
			"Native bridge missing",
			provider_name()
		)


class PendingProvider extends GameServicesProvider:
	func provider_name() -> StringName:
		return &"pending_test"


	func capabilities() -> int:
		return Capability.AUTHENTICATION


	func authenticate() -> GameServicesRequest:
		return _new_request(&"authenticate")


class PendingCloudSaveProvider extends GameServicesProvider:
	func provider_name() -> StringName:
		return &"pending_cloud_save_test"


	func capabilities() -> int:
		return Capability.CLOUD_SAVES


	func save_game(
		_name: String,
		_data: PackedByteArray,
		_metadata: Dictionary = {}
	) -> GameServicesRequest:
		return _new_request(&"save_game")


class ConflictCloudSaveProvider extends GameServicesProvider:
	var payloads: Array[PackedByteArray] = []
	var conflict_mode: bool = false
	var resolved_snapshot_id: String = ""
	var resolve_count: int = 0


	func provider_name() -> StringName:
		return &"conflict_cloud_save_test"


	func capabilities() -> int:
		return Capability.CLOUD_SAVES


	func save_game(
		name: String,
		data: PackedByteArray,
		metadata: Dictionary = {}
	) -> GameServicesRequest:
		payloads.append(data.duplicate())
		var request := _new_request(&"save_game")
		var result_metadata := metadata.duplicate(true)
		result_metadata.merge({
			"id": "snapshot-%d" % payloads.size(),
			"name": name,
			"updated_at_msec": payloads.size() * 100,
		}, true)
		request.complete(GameServicesResult.success(
			&"save_game",
			result_metadata,
			provider_name()
		))
		return request


	func load_game(name: String) -> GameServicesRequest:
		var request := _new_request(&"load_game")
		if not conflict_mode or payloads.size() < 2:
			request.complete(GameServicesResult.failure(
				&"load_game",
				GameServicesResult.Code.NOT_FOUND,
				"No conflict fixture is available",
				provider_name()
			))
			return request
		request.complete(GameServicesResult.failure(
			&"load_game",
			GameServicesResult.Code.CONFLICT,
			"Fixture conflict",
			provider_name(),
			null,
			{
				"conflict_id": "fixture-conflict",
				"snapshots": [
					{
						"id": "left",
						"data": payloads[0],
						"metadata": {
							"id": "left",
							"name": name,
							"updated_at_msec": 200,
						},
					},
					{
						"id": "right",
						"data": payloads[1],
						"metadata": {
							"id": "right",
							"name": name,
							"updated_at_msec": 100,
						},
					},
				],
			}
		))
		return request


	func resolve_saved_game_conflict(
		_conflict_id: String,
		snapshot_id: String,
		_data: PackedByteArray,
		_metadata: Dictionary = {}
	) -> GameServicesRequest:
		resolved_snapshot_id = snapshot_id
		resolve_count += 1
		var request := _new_request(&"resolve_saved_game_conflict")
		request.complete(GameServicesResult.success(
			&"resolve_saved_game_conflict",
			{
				"metadata": {
					"id": "resolved",
					"name": "conflict-slot",
					"updated_at_msec": 300 + resolve_count,
				},
			},
			provider_name()
		))
		return request


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := GameServicesScript.new()
	service.auto_initialize = false
	root.add_child(service)
	var finished_request_ids: Array[int] = []
	service.request_finished.connect(
		func(request: GameServicesRequest, _result: GameServicesResult) -> void:
			finished_request_ids.append(request.id)
	)

	var test_config := GameServicesConfig.new()
	test_config.request_timeout_seconds = 2.0
	test_config.apple_achievement_ids = {"first_win": "gc.first_win"}
	test_config.google_achievement_ids = {"first_win": "CgkI_first_win"}
	test_config.google_achievement_steps = {"first_win": 10}
	test_config.apple_leaderboard_ids = {"high_score": "gc.high_score"}
	test_config.apple_leaderboard_ids["low_score"] = "gc.low_score"
	test_config.google_leaderboard_ids = {
		"high_score": "CgkI_high_score",
		"low_score": "CgkI_low_score",
	}

	var unavailable := service.initialize(test_config, UnavailableProvider.new())
	_check(not unavailable.ok, "Provider initialization failures are returned")
	_check(service.capabilities() == 0, "Failed providers advertise no capabilities")
	var unavailable_auth: GameServicesResult = await service.authenticate().wait()
	_check(
		unavailable_auth.error_code == GameServicesResult.Code.UNAVAILABLE,
		"Calls cannot reach a provider that failed initialization"
	)

	_check(
		test_config.achievement_id(&"first_win", &"apple_game_center") == "gc.first_win",
		"Apple achievement mappings resolve"
	)
	_check(
		test_config.achievement_total_steps(&"first_win", &"google_play_games") == 10,
		"Google achievement step mappings resolve"
	)

	var pending_initialized := service.initialize(test_config, PendingProvider.new())
	_check(pending_initialized.ok, "Pending provider initializes")
	var pending_request := service.authenticate()
	service.shutdown()
	var cancelled: GameServicesResult = await pending_request.wait()
	_check(
		cancelled.error_code == GameServicesResult.Code.CANCELLED
		and cancelled.provider == &"pending_test",
		"Shutdown cancels pending requests with their original provider"
	)
	_check(
		finished_request_ids.count(pending_request.id) == 1,
		"A cancelled request emits request_finished exactly once"
	)

	var initialized := service.initialize(test_config, MockGameServicesProvider.new())
	_check(initialized.ok, "Mock provider initializes")
	_check(service.provider_name() == &"mock", "Mock provider is selected")
	_check(service.supports(service.Capability.CLOUD_SAVES), "Mock advertises cloud saves")

	var locked_result: GameServicesResult = await service.unlock_achievement(&"first_win").wait()
	_check(
		locked_result.error_code == GameServicesResult.Code.NOT_AUTHENTICATED,
		"Operations fail portably before authentication"
	)

	var auth_result: GameServicesResult = await service.authenticate().wait()
	_check(auth_result.ok and service.is_authenticated(), "Authentication updates state")
	_check(auth_result.data.player.id == "mock-player", "Authentication returns normalized player data")

	var progress_result: GameServicesResult = await service.set_achievement_progress(&"first_win", 0.6).wait()
	_check(progress_result.ok, "Achievement progress succeeds")
	_check(progress_result.data.id == "first_win", "Achievement result uses the logical ID")

	await service.set_achievement_progress(&"first_win", 0.2).wait()
	var achievements_result: GameServicesResult = await service.load_achievements().wait()
	_check(achievements_result.ok and achievements_result.data.size() == 1, "Achievements load")
	_check(
		is_equal_approx(achievements_result.data[0].progress, 0.6),
		"Achievement progress is monotonic"
	)
	_check(achievements_result.data[0].id == "first_win", "Loaded achievements use logical IDs")

	var invalid_progress: GameServicesResult = await service.set_achievement_progress(&"first_win", 1.1).wait()
	_check(
		invalid_progress.error_code == GameServicesResult.Code.INVALID_ARGUMENT,
		"Out-of-range progress fails immediately without racing wait()"
	)

	var score_result: GameServicesResult = await service.submit_score(&"high_score", 42000).wait()
	_check(score_result.ok and score_result.data.id == "high_score", "Scores use logical leaderboard IDs")

	var bytes := "save payload".to_utf8_buffer()
	var save_result: GameServicesResult = await service.save_game(
		"slot-1",
		bytes,
		{"description": "Test save"}
	).wait()
	_check(save_result.ok, "Binary save data is accepted")

	var list_result: GameServicesResult = await service.list_saved_games().wait()
	_check(list_result.ok and list_result.data.size() == 1, "Saved games can be listed")

	var load_result: GameServicesResult = await service.load_game("slot-1").wait()
	_check(load_result.ok and load_result.data.data == bytes, "Saved binary data round-trips")

	var delete_result: GameServicesResult = await service.delete_saved_game("slot-1").wait()
	_check(delete_result.ok and delete_result.data.deleted, "Saved games can be deleted")

	var missing_load: GameServicesResult = await service.load_game("slot-1").wait()
	_check(
		missing_load.error_code == GameServicesResult.Code.NOT_FOUND,
		"Missing saved games use the portable not-found code"
	)

	var missing_conflict: GameServicesResult = await service.resolve_saved_game_conflict(
		"missing-conflict",
		"",
		bytes
	).wait()
	_check(
		missing_conflict.error_code == GameServicesResult.Code.NOT_FOUND,
		"Unknown cloud-save conflicts use the portable not-found code"
	)

	var invalid_save: GameServicesResult = await service.save_game("bad/name", bytes).wait()
	_check(
		invalid_save.error_code == GameServicesResult.Code.INVALID_ARGUMENT,
		"Cross-platform save names are validated"
	)

	await _test_cloud_save_store(service, finished_request_ids)
	await _test_cloud_save_cancellation(service, test_config)

	service.shutdown()
	service.queue_free()

	await _test_cloud_save_conflicts(test_config)
	await _test_google_adapter(test_config)
	await _test_apple_adapter(test_config)

	if _failures.is_empty():
		print("PASS: all game-services tests")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: %s" % failure)
		quit(1)


func _test_cloud_save_store(
	service: Node,
	facade_finished_request_ids: Array[int]
) -> void:
	var store: CloudSaveStore = service.cloud_saves
	store.schema_version = 1
	store.conflict_policy = CloudSaveStore.ConflictPolicy.MANUAL
	store.clear_migrations()

	var finished_request_ids: Array[int] = []
	store.request_finished.connect(
		func(request: GameServicesRequest, _result: GameServicesResult) -> void:
			finished_request_ids.append(request.id)
	)

	await process_frame
	var facade_finished_count := facade_finished_request_ids.size()
	var document := store.create("typed-slot", {
		"coins": 10,
		"position": Vector2(2.0, 3.0),
	}, {
		"description": "Typed save",
		"played_time_msec": 5_000,
		"progress_value": 25,
		"difficulty": "hard",
	})
	var first_request := store.save(document)
	var first_save: GameServicesResult = await first_request.wait()
	_check(first_save.ok and first_save.data is CloudSaveDocument, "Typed cloud saves serialize")
	if not first_save.ok or first_save.data is not CloudSaveDocument:
		return
	var first: CloudSaveDocument = first_save.data
	_check(not first.revision.is_empty(), "Cloud saves receive revision identifiers")
	_check(first.custom_metadata.difficulty == "hard", "Custom save metadata round-trips")
	_check(
		finished_request_ids.count(first_request.id) == 1,
		"The high-level store emits request completion exactly once"
	)
	await process_frame
	_check(
		facade_finished_request_ids.size() == facade_finished_count,
		"Internal cloud-save transport requests stay out of facade completion events"
	)

	first.value.coins = 20
	var second_save: GameServicesResult = await store.save(first).wait()
	_check(second_save.ok and second_save.data is CloudSaveDocument, "Typed cloud saves update")
	if not second_save.ok or second_save.data is not CloudSaveDocument:
		return
	var second: CloudSaveDocument = second_save.data
	_check(second.revision != first.revision, "Each save creates a new revision")
	_check(
		second.parent_revisions == PackedStringArray([first.revision]),
		"Updated saves retain revision ancestry"
	)

	var loaded_result: GameServicesResult = await store.load("typed-slot").wait()
	_check(loaded_result.ok and loaded_result.data is CloudSaveDocument, "Typed cloud saves load")
	if loaded_result.ok and loaded_result.data is CloudSaveDocument:
		var loaded: CloudSaveDocument = loaded_result.data
		_check(loaded.value.coins == 20, "Cloud-save values round-trip")
		_check(loaded.value.position == Vector2(2.0, 3.0), "Godot Variant types round-trip")
		_check(loaded.description == "Typed save", "Portable save metadata round-trips")

	var migration_source := store.create("migration-slot", {"coins": 5})
	var migration_saved: GameServicesResult = await store.save(migration_source).wait()
	_check(migration_saved.ok, "Migration fixture saves")
	store.schema_version = 2
	store.add_migration(1, Callable(self, "_migrate_cloud_save_v1"))
	var migrated_result: GameServicesResult = await store.load("migration-slot").wait()
	_check(
		migrated_result.ok
		and migrated_result.data is CloudSaveDocument
		and migrated_result.data.schema_version == 2
		and migrated_result.data.needs_save
		and migrated_result.data.value.difficulty == "normal",
		"Cloud saves migrate incrementally without an implicit write"
	)

	var listed_result: GameServicesResult = await store.list().wait()
	_check(listed_result.ok and listed_result.data is Array, "Typed cloud-save slots can be listed")
	if listed_result.ok:
		var found_typed_slot := false
		for info: CloudSaveInfo in listed_result.data:
			if info.slot == "typed-slot":
				found_typed_slot = true
				_check(info.progress_value == 25, "Provider list metadata is normalized")
		_check(found_typed_slot, "Cloud-save lists expose logical slot names")

	var foreign_bytes := var_to_bytes({"foreign": true})
	await service.save_game("foreign-slot", foreign_bytes).wait()
	var foreign_result: GameServicesResult = await store.load("foreign-slot").wait()
	_check(
		foreign_result.error_code == GameServicesResult.Code.INVALID_DATA,
		"Foreign binary saves are not overwritten or decoded as typed saves"
	)
	var malformed_bytes := var_to_bytes({
		"format": CloudSaveStore.FORMAT_IDENTIFIER,
		"format_version": CloudSaveStore.FORMAT_VERSION,
		"slot": "malformed-slot",
		"schema_version": store.schema_version,
		"revision": "malformed-revision",
		"parent_revisions": 42,
		"saved_at_msec": 1,
		"metadata": {},
		"value": {"coins": 1},
	})
	await service.save_game("malformed-slot", malformed_bytes).wait()
	var malformed_result: GameServicesResult = await store.load("malformed-slot").wait()
	_check(
		malformed_result.error_code == GameServicesResult.Code.INVALID_DATA,
		"Malformed typed envelopes fail without coercing corrupted fields"
	)
	var unsafe_node := Node.new()
	var unsafe_result: GameServicesResult = await store.save(store.create(
		"unsafe-slot",
		{"node": unsafe_node}
	)).wait()
	unsafe_node.free()
	_check(
		unsafe_result.error_code == GameServicesResult.Code.INVALID_ARGUMENT,
		"Typed cloud saves reject object serialization"
	)
	var unsafe_default_node := Node.new()
	var unsafe_default_result: GameServicesResult = await store.load_or_create(
		"unsafe-default-slot",
		{"node": unsafe_default_node}
	).wait()
	unsafe_default_node.free()
	_check(
		unsafe_default_result.error_code == GameServicesResult.Code.INVALID_ARGUMENT,
		"Typed cloud-save defaults use the same serialization rules"
	)

	var default_result: GameServicesResult = await store.load_or_create(
		"new-slot",
		{"coins": 0}
	).wait()
	_check(
		default_result.ok
		and default_result.data is CloudSaveDocument
		and default_result.data.revision.is_empty()
		and default_result.data.value.coins == 0,
		"Missing slots can produce an unsaved default document"
	)

	var deleted_result: GameServicesResult = await store.delete("typed-slot").wait()
	_check(
		deleted_result.ok and deleted_result.data.deleted,
		"Typed cloud saves delete by logical slot instead of provider ID"
	)
	_check(
		finished_request_ids.size() >= 8,
		"The high-level store reports its own completed requests"
	)


func _test_cloud_save_cancellation(service: Node, test_config: GameServicesConfig) -> void:
	var initialized: GameServicesResult = service.initialize(
		test_config,
		PendingCloudSaveProvider.new()
	)
	_check(initialized.ok, "Pending cloud-save provider initializes")
	var document: CloudSaveDocument = service.cloud_saves.create(
		"pending-slot",
		{"coins": 1}
	)
	var request: GameServicesRequest = service.cloud_saves.save(document)
	service.shutdown()
	var result: GameServicesResult = await request.wait()
	_check(
		result.error_code == GameServicesResult.Code.CANCELLED
		and result.provider == &"pending_cloud_save_test",
		"Provider shutdown cancels high-level cloud-save requests"
	)


func _test_cloud_save_conflicts(test_config: GameServicesConfig) -> void:
	var provider := ConflictCloudSaveProvider.new()
	var service := GameServicesScript.new()
	service.auto_initialize = false
	root.add_child(service)
	var initialized := service.initialize(test_config, provider)
	_check(initialized.ok, "Conflict cloud-save provider initializes")
	var store: CloudSaveStore = service.cloud_saves

	var left_result: GameServicesResult = await store.save(store.create(
		"conflict-slot",
		{"coins": 1},
		{"progress_value": 10}
	)).wait()
	var right_result: GameServicesResult = await store.save(store.create(
		"conflict-slot",
		{"coins": 2},
		{"progress_value": 90}
	)).wait()
	_check(left_result.ok and right_result.ok, "Conflict candidates serialize")
	provider.conflict_mode = true

	var manual_result: GameServicesResult = await store.load("conflict-slot").wait()
	_check(
		manual_result.error_code == GameServicesResult.Code.CONFLICT
		and manual_result.data is CloudSaveConflict,
		"Manual conflict policy returns a typed conflict"
	)
	if manual_result.data is not CloudSaveConflict:
		service.shutdown()
		service.queue_free()
		return
	var conflict: CloudSaveConflict = manual_result.data
	_check(conflict.candidates.size() == 2, "Conflict candidates decode")
	_check(conflict.newest().provider_id == "left", "Conflicts can select the newest candidate")
	_check(
		conflict.highest_progress().provider_id == "right",
		"Conflicts can select the highest-progress candidate"
	)

	var resolved_result: GameServicesResult = await store.resolve_with_candidate(
		conflict,
		conflict.highest_progress()
	).wait()
	_check(
		resolved_result.ok
		and resolved_result.data is CloudSaveDocument
		and resolved_result.data.value.coins == 2
		and resolved_result.data.parent_revisions.size() == 2
		and provider.resolved_snapshot_id == "right",
		"Choosing a conflict candidate creates a merge revision"
	)

	store.conflict_policy = CloudSaveStore.ConflictPolicy.NEWEST
	var newest_result: GameServicesResult = await store.load("conflict-slot").wait()
	_check(
		newest_result.ok and newest_result.data.value.coins == 1,
		"Newest conflict policy resolves only when explicitly selected"
	)

	store.conflict_policy = CloudSaveStore.ConflictPolicy.HIGHEST_PROGRESS
	var progress_result: GameServicesResult = await store.load("conflict-slot").wait()
	_check(
		progress_result.ok and progress_result.data.value.coins == 2,
		"Highest-progress conflict policy uses portable envelope metadata"
	)

	store.conflict_policy = CloudSaveStore.ConflictPolicy.CUSTOM
	store.conflict_resolver = Callable(self, "_merge_cloud_save_conflict")
	var merged_result: GameServicesResult = await store.load("conflict-slot").wait()
	_check(
		merged_result.ok
		and merged_result.data.value.coins == 3
		and merged_result.data.progress_value == 100,
		"Custom conflict resolvers can return merged values"
	)

	service.shutdown()
	service.queue_free()


func _migrate_cloud_save_v1(value: Variant) -> Variant:
	var migrated: Dictionary = value.duplicate(true) if value is Dictionary else {}
	migrated["difficulty"] = "normal"
	return migrated


func _merge_cloud_save_conflict(conflict: CloudSaveConflict) -> CloudSaveResolution:
	var coins := 0
	for candidate in conflict.candidates:
		if candidate.is_decoded():
			coins += int(candidate.document.value.get("coins", 0))
	return CloudSaveResolution.merge(
		{"coins": coins},
		conflict.highest_progress(),
		{"progress_value": 100}
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_google_adapter(test_config: GameServicesConfig) -> void:
	var fake := FakeGooglePlayGames.new()
	Engine.register_singleton("GodotPlayGameServices", fake)
	var service := GameServicesScript.new()
	service.auto_initialize = false
	root.add_child(service)

	var initialized := service.initialize(test_config, GooglePlayGamesProvider.new())
	_check(initialized.ok, "Google adapter initializes with its native singleton")
	_check(
		service.supports(service.Capability.CLOUD_SAVES),
		"Patched Google bridge advertises cloud saves"
	)

	var denied_request := service.authenticate()
	fake.userAuthenticated.emit(false)
	var denied: GameServicesResult = await denied_request.wait()
	_check(
		denied.error_code == GameServicesResult.Code.PLATFORM_ERROR,
		"A rejected Google sign-in is not reported as success"
	)

	var auth_request := service.authenticate()
	fake.userAuthenticated.emit(true)
	var authenticated: GameServicesResult = await auth_request.wait()
	_check(authenticated.ok and service.is_authenticated(), "Google sign-in state is normalized")

	var load_achievements_request := service.load_achievements()
	fake.achievementsLoaded.emit(JSON.stringify([{
		"achievementId": "CgkI_first_win",
		"name": "First win",
		"state": "STATE_UNLOCKED",
		"currentSteps": 10,
		"totalSteps": 10,
	}]))
	var achievements: GameServicesResult = await load_achievements_request.wait()
	_check(
		achievements.ok and achievements.data[0].id == "first_win",
		"Google achievement IDs normalize back to logical IDs"
	)

	var bytes := PackedByteArray([1, 2, 3])
	var save_a := service.save_game("slot-a", bytes)
	var save_b := service.save_game("slot-b", bytes)
	fake.gameSaved.emit(true, "slot-b", "")
	fake.gameSaved.emit(true, "slot-a", "")
	var saved_b: GameServicesResult = await save_b.wait()
	var saved_a: GameServicesResult = await save_a.wait()
	_check(
		saved_a.data.id == "slot-a" and saved_b.data.id == "slot-b",
		"Concurrent Google saves are matched by name"
	)

	var failed_load_request := service.load_game("slot-a")
	fake.gameLoaded.emit(JSON.stringify({"error": "offline", "errorCode": 7}), "slot-a")
	var failed_load: GameServicesResult = await failed_load_request.wait()
	_check(
		failed_load.error_code == GameServicesResult.Code.PLATFORM_ERROR
		and failed_load.platform_code == 7,
		"Google snapshot errors preserve native details"
	)

	var conflict_request := service.load_game("slot-a")
	fake.conflictEmitted.emit(JSON.stringify({
		"origin": "LOAD",
		"conflictId": "conflict-1",
		"serverSnapshot": {
			"content": [1, 2],
			"metadata": {"snapshotId": "server", "uniqueName": "slot-a"},
		},
		"conflictingSnapshot": {
			"content": [3, 4],
			"metadata": {"snapshotId": "local", "uniqueName": "slot-a"},
		},
	}))
	var conflict: GameServicesResult = await conflict_request.wait()
	_check(
		conflict.error_code == GameServicesResult.Code.CONFLICT
		and conflict.data.snapshots.size() == 2,
		"Google snapshot conflicts expose both candidates"
	)

	var resolve_request := service.resolve_saved_game_conflict(
		"conflict-1",
		"server",
		bytes
	)
	fake.conflictResolved.emit(true, JSON.stringify({
		"content": [1, 2, 3],
		"metadata": {"snapshotId": "resolved", "uniqueName": "slot-a"},
	}))
	var resolved: GameServicesResult = await resolve_request.wait()
	_check(resolved.ok, "Google snapshot conflicts can be resolved")

	service.shutdown()
	service.queue_free()
	Engine.unregister_singleton("GodotPlayGameServices")
	fake.free()


func _test_apple_adapter(test_config: GameServicesConfig) -> void:
	var fake := FakeGameCenter.new()
	Engine.register_singleton("GameCenter", fake)
	var service := GameServicesScript.new()
	service.auto_initialize = false
	root.add_child(service)

	var initialized := service.initialize(test_config, AppleGameCenterProvider.new())
	_check(initialized.ok, "Apple adapter initializes with its native singleton")
	_check(
		service.supports(service.Capability.CLOUD_SAVES),
		"Patched Apple bridge advertises cloud saves"
	)

	var auth_request := service.authenticate()
	fake.authenticated = true
	fake.push_event({
		"type": "authentication",
		"result": "ok",
		"player_id": "apple-player",
		"displayName": "Apple Player",
		"alias": "Apple",
	})
	service.provider.call("_process", 0.0)
	var authenticated: GameServicesResult = await auth_request.wait()
	_check(
		authenticated.ok and authenticated.data.player.id == "apple-player",
		"Apple player identity is normalized"
	)

	var large_score := 9_007_199_254_740_000
	var high_score_request := service.submit_score(&"high_score", large_score)
	var low_score_request := service.submit_score(&"low_score", 7)
	fake.push_event({
		"type": "post_score",
		"result": "ok",
		"platform_id": "gc.low_score",
	})
	fake.push_event({
		"type": "post_score",
		"result": "ok",
		"platform_id": "gc.high_score",
	})
	service.provider.call("_process", 0.0)
	var low_score: GameServicesResult = await low_score_request.wait()
	var high_score: GameServicesResult = await high_score_request.wait()
	_check(
		high_score.ok and high_score.data.score == large_score,
		"Bundled Apple bridge accepts int64 scores"
	)
	_check(
		low_score.data.id == "low_score" and high_score.data.id == "high_score",
		"Concurrent Apple scores are matched by leaderboard ID"
	)

	var conflict_request := service.load_game("slot-a")
	fake.push_event({
		"type": "load_game",
		"result": "conflict",
		"conflict_id": "apple-conflict",
		"saved_games": [
			{"name": "slot-a", "device_name": "iPhone", "data": PackedByteArray([1])},
			{"name": "slot-a", "device_name": "iPad", "data": PackedByteArray([2])},
		],
	})
	service.provider.call("_process", 0.0)
	var conflict: GameServicesResult = await conflict_request.wait()
	_check(
		conflict.error_code == GameServicesResult.Code.CONFLICT
		and conflict.data.snapshots.size() == 2
		and conflict.data.snapshots[0].has("metadata"),
		"Apple saved-game conflicts expose both candidates"
	)

	var resolve_request := service.resolve_saved_game_conflict(
		"apple-conflict",
		"",
		PackedByteArray([2])
	)
	fake.push_event({
		"type": "resolve_saved_game_conflict",
		"result": "ok",
		"conflict_id": "apple-conflict",
		"saved_games": [{"name": "slot-a"}],
	})
	service.provider.call("_process", 0.0)
	var resolved: GameServicesResult = await resolve_request.wait()
	_check(resolved.ok, "Apple saved-game conflicts can be resolved")

	service.shutdown()
	service.queue_free()
	Engine.unregister_singleton("GameCenter")
	fake.free()
