package com.roana.app

import kotlin.math.abs

class CorridorPlanner {
    fun decide(grid: DepthGrid): CorridorDecision {
        require(grid.rows == GRID_SIZE && grid.cols == GRID_SIZE) {
            "Expected ${GRID_SIZE}x$GRID_SIZE depth grid, got ${grid.rows}x${grid.cols}"
        }

        if (grid.nearestBottomCenter() >= NEAR_OBSTACLE_DEPTH) {
            return CorridorDecision(CorridorCommand.STOP, emptyList(), "near_obstacle")
        }

        val start = Cell(row = GRID_SIZE - 1, col = GRID_SIZE / 2)
        val path = search(grid, start, listOf(start))
        if (path.size < MIN_PATH_CELLS) {
            return CorridorDecision(CorridorCommand.STOP, path, "no_safe_corridor")
        }

        val endpoint = path.last()
        val offset = endpoint.col - start.col
        val command = when {
            offset <= -TURN_OFFSET_CELLS -> CorridorCommand.LEFT
            offset >= TURN_OFFSET_CELLS -> CorridorCommand.RIGHT
            else -> CorridorCommand.STRAIGHT
        }
        return CorridorDecision(command, path, "path_found")
    }

    private fun search(grid: DepthGrid, current: Cell, path: List<Cell>): List<Cell> {
        if (current.row == 0) {
            return path
        }

        val candidates = nextCandidates(current)
            .filter { grid.contains(it) }
            .filter { candidate -> grid[candidate] <= SAFE_CELL_DEPTH }
            .filter { candidate -> grid[candidate] <= grid[current] + MAX_FORWARD_DEPTH_RISE }

        if (candidates.isEmpty()) {
            return path
        }

        return candidates
            .map { candidate -> search(grid, candidate, path + candidate) }
            .maxWith(pathComparator)
    }

    private fun nextCandidates(current: Cell): List<Cell> =
        listOf(
            Cell(current.row - 1, current.col),
            Cell(current.row - 1, current.col - 1),
            Cell(current.row - 1, current.col + 1),
        )

    data class DepthGrid(
        val rows: Int,
        val cols: Int,
        private val values: FloatArray,
    ) {
        init {
            require(rows > 0 && cols > 0) { "Depth grid dimensions must be positive" }
            require(values.size == rows * cols) {
                "Depth grid value count ${values.size} does not match ${rows}x$cols"
            }
        }

        operator fun get(cell: Cell): Float = values[cell.row * cols + cell.col]

        fun toFloatArray(): FloatArray = values.copyOf()

        fun contains(cell: Cell): Boolean =
            cell.row in 0 until rows && cell.col in 0 until cols

        fun nearestBottomCenter(): Float {
            var nearest = Float.NEGATIVE_INFINITY
            val centerCol = cols / 2
            for (row in rows - IMMINENT_OBSTACLE_ROWS until rows) {
                for (col in (centerCol - IMMINENT_OBSTACLE_HALF_WIDTH)..(centerCol + IMMINENT_OBSTACLE_HALF_WIDTH)) {
                    nearest = maxOf(nearest, values[row * cols + col])
                }
            }
            return nearest
        }

        companion object {
            fun square15(values: FloatArray): DepthGrid =
                DepthGrid(GRID_SIZE, GRID_SIZE, values)

            fun fromDepthMap(
                values: FloatArray,
                rows: Int,
                cols: Int,
            ): DepthGrid {
                require(rows > 0 && cols > 0) { "Depth map dimensions must be positive" }
                require(values.size == rows * cols) {
                    "Depth map value count ${values.size} does not match ${rows}x$cols"
                }

                val min = values.minOrNull() ?: 0f
                val max = values.maxOrNull() ?: min
                val range = max - min
                val output = FloatArray(GRID_SIZE * GRID_SIZE)
                for (gridRow in 0 until GRID_SIZE) {
                    val sourceRowStart = gridRow * rows / GRID_SIZE
                    val sourceRowEnd = maxOf(sourceRowStart + 1, (gridRow + 1) * rows / GRID_SIZE)
                    for (gridCol in 0 until GRID_SIZE) {
                        val sourceColStart = gridCol * cols / GRID_SIZE
                        val sourceColEnd = maxOf(sourceColStart + 1, (gridCol + 1) * cols / GRID_SIZE)
                        var sum = 0.0
                        var count = 0
                        for (sourceRow in sourceRowStart until sourceRowEnd) {
                            for (sourceCol in sourceColStart until sourceColEnd) {
                                sum += values[sourceRow * cols + sourceCol]
                                count += 1
                            }
                        }
                        val average = (sum / count).toFloat()
                        output[gridRow * GRID_SIZE + gridCol] = if (range > 0f) {
                            (average - min) / range
                        } else {
                            0f
                        }
                    }
                }
                return square15(output)
            }

            fun depthMapValues(
                values: FloatArray,
                rows: Int,
                cols: Int,
            ): FloatArray =
                fromDepthMap(values = values, rows = rows, cols = cols).toFloatArray()
        }
    }

    data class Cell(
        val row: Int,
        val col: Int,
    )

    data class CorridorDecision(
        val command: CorridorCommand,
        val path: List<Cell>,
        val reason: String,
    )

    enum class CorridorCommand {
        LEFT,
        STRAIGHT,
        RIGHT,
        STOP,
    }

    private companion object {
        private const val GRID_SIZE = 15
        private const val NEAR_OBSTACLE_DEPTH = 0.86f
        private const val SAFE_CELL_DEPTH = 0.72f
        private const val MAX_FORWARD_DEPTH_RISE = 0.12f
        private const val MIN_PATH_CELLS = 6
        private const val TURN_OFFSET_CELLS = 3
        private const val IMMINENT_OBSTACLE_ROWS = 3
        private const val IMMINENT_OBSTACLE_HALF_WIDTH = 1

        private val pathComparator = compareBy<List<Cell>> { it.size }
            .thenByDescending { path -> straightnessScore(path) }

        private fun straightnessScore(path: List<Cell>): Int {
            val startCol = path.first().col
            return -path.sumOf { abs(it.col - startCol) }
        }
    }
}
