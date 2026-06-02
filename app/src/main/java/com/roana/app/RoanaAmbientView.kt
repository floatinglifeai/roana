// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

package com.roana.app

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import com.roana.app.CorridorPlanner.CorridorCommand

/**
 * Default real-user surface. Near-black, low-power. One large command glyph +
 * colour + speech caption + an "alive" pulse. STOP draws a red edge. Output that
 * matters (speech / haptics) lives elsewhere; this is a glanceable cue.
 */
class RoanaAmbientView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    private var command: CorridorCommand = CorridorCommand.STOP
    private var pulse = 0f

    private val glyphPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    private val captionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#DFE6EE")
        textAlign = Paint.Align.CENTER
    }
    private val pulsePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val edgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }

    private val pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 2400L
        repeatCount = ValueAnimator.INFINITE
        repeatMode = ValueAnimator.REVERSE
        interpolator = LinearInterpolator()
        addUpdateListener { pulse = it.animatedValue as Float; postInvalidateOnAnimation() }
    }

    fun setCommand(next: CorridorCommand) {
        command = next
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        pulseAnimator.start()
    }

    override fun onDetachedFromWindow() {
        pulseAnimator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(RoanaPresentation.AMBIENT_BACKGROUND)
        val style = RoanaPresentation.styleFor(command)
        val cx = width / 2f
        val cy = height / 2f

        // alive pulse ring
        val baseR = dp(80f)
        val r = baseR * (0.82f + 0.23f * pulse)
        pulsePaint.color = style.color
        pulsePaint.alpha = (40 + 60 * pulse).toInt()
        pulsePaint.strokeWidth = dp(2f)
        canvas.drawCircle(cx, cy, r, pulsePaint)

        // glyph
        glyphPaint.color = style.color
        glyphPaint.textSize = dp(96f)
        canvas.drawText(style.glyph, cx, cy + dp(34f), glyphPaint)

        // caption
        captionPaint.textSize = dp(15f)
        canvas.drawText(style.caption, cx, cy + dp(96f), captionPaint)

        // STOP edge
        if (command == CorridorCommand.STOP) {
            edgePaint.color = RoanaPresentation.STOP_EDGE
            edgePaint.alpha = 140
            edgePaint.strokeWidth = dp(6f)
            val i = dp(3f)
            canvas.drawRect(i, i, width - i, height - i, edgePaint)
        }
    }

    private fun dp(v: Float): Float = v * resources.displayMetrics.density
}
