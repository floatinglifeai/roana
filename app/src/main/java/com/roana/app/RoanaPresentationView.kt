// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

package com.roana.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout

/**
 * Single view Roana mounts over the camera. Holds the ambient (default) and
 * debug HUD surfaces and toggles between them on a 2s bottom-right corner
 * long-press. Mode is NOT persisted; every launch starts in ambient.
 *
 * Usage in MainActivity.setupUi():
 *   presentationView = RoanaPresentationView(this)
 *   frame.addView(presentationView)               // above the (optional) PreviewView
 * Per-frame in TimingAnalyzer onStats/onCorridorState:
 *   presentationView.submit(PresentationFrame.from(...))
 */
class RoanaPresentationView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    enum class Mode { AMBIENT, DEBUG }

    private val ambient = RoanaAmbientView(context)
    private val hud = RoanaHudView(context)
    private var mode = Mode.AMBIENT
    private var hudSettings = RoanaHudView.Settings()

    private val handler = Handler(Looper.getMainLooper())
    private var holdRunnable: Runnable? = null
    private var holdTriggered = false

    init {
        addView(ambient, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(hud, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        hud.setSettings(hudSettings)
        applyMode()
    }

    fun submit(frame: PresentationFrame) {
        ambient.setCommand(frame.command)
        hud.setFrame(frame)
    }

    private fun applyMode() {
        ambient.visibility = if (mode == Mode.AMBIENT) View.VISIBLE else View.GONE
        hud.visibility = if (mode == Mode.DEBUG) View.VISIBLE else View.GONE
    }

    private fun toggleMode() {
        mode = if (mode == Mode.AMBIENT) Mode.DEBUG else Mode.AMBIENT
        applyMode()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val region = RoanaPresentation.GESTURE_REGION_DP * resources.displayMetrics.density
        val inCorner = event.x >= width - region && event.y >= height - region
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                holdTriggered = false
                if (inCorner) {
                    holdRunnable = Runnable {
                        holdTriggered = true
                        toggleMode()
                        holdRunnable = null
                    }
                    handler.postDelayed(holdRunnable!!, RoanaPresentation.GESTURE_HOLD_MS)
                    return true
                }
                if (mode == Mode.DEBUG && hud.hitControl(event.x, event.y) != null) {
                    return true
                }
            }
            MotionEvent.ACTION_MOVE -> if (!inCorner) cancelHold()
            MotionEvent.ACTION_UP -> {
                cancelHold()
                if (!holdTriggered && mode == Mode.DEBUG) {
                    hud.hitControl(event.x, event.y)?.let { layer ->
                        hudSettings = hudSettings.toggled(layer)
                        hud.setSettings(hudSettings)
                        return true
                    }
                }
            }
            MotionEvent.ACTION_CANCEL -> cancelHold()
        }
        return super.onTouchEvent(event)
    }

    private fun cancelHold() {
        holdRunnable?.let { handler.removeCallbacks(it) }
        holdRunnable = null
    }
}
