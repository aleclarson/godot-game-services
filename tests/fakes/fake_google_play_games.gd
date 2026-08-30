extends Node

signal userAuthenticated(authenticated: bool)
signal currentPlayerLoaded(player_json: String)
signal achievementUnlocked(unlocked: bool, achievement_id: String)
signal achievementsLoaded(achievements_json: String)
signal scoreSubmitted(submitted: bool, leaderboard_id: String)
signal serverSideAccessRequested(token: String)
signal gameSaved(saved: bool, name: String, description: String)
signal gameLoaded(snapshot_json: String, name: String)
signal conflictEmitted(conflict_json: String)
signal conflictResolved(resolved: bool, payload_json: String)
signal snapshotsLoaded(snapshots_json: String)
signal snapshotDeleted(deleted: bool, snapshot_id: String)

var calls: Array[Dictionary] = []
var java_method_checks: Array[StringName] = []


func initialize() -> void:
	_record("initialize")


func has_java_method(method: StringName) -> bool:
	java_method_checks.append(method)
	return has_method(method)


func isAuthenticated() -> void:
	_record("isAuthenticated")


func signIn() -> void:
	_record("signIn")


func loadCurrentPlayer(force_reload: bool) -> void:
	_record("loadCurrentPlayer", [force_reload])


func unlockAchievement(achievement_id: String) -> void:
	_record("unlockAchievement", [achievement_id])


func setAchievementSteps(achievement_id: String, steps: int) -> void:
	_record("setAchievementSteps", [achievement_id, steps])


func loadAchievements(force_reload: bool) -> void:
	_record("loadAchievements", [force_reload])


func submitScore(leaderboard_id: String, score: int) -> void:
	_record("submitScore", [leaderboard_id, score])


func showAchievements() -> void:
	_record("showAchievements")


func showAllLeaderboards() -> void:
	_record("showAllLeaderboards")


func showLeaderboard(leaderboard_id: String) -> void:
	_record("showLeaderboard", [leaderboard_id])


func requestServerSideAccess(client_id: String, force_refresh: bool) -> void:
	_record("requestServerSideAccess", [client_id, force_refresh])


func saveGame(
	name: String,
	description: String,
	data: PackedByteArray,
	played_time_msec: int,
	progress_value: int
) -> void:
	_record("saveGame", [name, description, data, played_time_msec, progress_value])


func loadGame(name: String, create_if_missing: bool) -> void:
	_record("loadGame", [name, create_if_missing])


func loadSnapshots(force_reload: bool) -> void:
	_record("loadSnapshots", [force_reload])


func deleteSnapshot(snapshot_id: String) -> void:
	_record("deleteSnapshot", [snapshot_id])


func resolveSnapshotConflict(
	conflict_id: String,
	snapshot_id: String,
	data: PackedByteArray,
	description: String,
	played_time_msec: int,
	progress_value: int
) -> void:
	_record("resolveSnapshotConflict", [
		conflict_id,
		snapshot_id,
		data,
		description,
		played_time_msec,
		progress_value,
	])


func _record(method: String, arguments: Array = []) -> void:
	calls.append({"method": method, "arguments": arguments})
