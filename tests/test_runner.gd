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


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := GameServicesScript.new()
	service.auto_initialize = false
	root.add_child(service)

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

	service.shutdown()
	service.queue_free()

	await _test_google_adapter(test_config)
	await _test_apple_adapter(test_config)

	if _failures.is_empty():
		print("PASS: all game-services tests")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: %s" % failure)
		quit(1)


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
