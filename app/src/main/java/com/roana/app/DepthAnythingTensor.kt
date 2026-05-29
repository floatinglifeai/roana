package com.roana.app

object DepthAnythingTensor {
    const val INPUT_WIDTH = 518
    const val INPUT_HEIGHT = 518
    const val OUTPUT_WIDTH = 518
    const val OUTPUT_HEIGHT = 518
    const val OUTPUT_CHANNELS = 1

    fun newOutputArray(
        rows: Int = OUTPUT_HEIGHT,
        cols: Int = OUTPUT_WIDTH,
    ): Array<Array<Array<FloatArray>>> =
        Array(1) {
            Array(rows) {
                Array(cols) {
                    FloatArray(OUTPUT_CHANNELS)
                }
            }
        }

    fun flattenOutput(output: Array<Array<Array<FloatArray>>>): DepthMap {
        val shape = validateOutput(output)

        val values = FloatArray(shape.rows * shape.cols)
        for (row in 0 until shape.rows) {
            for (col in 0 until shape.cols) {
                values[row * shape.cols + col] = output[0][row][col][0]
            }
        }
        return DepthMap(rows = shape.rows, cols = shape.cols, values = values)
    }

    fun outputToPlannerGrid(output: Array<Array<Array<FloatArray>>>): CorridorPlanner.DepthGrid {
        val shape = validateOutput(output)
        if (shape.rows < PLANNER_GRID_SIZE || shape.cols < PLANNER_GRID_SIZE) {
            return flattenOutput(output).toPlannerGrid()
        }

        var min = Float.POSITIVE_INFINITY
        var max = Float.NEGATIVE_INFINITY
        val sums = DoubleArray(PLANNER_GRID_SIZE * PLANNER_GRID_SIZE)
        val counts = IntArray(PLANNER_GRID_SIZE * PLANNER_GRID_SIZE)

        for (row in 0 until shape.rows) {
            val gridRow = row * PLANNER_GRID_SIZE / shape.rows
            for (col in 0 until shape.cols) {
                val value = output[0][row][col][0]
                min = minOf(min, value)
                max = maxOf(max, value)
                val gridCol = col * PLANNER_GRID_SIZE / shape.cols
                val gridIndex = gridRow * PLANNER_GRID_SIZE + gridCol
                sums[gridIndex] += value
                counts[gridIndex] += 1
            }
        }

        val range = max - min
        val values = FloatArray(PLANNER_GRID_SIZE * PLANNER_GRID_SIZE)
        for (gridIndex in values.indices) {
            val average = (sums[gridIndex] / counts[gridIndex]).toFloat()
            values[gridIndex] = if (range > 0f) {
                (average - min) / range
            } else {
                0f
            }
        }
        return CorridorPlanner.DepthGrid.square15(values)
    }

    private fun validateOutput(output: Array<Array<Array<FloatArray>>>): OutputShape {
        require(output.size == 1) { "Expected batch-one depth output, got batch=${output.size}" }
        val rows = output[0].size
        require(rows > 0) { "Depth output must have at least one row" }
        val cols = output[0][0].size
        require(cols > 0) { "Depth output must have at least one column" }
        for (row in 0 until rows) {
            require(output[0][row].size == cols) { "Depth output rows must have uniform width" }
            for (col in 0 until cols) {
                require(output[0][row][col].size == OUTPUT_CHANNELS) {
                    "Expected one depth channel at $row,$col, got ${output[0][row][col].size}"
                }
            }
        }
        return OutputShape(rows = rows, cols = cols)
    }

    data class DepthMap(
        val rows: Int,
        val cols: Int,
        val values: FloatArray,
    ) {
        init {
            require(rows > 0 && cols > 0) { "Depth map dimensions must be positive" }
            require(values.size == rows * cols) {
                "Depth map value count ${values.size} does not match ${rows}x$cols"
            }
        }

        fun toPlannerGrid(): CorridorPlanner.DepthGrid =
            CorridorPlanner.DepthGrid.fromDepthMap(
                values = values,
                rows = rows,
                cols = cols,
            )

        fun toPlannerGridValues(): FloatArray =
            CorridorPlanner.DepthGrid.depthMapValues(
                values = values,
                rows = rows,
                cols = cols,
            )
    }

    private data class OutputShape(
        val rows: Int,
        val cols: Int,
    )

    private const val PLANNER_GRID_SIZE = 15
}
