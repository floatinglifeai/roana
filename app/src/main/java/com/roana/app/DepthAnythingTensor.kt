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
        require(output.size == 1) { "Expected batch-one depth output, got batch=${output.size}" }
        val rows = output[0].size
        require(rows > 0) { "Depth output must have at least one row" }
        val cols = output[0][0].size
        require(cols > 0) { "Depth output must have at least one column" }

        val values = FloatArray(rows * cols)
        for (row in 0 until rows) {
            require(output[0][row].size == cols) { "Depth output rows must have uniform width" }
            for (col in 0 until cols) {
                require(output[0][row][col].size == OUTPUT_CHANNELS) {
                    "Expected one depth channel at $row,$col, got ${output[0][row][col].size}"
                }
                values[row * cols + col] = output[0][row][col][0]
            }
        }
        return DepthMap(rows = rows, cols = cols, values = values)
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
}
