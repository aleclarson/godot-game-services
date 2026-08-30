package com.jacobibanez.plugin.android.storereview.signals

import org.godotengine.godot.plugin.SignalInfo

object ReviewSignals {
    val reviewFlowCompleted = SignalInfo(
        "reviewFlowCompleted",
        Boolean::class.javaObjectType,
        Int::class.javaObjectType,
        String::class.java
    )
}
