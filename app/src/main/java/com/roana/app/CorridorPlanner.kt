package com.roana.app

import kotlin.math.abs

class CorridorPlanner {
    fun decide(grid: DepthGrid): CorridorDecision {
        require(grid.rows == CorridorContract.GRID_SIZE && grid.cols == CorridorContract.GRID_SIZE) {
            "Expected ${CorridorContract.GRID_SIZE}x${CorridorContract.GRID_SIZE} depth grid, got ${grid.rows}x${grid.cols}"
        }

        if (grid.nearestBottomCenter() >= CorridorContract.NEAR_OBSTACLE_DEPTH) {
            return CorridorDecision(CorridorCommand.STOP, emptyList(), CorridorContract.Reason.NEAR_OBSTACLE)
        }

        val start = Cell(row = CorridorContract.GRID_SIZE - 1, col = CorridorContract.GRID_SIZE / 2)
        val path = search(grid, start)
        if (path.size < CorridorContract.MIN_PATH_CELLS) {
            return CorridorDecision(CorridorCommand.STOP, path, CorridorContract.Reason.NO_SAFE_CORRIDOR)
        }

        val endpoint = path.last()
        val offset = endpoint.col - start.col
        val command = when {
            offset <= -CorridorContract.TURN_OFFSET_CELLS -> CorridorCommand.LEFT
            offset >= CorridorContract.TURN_OFFSET_CELLS -> CorridorCommand.RIGHT
            else -> CorridorCommand.STRAIGHT
        }
        return CorridorDecision(command, path, CorridorContract.Reason.PATH_FOUND)
    }

    private fun search(grid: DepthGrid, start: Cell): List<Cell> {
        val memo = arrayOfNulls<PathCandidate>(CorridorContract.GRID_SIZE * CorridorContract.GRID_SIZE)
        return bestPathFrom(
            grid = grid,
            current = start,
            startCol = start.col,
            memo = memo,
        ).toCells()
    }

    private fun bestPathFrom(
        grid: DepthGrid,
        current: Cell,
        startCol: Int,
        memo: Array<PathCandidate?>,
    ): PathCandidate {
        val memoIndex = current.row * CorridorContract.GRID_SIZE + current.col
        memo[memoIndex]?.let { return it }

        var bestNext: PathCandidate? = null
        if (current.row > 0) {
            nextCandidates(current).forEach { candidate ->
                if (
                    grid.contains(candidate) &&
                    grid[candidate] <= CorridorContract.SAFE_CELL_DEPTH &&
                    grid[candidate] <= grid[current] + CorridorContract.MAX_FORWARD_DEPTH_RISE
                ) {
                    val nextPath = bestPathFrom(
                        grid = grid,
                        current = candidate,
                        startCol = startCol,
                        memo = memo,
                    )
                    if (bestNext == null || nextPath.isBetterThan(bestNext)) {
                        bestNext = nextPath
                    }
                }
            }
        }

        val result = PathCandidate(
            cell = current,
            length = 1 + (bestNext?.length ?: 0),
            clearanceScore = horizontalClearance(grid, current) + (bestNext?.clearanceScore ?: 0),
            straightnessScore = -abs(current.col - startCol) + (bestNext?.straightnessScore ?: 0),
            next = bestNext,
        )
        memo[memoIndex] = result
        return result
    }

    private fun nextCandidates(current: Cell): List<Cell> =
        listOf(
            Cell(current.row - 1, current.col),
            Cell(current.row - 1, current.col - 1),
            Cell(current.row - 1, current.col + 1),
        )

    private fun horizontalClearance(grid: DepthGrid, cell: Cell): Int {
        if (grid[cell] > CorridorContract.SAFE_CELL_DEPTH) {
            return 0
        }

        var left = 0
        var col = cell.col - 1
        while (col >= 0 && grid[Cell(cell.row, col)] <= CorridorContract.SAFE_CELL_DEPTH) {
            left += 1
            col -= 1
        }

        var right = 0
        col = cell.col + 1
        while (col < CorridorContract.GRID_SIZE && grid[Cell(cell.row, col)] <= CorridorContract.SAFE_CELL_DEPTH) {
            right += 1
            col += 1
        }

        return minOf(left, right)
    }

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
            for (row in rows - CorridorContract.IMMINENT_OBSTACLE_ROWS until rows) {
                for (col in (centerCol - CorridorContract.IMMINENT_OBSTACLE_HALF_WIDTH)..(centerCol + CorridorContract.IMMINENT_OBSTACLE_HALF_WIDTH)) {
                    nearest = maxOf(nearest, values[row * cols + col])
                }
            }
            return nearest
        }

        companion object {
            fun square15(values: FloatArray): DepthGrid =
                DepthGrid(CorridorContract.GRID_SIZE, CorridorContract.GRID_SIZE, values)

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
                val output = FloatArray(CorridorContract.GRID_SIZE * CorridorContract.GRID_SIZE)
                for (gridRow in 0 until CorridorContract.GRID_SIZE) {
                    val sourceRowStart = gridRow * rows / CorridorContract.GRID_SIZE
                    val sourceRowEnd = maxOf(sourceRowStart + 1, (gridRow + 1) * rows / CorridorContract.GRID_SIZE)
                    for (gridCol in 0 until CorridorContract.GRID_SIZE) {
                        val sourceColStart = gridCol * cols / CorridorContract.GRID_SIZE
                        val sourceColEnd = maxOf(sourceColStart + 1, (gridCol + 1) * cols / CorridorContract.GRID_SIZE)
                        var sum = 0.0
                        var count = 0
                        for (sourceRow in sourceRowStart until sourceRowEnd) {
                            for (sourceCol in sourceColStart until sourceColEnd) {
                                sum += values[sourceRow * cols + sourceCol]
                                count += 1
                            }
                        }
                        val average = (sum / count).toFloat()
                        output[gridRow * CorridorContract.GRID_SIZE + gridCol] = if (range > 0f) {
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

    private data class PathCandidate(
        val cell: Cell,
        val length: Int,
        val clearanceScore: Int,
        val straightnessScore: Int,
        val next: PathCandidate?,
    ) {
        fun isBetterThan(other: PathCandidate?): Boolean =
            other == null ||
                length > other.length ||
                (length == other.length && clearanceScore > other.clearanceScore) ||
                (
                    length == other.length &&
                        clearanceScore == other.clearanceScore &&
                        straightnessScore > other.straightnessScore
                    )

        fun toCells(): List<Cell> {
            val cells = ArrayList<Cell>(length)
            var current: PathCandidate? = this
            while (current != null) {
                cells += current.cell
                current = current.next
            }
            return cells
        }
    }

}
