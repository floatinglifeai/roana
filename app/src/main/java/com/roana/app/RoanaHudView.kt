// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

package com.roana.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View
import kotlin.math.min

/**
 * Developer / testing surface. Renders what the system sees:
 * depth heatmap (aligned to the planner grid) + detection box + corridor path +
 * command chip + telemetry strip. Camera frame is intentionally NOT drawn here;
 * a dim camera underlay can be layered behind this view when debugging.
 */
class RoanaHudView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    private var frame: PresentationFrame? = null

    private val cellPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val pathPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val boxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = RoanaPresentation.DETECTION_STROKE
        pathEffect = DashPathEffect(floatArrayOf(14f, 9f), 0f)
    }
    private val chipPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        isFakeBoldText = true
    }
    private val dimPaint = Paint().apply { color = Color.parseColor("#7C8696") }

    fun setFrame(next: PresentationFrame) {
        frame = next
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(RoanaPresentation.HUD_BACKGROUND)
        val f = frame ?: return

        val w = width.toFloat()
        val teleH = dp(40f)
        val topH = dp(34f)
        val gridTop = topH
        val gridBottom = height - teleH
        val gridH = gridBottom - gridTop
        val grid = RoanaPresentation.GRID
        val cw = w / grid
        val ch = gridH / grid
        val gap = dp(1.2f)

        // 1) depth heatmap
        for (r in 0 until grid) {
            for (c in 0 until grid) {
                cellPaint.color = RoanaPresentation.depthColor(f.depthAt(r, c))
                val x = c * cw
                val y = gridTop + r * ch
                canvas.drawRect(x + gap / 2, y + gap / 2, x + cw - gap / 2, y + ch - gap / 2, cellPaint)
            }
        }

        val style = RoanaPresentation.styleFor(f.command)

        // 2) corridor path ribbon (bottom-center -> target column)
        pathPaint.color = style.color
        pathPaint.strokeWidth = dp(3.2f)
        val targetX = (style.pathTargetCol + 0.5f) * cw
        val path = Path().apply {
            moveTo(w / 2f, gridBottom)
            quadTo(w / 2f, gridTop + gridH * 0.62f, targetX, gridTop + gridH * 0.30f)
        }
        canvas.drawPath(path, pathPaint)

        // 3) detection boxes
        textPaint.textSize = dp(11f)
        for (d in f.detections) {
            val bw = d.width * w
            val bh = d.height * gridH
            val bx = d.centerX * w - bw / 2
            val by = gridTop + d.centerY * gridH - bh / 2
            canvas.drawRect(bx, by, bx + bw, by + bh, boxPaint)
            val label = "${d.label} ${"%.2f".format(d.score)}"
            val tw = textPaint.measureText(label)
            chipPaint.color = RoanaPresentation.DETECTION_STROKE
            canvas.drawRect(bx, by - dp(15f), bx + tw + dp(10f), by, chipPaint)
            textPaint.color = Color.parseColor("#04201C")
            canvas.drawText(label, bx + dp(5f), by - dp(4f), textPaint)
            textPaint.color = Color.WHITE
        }

        // 4) command chip (top-left)
        chipPaint.color = style.color
        textPaint.textSize = dp(14f)
        val chipLabel = "${style.glyph} ${f.command.name}"
        val chipW = textPaint.measureText(chipLabel) + dp(18f)
        canvas.drawRoundRect(dp(8f), dp(6f), dp(8f) + chipW, dp(28f), dp(6f), dp(6f), chipPaint)
        textPaint.color = Color.parseColor("#04150F")
        canvas.drawText(chipLabel, dp(17f), dp(22f), textPaint)
        textPaint.color = Color.WHITE

        // 5) telemetry strip
        val tele = f.telemetry()
        val colW = w / tele.size
        textPaint.textAlign = Paint.Align.CENTER
        tele.forEachIndexed { i, (k, v) ->
            val cx = colW * i + colW / 2
            dimPaint.textSize = dp(7.5f)
            dimPaint.textAlign = Paint.Align.CENTER
            canvas.drawText(k, cx, gridBottom + dp(15f), dimPaint)
            textPaint.textSize = dp(13f)
            canvas.drawText(v, cx, gridBottom + dp(30f), textPaint)
        }
        textPaint.textAlign = Paint.Align.LEFT
    }

    private fun dp(v: Float): Float = v * resources.displayMetrics.density
}
