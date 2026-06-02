// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

package com.roana.app

import com.roana.app.CorridorPlanner.CorridorCommand
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Presentation parity guard. Pins the in-code command styles to fixed values and
 * confirms the same literals live in the shared source of truth
 * (parity/presentation-core.json). Catches drift between the JSON and the
 * Android mirror without needing the app runtime. CWD is the module dir, so the
 * fixture sits one level up (see PrivacyBoundaryTest for the same convention).
 */
class PresentationContractTest {

    private val contract: String = File("../parity/presentation-core.json").readText()

    private fun hex(color: Int): String = "#%06X".format(color and 0xFFFFFF)

    @Test
    fun commandStylesMatchTheSharedContract() {
        val expected = mapOf(
            CorridorCommand.STRAIGHT to Triple("↑", "#62E08A", "Go straight"),
            CorridorCommand.LEFT to Triple("←", "#5CC8FF", "Turn left"),
            CorridorCommand.RIGHT to Triple("→", "#C89BFF", "Turn right"),
            CorridorCommand.STOP to Triple("■", "#FF5563", "Stop"),
        )
        for ((cmd, e) in expected) {
            val (glyph, colorHex, caption) = e
            val style = RoanaPresentation.styleFor(cmd)
            assertEquals("glyph for $cmd", glyph, style.glyph)
            assertEquals("color for $cmd", colorHex, hex(style.color))
            assertEquals("caption for $cmd", caption, style.caption)
            assertTrue("$colorHex missing from presentation-core.json", contract.contains(colorHex))
            assertTrue("\"$caption\" missing from presentation-core.json", contract.contains(caption))
            assertTrue("glyph $glyph missing from presentation-core.json", contract.contains(glyph))
        }
    }

    @Test
    fun gridAndThresholdsComeFromCorridorContract() {
        assertEquals(CorridorContract.GRID_SIZE, RoanaPresentation.GRID)
        assertEquals(CorridorContract.SAFE_CELL_DEPTH, RoanaPresentation.SAFE_DEPTH, 0f)
        assertEquals(CorridorContract.NEAR_OBSTACLE_DEPTH, RoanaPresentation.NEAR_DEPTH, 0f)
        assertTrue(contract.contains("\"size\": ${CorridorContract.GRID_SIZE}"))
    }

    @Test
    fun telemetryOrderMatchesContract() {
        val frame = PresentationFrame(
            command = CorridorCommand.STRAIGHT,
            reason = "path_found",
            depth = FloatArray(RoanaPresentation.GRID * RoanaPresentation.GRID) { 0.2f },
            depthCols = RoanaPresentation.GRID,
            detections = emptyList(),
            frames = 10,
            yoloMs = 20.0,
            depthMs = 12.0,
            gaps = 0,
        )
        assertEquals(
            listOf("FRM", "YOLO ms", "DEPTH ms", "GAPS"),
            frame.telemetry().map { it.first },
        )
    }
}
