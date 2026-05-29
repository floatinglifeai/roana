package com.roana.app

class CorridorGridFusion {
    fun fuse(
        depthMap: DepthAnythingTensor.DepthMap,
        detections: List<YoloObstacleDetector.YoloDetection>,
    ): CorridorPlanner.DepthGrid =
        fuse(depthMap.toPlannerGrid(), detections)

    fun fuse(
        depthGrid: CorridorPlanner.DepthGrid,
        detections: List<YoloObstacleDetector.YoloDetection>,
    ): CorridorPlanner.DepthGrid {
        val values = depthGrid.toFloatArray()
        detections
            .filter { it.score >= DETECTION_GRID_THRESHOLD }
            .forEach { detection -> markDetection(values, detection) }
        return CorridorPlanner.DepthGrid.square15(values)
    }

    private fun markDetection(
        grid: FloatArray,
        detection: YoloObstacleDetector.YoloDetection,
    ) {
        val left = ((detection.centerX - detection.width / 2f) * GRID_SIZE)
            .toInt()
            .coerceIn(0, GRID_SIZE - 1)
        val right = ((detection.centerX + detection.width / 2f) * GRID_SIZE)
            .toInt()
            .coerceIn(0, GRID_SIZE - 1)
        val top = ((detection.centerY - detection.height / 2f) * GRID_SIZE)
            .toInt()
            .coerceIn(0, GRID_SIZE - 1)
        val bottom = ((detection.centerY + detection.height / 2f) * GRID_SIZE)
            .toInt()
            .coerceIn(0, GRID_SIZE - 1)

        for (row in top..bottom) {
            for (col in left..right) {
                grid[row * GRID_SIZE + col] = DETECTION_OBSTACLE_DEPTH
            }
        }
    }

    private companion object {
        private const val GRID_SIZE = 15
        private const val DETECTION_GRID_THRESHOLD = 0.35f
        private const val DETECTION_OBSTACLE_DEPTH = 0.96f
    }
}
