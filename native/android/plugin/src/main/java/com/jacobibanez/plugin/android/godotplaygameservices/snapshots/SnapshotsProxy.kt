package com.jacobibanez.plugin.android.godotplaygameservices.snapshots

import android.app.Activity
import android.content.Intent
import android.util.Log
import androidx.core.app.ActivityCompat
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.SnapshotsClient
import com.google.android.gms.games.SnapshotsClient.EXTRA_SNAPSHOT_METADATA
import com.google.android.gms.games.SnapshotsClient.RESOLUTION_POLICY_HIGHEST_PROGRESS
import com.google.android.gms.games.SnapshotsClient.RESOLUTION_POLICY_MOST_RECENTLY_MODIFIED
import com.google.android.gms.games.SnapshotsClient.SnapshotConflict
import com.google.android.gms.games.snapshot.SnapshotMetadata
import com.google.android.gms.games.snapshot.SnapshotMetadataChange
import com.google.gson.Gson
import com.jacobibanez.plugin.android.godotplaygameservices.BuildConfig.GODOT_PLUGIN_NAME
import com.jacobibanez.plugin.android.godotplaygameservices.signals.SnapshotSignals.conflictEmitted
import com.jacobibanez.plugin.android.godotplaygameservices.signals.SnapshotSignals.conflictResolved
import com.jacobibanez.plugin.android.godotplaygameservices.signals.SnapshotSignals.snapshotDeleted
import com.jacobibanez.plugin.android.godotplaygameservices.signals.SnapshotSignals.gameLoaded
import com.jacobibanez.plugin.android.godotplaygameservices.signals.SnapshotSignals.gameSaved
import com.jacobibanez.plugin.android.godotplaygameservices.signals.SnapshotSignals.snapshotsLoaded
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin.emitSignal

private enum class Origin {
    SAVE, LOAD, RESOLVE
}

