// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

package com.roana.app.parity

import com.roana.app.CorridorGridFusion
import com.roana.app.CorridorPlanner
import com.roana.app.CorridorStateMachine
import com.roana.app.YoloObstacleDetector
import java.nio.file.Path
import kotlin.io.path.createDirectories
import kotlin.io.path.writeText

object CorridorParityFixtureGenerator {
    @JvmStatic
    fun main(args: Array<String>) {
        val outputPath = args.firstOrNull()?.let(Path::of)
            ?: Path.of("parity", "corridor-core.json")
        outputPath.parent?.createDirectories()
        outputPath.writeText(generate(), Charsets.UTF_8)
        println("wrote ${outputPath.toAbsolutePath()}")
    }

    fun generate(): String {
        val cases = buildList {
            add(plannerCase("choosesStraightForCenteredOpenCorridor", listOf(7, 7, 7, 7, 7, 7, 7, 7, 7)))
            add(plannerCase("choosesLeftForLeftBiasedCorridor", listOf(7, 7, 7, 6, 5, 5, 4, 4, 4)))
            add(plannerCase("choosesRightForRightBiasedCorridor", listOf(7, 7, 7, 8, 9, 9, 10, 10, 10)))
            add(allSafePlannerCase())
            add(nearObstaclePlannerCase())
            add(stateMachineConfirmationsCase())
            add(stateMachineFrameLossCase())
            add(fusionNearObstacleCase())
        }

        return buildString {
            appendLine("{")
            appendLine("  \"schema\": 1,")
            appendLine("  \"source\": \"app/src/test/java/com/roana/app/parity/CorridorParityFixtureGenerator.kt\",")
            appendLine("  \"cases\": [")
            cases.forEachIndexed { index, caseJson ->
                append(caseJson.prependIndent("    "))
                if (index != cases.lastIndex) {
                    appendLine(",")
                } else {
                    appendLine()
                }
            }
            appendLine("  ]")
            appendLine("}")
        }
    }

    private fun plannerCase(name: String, colsFromBottom: List<Int>): String {
        val decision = CorridorPlanner().decide(CorridorPlanner.DepthGrid.square15(carvedCorridor(colsFromBottom)))
        return """
{
  "name": "$name",
  "type": "planner",
  "grid": {
    "kind": "carvedCorridor",
    "colsFromBottom": ${colsFromBottom.toJsonArray()}
  },
  "expected": {
    "command": "${decision.command}",
    "reason": "${decision.reason}",
    "minPathCells": 6
  }
}""".trimIndent()
    }

    private fun allSafePlannerCase(): String {
        val decision = CorridorPlanner().decide(
            CorridorPlanner.DepthGrid.square15(FloatArray(GRID_SIZE * GRID_SIZE) { 0.30f }),
        )
        return """
{
  "name": "choosesStraightQuicklyWhenEveryCellIsSafe",
  "type": "planner",
  "grid": {
    "kind": "filled",
    "value": 0.30
  },
  "expected": {
    "command": "${decision.command}",
    "reason": "${decision.reason}",
    "pathCells": ${decision.path.size}
  }
}""".trimIndent()
    }

    private fun nearObstaclePlannerCase(): String {
        val colsFromBottom = listOf(7, 7, 7, 7, 7, 7, 7, 7, 7)
        val grid = carvedCorridor(colsFromBottom)
        grid[index(row = 12, col = 7)] = 0.95f
        val decision = CorridorPlanner().decide(CorridorPlanner.DepthGrid.square15(grid))
        return """
{
  "name": "stopsForNearLowerHalfObstacle",
  "type": "planner",
  "grid": {
    "kind": "carvedCorridor",
    "colsFromBottom": ${colsFromBottom.toJsonArray()},
    "overrides": [
      { "row": 12, "col": 7, "value": 0.95 }
    ]
  },
  "expected": {
    "command": "${decision.command}",
    "reason": "${decision.reason}",
    "pathCells": ${decision.path.size}
  }
}""".trimIndent()
    }

