// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

package com.roana.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

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

    enum class Layer {
        CAMERA,
        DEPTH,
        PATH,
        DETECTIONS,
        TELEMETRY,
    }

    data class Settings(
        val showCameraUnderlay: Boolean = false,
        val showDepth: Boolean = true,
        val showPath: Boolean = true,
        val showDetections: Boolean = true,
        val showTelemetry: Boolean = true,
    ) {
        fun toggled(layer: Layer): Settings = when (layer) {
            Layer.CAMERA -> copy(showCameraUnderlay = !showCameraUnderlay)
            Layer.DEPTH -> copy(showDepth = !showDepth)
            Layer.PATH -> copy(showPath = !showPath)
            Layer.DETECTIONS -> copy(showDetections = !showDetections)
            Layer.TELEMETRY -> copy(showTelemetry = !showTelemetry)
        }

        fun enabled(layer: Layer): Boolean = when (layer) {
            Layer.CAMERA -> showCameraUnderlay
            Layer.DEPTH -> showDepth
            Layer.PATH -> showPath
            Layer.DETECTIONS -> showDetections
            Layer.TELEMETRY -> showTelemetry
        }
    }

    private var frame: PresentationFrame? = null
    private var settings = Settings()
    private val controlBounds = mutableMapOf<Layer, RectF>()

    private val cellPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val gridLinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#334456")
        strokeWidth = 1f
    }
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
    private val hitScratch = RectF()

    fun setSettings(next: Settings) {
        settings = next
        postInvalidateOnAnimation()
    }

    fun setFrame(next: PresentationFrame) {
        frame = next
        postInvalidateOnAnimation()
    }

    fun hitControl(x: Float, y: Float): Layer? =
        controlBounds.entries.firstOrNull { (_, bounds) -> bounds.contains(x, y) }?.key

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(
            if (settings.showCameraUnderlay) {
                RoanaPresentation.HUD_CAMERA_SCRIM
            } else {
                RoanaPresentation.HUD_BACKGROUND
            },
        )
        val f = frame ?: return

        val w = width.toFloat()
        val teleH = if (settings.showTelemetry) dp(40f) else 0f
        val topH = dp(40f)
        val railW = dp(72f)
        val gridLeft = railW
        val gridW = (w - gridLeft).coerceAtLeast(1f)
        val gridTop = topH
        val gridBottom = height - teleH
        val gridH = gridBottom - gridTop
        val grid = RoanaPresentation.GRID
        val cw = gridW / grid
        val ch = gridH / grid
        val gap = dp(1.2f)
        drawLayerControls(canvas, railW)

        // 1) depth heatmap
        if (settings.showDepth) {
            for (r in 0 until grid) {
                for (c in 0 until grid) {
                    cellPaint.color = RoanaPresentation.depthColor(f.depthAt(r, c))
                    cellPaint.alpha = if (settings.showCameraUnderlay) 145 else 255
                    val x = gridLeft + c * cw
                    val y = gridTop + r * ch
                    canvas.drawRect(x + gap / 2, y + gap / 2, x + cw - gap / 2, y + ch - gap / 2, cellPaint)
                }
            }
            cellPaint.alpha = 255
        } else if (!settings.showCameraUnderlay) {
            for (r in 0..grid) {
                val y = gridTop + r * ch
                canvas.drawLine(gridLeft, y, w, y, gridLinePaint)
            }
            for (c in 0..grid) {
                val x = gridLeft + c * cw
                canvas.drawLine(x, gridTop, x, gridBottom, gridLinePaint)
            }
        }

        val style = RoanaPresentation.styleFor(f.command)

        // 2) corridor path ribbon (bottom-center -> target column)
        if (settings.showPath) {
            pathPaint.color = style.color
            pathPaint.strokeWidth = dp(3.2f)
            val targetX = gridLeft + (style.pathTargetCol + 0.5f) * cw
            val path = Path().apply {
                moveTo(gridLeft + gridW / 2f, gridBottom)
                quadTo(gridLeft + gridW / 2f, gridTop + gridH * 0.62f, targetX, gridTop + gridH * 0.30f)
            }
            canvas.drawPath(path, pathPaint)
        }

        // 3) detection boxes
        textPaint.textSize = dp(11f)
        if (settings.showDetections) {
            for (d in f.detections) {
                val bw = d.width * gridW
                val bh = d.height * gridH
                val bx = gridLeft + d.centerX * gridW - bw / 2
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
        }

        // 4) command chip (top-left)
        chipPaint.color = style.color
        textPaint.textSize = dp(14f)
        val chipLabel = "${style.glyph} ${f.command.name}"
        val chipW = textPaint.measureText(chipLabel) + dp(18f)
        val chipX = gridLeft + dp(8f)
        canvas.drawRoundRect(chipX, dp(6f), chipX + chipW, dp(28f), dp(6f), dp(6f), chipPaint)
        textPaint.color = Color.parseColor("#04150F")
        canvas.drawText(chipLabel, chipX + dp(9f), dp(22f), textPaint)
        textPaint.color = Color.WHITE
        if (f.source == PresentationFrame.Source.DEMO) {
            drawDemoChip(canvas, chipX + chipW + dp(6f), dp(6f))
        }

        // 5) telemetry strip
        if (settings.showTelemetry) {
            val tele = f.telemetry()
            val colW = gridW / tele.size
            textPaint.textAlign = Paint.Align.CENTER
            tele.forEachIndexed { i, (k, v) ->
                val cx = gridLeft + colW * i + colW / 2
                dimPaint.textSize = dp(7.5f)
                dimPaint.textAlign = Paint.Align.CENTER
                canvas.drawText(k, cx, gridBottom + dp(15f), dimPaint)
                textPaint.textSize = dp(13f)
                canvas.drawText(v, cx, gridBottom + dp(30f), textPaint)
            }
            textPaint.textAlign = Paint.Align.LEFT
        }
    }

    private fun drawLayerControls(canvas: Canvas, railW: Float) {
        controlBounds.clear()
        val controls = listOf(
            RoanaHudControl("CAM", Layer.CAMERA),
            RoanaHudControl("DEPTH", Layer.DEPTH),
            RoanaHudControl("PATH", Layer.PATH),
            RoanaHudControl("BOX", Layer.DETECTIONS),
            RoanaHudControl("TEL", Layer.TELEMETRY),
        )
        chipPaint.color = Color.parseColor("#090D12")
        canvas.drawRect(0f, 0f, railW, height.toFloat(), chipPaint)
        val x = dp(8f)
        var y = dp(56f)
        val chipW = railW - dp(16f)
        val chipH = dp(30f)
        textPaint.textAlign = Paint.Align.CENTER
        textPaint.textSize = dp(10.5f)
        for (control in controls) {
            val visualRect = RectF(x, y, x + chipW, y + chipH)
            hitScratch.set(x - dp(4f), y - dp(4f), x + chipW + dp(4f), y + chipH + dp(4f))
            controlBounds[control.layer] = RectF(hitScratch)
            val enabled = settings.enabled(control.layer)
            chipPaint.color = if (enabled) Color.parseColor("#CFE7D2") else Color.parseColor("#27313B")
            canvas.drawRoundRect(visualRect, dp(7f), dp(7f), chipPaint)
            textPaint.color = if (enabled) Color.parseColor("#06140A") else Color.parseColor("#AAB3BD")
            canvas.drawText(control.label, visualRect.centerX(), visualRect.top + dp(19.5f), textPaint)
            y = visualRect.bottom + dp(8f)
        }
        textPaint.textAlign = Paint.Align.LEFT
        textPaint.color = Color.WHITE
    }

    private fun drawDemoChip(canvas: Canvas, x: Float, y: Float) {
        textPaint.textSize = dp(10f)
        val label = "DEMO"
        val w = textPaint.measureText(label) + dp(16f)
        chipPaint.color = Color.parseColor("#FFD166")
        canvas.drawRoundRect(x, y, x + w, y + dp(22f), dp(6f), dp(6f), chipPaint)
        textPaint.color = Color.parseColor("#1C1400")
        canvas.drawText(label, x + dp(8f), y + dp(15.5f), textPaint)
        textPaint.color = Color.WHITE
    }

    private fun dp(v: Float): Float = v * resources.displayMetrics.density

    private data class RoanaHudControl(
        val label: String,
        val layer: Layer,
    )
}
