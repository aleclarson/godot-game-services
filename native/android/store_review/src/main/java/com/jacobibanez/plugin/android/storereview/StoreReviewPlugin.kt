package com.jacobibanez.plugin.android.storereview

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.util.Log
import com.google.android.play.core.review.ReviewException
import com.google.android.play.core.review.ReviewInfo
import com.google.android.play.core.review.ReviewManager
import com.google.android.play.core.review.ReviewManagerFactory
import com.jacobibanez.plugin.android.storereview.signals.ReviewSignals.reviewFlowCompleted
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.godotengine.godot.plugin.GodotPlugin.emitSignal

/** Dedicated Godot bridge for native in-app review and store-page flows. */
class StoreReviewPlugin(private val godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val REVIEW_STARTED = 0
        private const val ACTIVITY_UNAVAILABLE = 1
        private const val REQUEST_ALREADY_IN_PROGRESS = 2
        private const val INVALID_STORE_URL = 3
        private const val STORE_HANDLER_UNAVAILABLE = 4
        private const val UNKNOWN_REVIEW_ERROR = -1
    }

    private var reviewInFlight = false

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    override fun getPluginSignals(): MutableSet<SignalInfo> = mutableSetOf(reviewFlowCompleted)

    /**
     * Requests the Play in-app review flow. Completion only means the native
     * flow finished; Play does not report whether a prompt was shown or a
     * review was submitted.
     */
    @UsedByGodot
    fun requestInAppReview(): Int {
        val currentActivity = godot.getActivity() ?: return ACTIVITY_UNAVAILABLE
        if (reviewInFlight) {
            return REQUEST_ALREADY_IN_PROGRESS
        }

        reviewInFlight = true
        try {
            val manager = ReviewManagerFactory.create(currentActivity)
            manager.requestReviewFlow().addOnCompleteListener { requestTask ->
                if (!requestTask.isSuccessful) {
                    finishReview(
                        false,
                        reviewErrorCode(requestTask.exception),
                        requestTask.exception?.message ?: "Play review flow request failed"
                    )
                    return@addOnCompleteListener
                }

                val reviewInfo: ReviewInfo = requestTask.result
                manager.launchReviewFlow(currentActivity, reviewInfo)
                    .addOnCompleteListener { launchTask ->
                        if (launchTask.isSuccessful) {
                            finishReview(true, 0, "")
                        } else {
                            finishReview(
                                false,
                                reviewErrorCode(launchTask.exception),
                                launchTask.exception?.message ?: "Play review flow failed"
                            )
                        }
                    }
            }
        } catch (exception: RuntimeException) {
            finishReview(false, UNKNOWN_REVIEW_ERROR, exception.message ?: "Play review flow failed")
            return UNKNOWN_REVIEW_ERROR
        }
        return REVIEW_STARTED
    }

    /** Opens the configured Play product/review URL through Android. */
    @UsedByGodot
    fun openStoreReviewPage(url: String): Int {
        val trimmedUrl = url.trim()
        if (trimmedUrl.isEmpty()) {
            return INVALID_STORE_URL
        }
        val uri = try {
            Uri.parse(trimmedUrl)
        } catch (_: IllegalArgumentException) {
            return INVALID_STORE_URL
        }
        if (uri.scheme.isNullOrEmpty()) {
            return INVALID_STORE_URL
        }

        val currentActivity: Activity = godot.getActivity() ?: return ACTIVITY_UNAVAILABLE
        val intent = Intent(Intent.ACTION_VIEW, uri)
        if (intent.resolveActivity(currentActivity.packageManager) == null) {
            return STORE_HANDLER_UNAVAILABLE
        }
        return try {
            currentActivity.startActivity(intent)
            0
        } catch (exception: ActivityNotFoundException) {
            Log.w(pluginName, "Could not open store review page", exception)
            STORE_HANDLER_UNAVAILABLE
        }
    }

    private fun finishReview(succeeded: Boolean, errorCode: Int, message: String) {
        reviewInFlight = false
        emitSignal(
            godot,
            BuildConfig.GODOT_PLUGIN_NAME,
            reviewFlowCompleted,
            succeeded,
            errorCode,
            message
        )
    }

    private fun reviewErrorCode(exception: Exception?): Int =
        (exception as? ReviewException)?.errorCode ?: UNKNOWN_REVIEW_ERROR
}