    private fun stateMachineConfirmationsCase(): String {
        val stateMachine = CorridorStateMachine(confirmationsRequired = 3)
        val decisions = listOf(
            CorridorPlanner.CorridorDecision(CorridorPlanner.CorridorCommand.STRAIGHT, emptyList(), "test"),
            CorridorPlanner.CorridorDecision(CorridorPlanner.CorridorCommand.STRAIGHT, emptyList(), "test"),
            CorridorPlanner.CorridorDecision(CorridorPlanner.CorridorCommand.STRAIGHT, emptyList(), "test"),
        )
        val states = decisions.map(stateMachine::update)
        return stateMachineCase(
            name = "stateMachineRequiresThreeConfirmationsForNonStop",
            decisions = decisions,
            states = states,
        )
    }

    private fun stateMachineFrameLossCase(): String {
        val stateMachine = CorridorStateMachine(confirmationsRequired = 3)
        val decisions = listOf(
            CorridorPlanner.CorridorDecision(CorridorPlanner.CorridorCommand.STRAIGHT, emptyList(), "test"),
            CorridorPlanner.CorridorDecision(CorridorPlanner.CorridorCommand.STRAIGHT, emptyList(), "test"),
            CorridorPlanner.CorridorDecision(CorridorPlanner.CorridorCommand.STRAIGHT, emptyList(), "test"),
            CorridorPlanner.CorridorDecision(CorridorPlanner.CorridorCommand.STRAIGHT, emptyList(), "frame_loss"),
        )
        val states = decisions.map(stateMachine::update)
        return stateMachineCase(
            name = "stateMachineTreatsFrameLossAsStop",
            decisions = decisions,
            states = states,
        )
    }

    private fun stateMachineCase(
        name: String,
        decisions: List<CorridorPlanner.CorridorDecision>,
        states: List<CorridorStateMachine.CorridorState>,
    ): String =
        """
{
  "name": "$name",
  "type": "stateMachine",
  "decisions": [
${decisions.joinToString(",\n") { """    { "command": "${it.command}", "reason": "${it.reason}" }""" }}
  ],
  "expectedStates": [
${states.joinToString(",\n") { state ->
            """    { "command": "${state.command}", "changed": ${state.changed}, "pendingCommand": ${state.pendingCommand?.let { "\"$it\"" } ?: "null"}, "pendingCount": ${state.pendingCount} }"""
        }}
  ]
}""".trimIndent()

    private fun fusionNearObstacleCase(): String {
        val colsFromBottom = listOf(7, 7, 7, 7, 7, 7, 7, 7, 7)
        val detection = YoloObstacleDetector.YoloDetection(
            label = "person",
            score = 0.92f,
            centerX = 0.5f,
            centerY = 0.84f,
            width = 0.25f,
            height = 0.24f,
        )
        val grid = CorridorGridFusion().fuse(
            CorridorPlanner.DepthGrid.square15(carvedCorridor(colsFromBottom)),
            detections = listOf(detection),
        )
        val decision = CorridorPlanner().decide(grid)
        return """
{
  "name": "gridFusionHighConfidenceCenterDetectionForcesNearObstacleStop",
  "type": "fusion",
  "grid": {
    "kind": "carvedCorridor",
    "colsFromBottom": ${colsFromBottom.toJsonArray()}
  },
  "detections": [
    { "confidence": 0.92, "centerX": 0.5, "centerY": 0.84, "width": 0.25, "height": 0.24 }
  ],
  "expected": {
    "command": "${decision.command}",
    "reason": "${decision.reason}"
  }
}""".trimIndent()
    }

    private fun carvedCorridor(colsFromBottom: List<Int>): FloatArray =
        FloatArray(GRID_SIZE * GRID_SIZE) { 0.95f }.also { grid ->
            colsFromBottom.forEachIndexed { offset, col ->
                val row = GRID_SIZE - 1 - offset
                for (safeCol in (col - 1)..(col + 1)) {
                    if (safeCol in 0 until GRID_SIZE) {
                        grid[index(row, safeCol)] = 0.35f - offset * 0.02f
                    }
                }
            }
        }

    private fun index(row: Int, col: Int): Int = row * GRID_SIZE + col

    private fun List<Int>.toJsonArray(): String = joinToString(prefix = "[", postfix = "]")

    private const val GRID_SIZE = 15
}