class SnapshotsProxy(
    private val godot: Godot,
    private val snapshotsClient: SnapshotsClient = PlayGames.getSnapshotsClient(godot.getActivity()!!)
) {
    private val tag = SnapshotsProxy::class.java.simpleName

    private val showSavedGamesRequestCode = 9010
    private val snapshotNotFoundCode = 26570
    private val pendingConflicts = mutableMapOf<String, SnapshotConflict>()

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == showSavedGamesRequestCode && resultCode == Activity.RESULT_OK) {
            data?.let { intent ->
                if (intent.hasExtra(EXTRA_SNAPSHOT_METADATA)) {
                    val snapshotMetadata = intent.extras
                        ?.get(EXTRA_SNAPSHOT_METADATA) as SnapshotMetadata
                    loadGame(snapshotMetadata.uniqueName, false)
                }
            }
        }
    }

    fun showSavedGames(
        title: String,
        allowAddButton: Boolean,
        allowDelete: Boolean,
        maxSnapshots: Int
    ) {
        Log.d(tag, "Showing save games")
        snapshotsClient.getSelectSnapshotIntent(title, allowAddButton, allowDelete, maxSnapshots)
            .addOnSuccessListener { intent ->
                ActivityCompat.startActivityForResult(
                    godot.getActivity()!!, intent,
                    showSavedGamesRequestCode, null
                )
            }
    }

    fun saveGame(
        fileName: String,
        description: String,
        saveData: ByteArray,
        playedTimeMillis: Long,
        progressValue: Long
    ) {
        Log.d(tag, "Saving game data with name $fileName and description ${description}.")
        snapshotsClient.open(fileName, true, RESOLUTION_POLICY_HIGHEST_PROGRESS)
            .addOnSuccessListener { dataOrConflict ->
                if (dataOrConflict.isConflict) {
                    handleConflict(Origin.SAVE.name, dataOrConflict.conflict)
                    return@addOnSuccessListener
                }
                dataOrConflict.data?.let { snapshot ->
                    snapshot.snapshotContents.writeBytes(saveData)
                    val metadata = SnapshotMetadataChange.Builder().apply {
                        setDescription(description)
                        setPlayedTimeMillis(playedTimeMillis)
                        setProgressValue(progressValue)
                    }.build()

                    snapshotsClient.commitAndClose(snapshot, metadata)
                        .addOnCompleteListener { task ->
                            if (!task.isSuccessful) {
                                Log.e(tag, "Failed to commit snapshot $fileName", task.exception)
                            }
                            emitSaveResult(task.isSuccessful, fileName, description)
                        }
                } ?: emitSaveResult(false, fileName, description)
            }
            .addOnFailureListener { error ->
                Log.e(tag, "Failed to open snapshot $fileName for saving", error)
                emitSaveResult(false, fileName, description)
            }
    }

    fun loadGame(fileName: String, createIfNotFound: Boolean) {
        Log.d(tag, "Loading snapshot with name $fileName.")
        snapshotsClient.open(fileName, createIfNotFound, RESOLUTION_POLICY_MOST_RECENTLY_MODIFIED)
            .addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    val dataOrConflict = task.result
                    if (dataOrConflict.isConflict) {
                        handleConflict(Origin.LOAD.name, dataOrConflict.conflict)
                        return@addOnCompleteListener
                    }
                    dataOrConflict.data?.let { snapshot ->
                        emitSignal(
                            godot,
                            GODOT_PLUGIN_NAME,
                            gameLoaded,
                            Gson().toJson(fromSnapshot(godot, snapshot)),
                            fileName
                        )
                    } ?: emitLoadError(fileName, "No snapshot returned")
                } else {
                    val exception = task.exception
                    Log.e(
                        tag,
                        "Error while opening Snapshot $fileName for loading. Cause: $exception"
                    )
                    if (exception is ApiException && exception.statusCode == snapshotNotFoundCode) {
                        emitSignal(
                            godot,
                            GODOT_PLUGIN_NAME,
                            gameLoaded,
                            Gson().toJson(null),
                            fileName
                        )
                    } else {
                        emitLoadError(
                            fileName,
                            exception?.message ?: "Failed to open snapshot",
                            (exception as? ApiException)?.statusCode
                        )
                    }
                }
            }
    }

    fun loadSnapshots(forceReload: Boolean) {
        Log.d(tag, "Loading snapshots")
        snapshotsClient.load(forceReload).addOnCompleteListener { task ->
            if (task.isSuccessful) {
                Log.d(
                    tag,
                    "Snapshots loaded successfully. Data is stale? ${task.result.isStale}"
                )
                val snapshots = task.result.get()!!
                val result: List<Dictionary> = snapshots.map { snapshotMetadata ->
                    fromSnapshotMetadata(godot, snapshotMetadata)
                }.toList()
                snapshots.release()
                emitSignal(
                    godot,
                    GODOT_PLUGIN_NAME,
                    snapshotsLoaded,
                    Gson().toJson(result)
                )
            } else {
                Log.e(
                    tag,
                    "Failed to load snapshots. Cause: ${task.exception}",
                    task.exception
                )
                emitSignal(
                    godot,
                    GODOT_PLUGIN_NAME,
                    snapshotsLoaded,
                    Gson().toJson(mapOf("error" to (task.exception?.message ?: "Failed to load snapshots")))
                )
            }
        }
    }

    fun deleteSnapshot(snapshotId: String) {
        Log.d(tag, "Attempting to delete snapshot with id: $snapshotId")
        snapshotsClient.load(true)
            .addOnSuccessListener { annotatedData ->
                annotatedData.get()?.let { buffer ->
                    val snapshotMetadata = buffer.toList()
                        .firstOrNull { it.snapshotId == snapshotId }

                    if (snapshotMetadata != null) {
                        performDelete(snapshotMetadata)
                    } else {
                        Log.w(tag, "Snapshot with id $snapshotId not found")
                        emitDeleteResult(false, snapshotId)
                    }
                }
            }
            .addOnFailureListener { e ->
                Log.e(tag, "Failed to load snapshots before delete", e)
                emitDeleteResult(false, snapshotId)
            }
    }

    fun resolveConflict(
        conflictId: String,
        snapshotId: String,
        resolutionData: ByteArray,
        description: String,
        playedTimeMillis: Long,
        progressValue: Long
    ) {
        val conflict = pendingConflicts[conflictId]
        if (conflict == null) {
            emitConflictResolution(false, mapOf("error" to "Unknown conflict ID"))
            return
        }

        val contents = conflict.resolutionSnapshotContents
        contents.writeBytes(resolutionData)
        val metadata = SnapshotMetadataChange.Builder().apply {
            setDescription(description)
            setPlayedTimeMillis(playedTimeMillis)
            setProgressValue(progressValue)
        }.build()

        snapshotsClient.resolveConflict(
            conflictId,
            snapshotId,
            metadata,
            contents
        ).addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                emitConflictResolution(
                    false,
                    mapOf("error" to (task.exception?.message ?: "Conflict resolution failed"))
                )
                return@addOnCompleteListener
            }

            val result = task.result
            if (result.isConflict) {
                pendingConflicts.remove(conflictId)
                handleConflict(Origin.RESOLVE.name, result.conflict)
                return@addOnCompleteListener
            }

            pendingConflicts.remove(conflictId)
            result.data?.let { snapshot ->
                val mapped = fromSnapshot(godot, snapshot)
                snapshotsClient.discardAndClose(snapshot)
                emitConflictResolution(true, mapped)
            } ?: emitConflictResolution(false, mapOf("error" to "No resolved snapshot returned"))
        }
    }

    private fun emitConflictResolution(success: Boolean, payload: Any) {
        emitSignal(
            godot,
            GODOT_PLUGIN_NAME,
            conflictResolved,
            success,
            Gson().toJson(payload)
        )
    }

    private fun emitSaveResult(success: Boolean, fileName: String, description: String) {
        emitSignal(
            godot,
            GODOT_PLUGIN_NAME,
            gameSaved,
            success,
            fileName,
            description
        )
    }

    private fun emitLoadError(fileName: String, message: String, errorCode: Int? = null) {
        val payload = mutableMapOf<String, Any>(
            "error" to message,
            "name" to fileName
        )
        errorCode?.let { payload["errorCode"] = it }
        emitSignal(
            godot,
            GODOT_PLUGIN_NAME,
            gameLoaded,
            Gson().toJson(payload),
            fileName
        )
    }

    private fun performDelete(metadata: SnapshotMetadata) {
        snapshotsClient.delete(metadata)
            .addOnSuccessListener { deletedSnapshotId ->
                Log.d(tag, "Successfully deleted snapshot: $deletedSnapshotId")
                emitDeleteResult(true, deletedSnapshotId)
            }
            .addOnFailureListener { e ->
                Log.e(tag, "Failed to delete snapshot ${metadata.snapshotId}", e)
                emitDeleteResult(false, metadata.snapshotId)
            }
    }

    private fun emitDeleteResult(success: Boolean, snapshotId: String) {
        emitSignal(
            godot,
            GODOT_PLUGIN_NAME,
            snapshotDeleted,
            success,
            snapshotId
        )
    }

    private fun handleConflict(origin: String, conflict: SnapshotConflict?) {
        conflict?.let {
            pendingConflicts[it.conflictId] = it
            val snapshot = it.snapshot
            val fileName = snapshot.metadata.uniqueName
            val description = snapshot.metadata.description
            Log.e(
                tag, "Conflict with id ${conflict.conflictId} during saving of data with " +
                        "name $fileName and description ${description}."
            )
            emitSignal(
                godot,
                GODOT_PLUGIN_NAME,
                conflictEmitted,
                Gson().toJson(fromConflict(godot, origin, it))
            )
        }
    }
}
