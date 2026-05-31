package com.roana.app

import android.app.Activity
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
import android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
import android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.util.Locale
import kotlin.concurrent.thread
import kotlin.math.roundToLong

class VideoReplayBenchmarkActivity : Activity() {
    private var worker: Thread? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        worker = thread(name = "RoanaVideoReplayBenchmark") {
            val exitCode = runCatching {
                runBenchmark()
                0
            }.getOrElse { error ->
                Log.e(TAG, "replay_benchmark status=failed reason=${error.javaClass.simpleName}", error)
                1
            }
            Log.i(TAG, "replay_benchmark activity=finish exit_code=$exitCode")
            runOnUiThread { finishAndRemoveTask() }
        }
    }

    override fun onDestroy() {
        worker?.interrupt()
        super.onDestroy()
    }

    private fun runBenchmark() {
        val videoPath = intent.getStringExtra(EXTRA_VIDEO_PATH)?.takeIf { it.isNotBlank() }
            ?: error("Missing video path extra $EXTRA_VIDEO_PATH")
        val fps = intent.getStringExtra(EXTRA_FPS)?.toDoubleOrNull()?.takeIf { it > 0.0 }
            ?: DEFAULT_FPS
        val maxSeconds = intent.getStringExtra(EXTRA_MAX_SECONDS)?.toDoubleOrNull()?.takeIf { it > 0.0 }
        val rotationDegrees = intent.getIntExtra(EXTRA_ROTATION_DEGREES, 0)
        val runYolo = intent.getBooleanExtra(EXTRA_RUN_YOLO, true)
        val runDepth = intent.getBooleanExtra(EXTRA_RUN_DEPTH, true)

        val videoFile = File(videoPath)
        require(videoFile.isFile) { "Video file does not exist: $videoPath" }

        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(videoFile.absolutePath)
        val durationMs = retriever.extractMetadata(METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        val width = retriever.extractMetadata(METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
        val height = retriever.extractMetadata(METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
        Log.i(
            TAG,
            "replay_benchmark status=started video=${videoFile.name.sanitizeLogValue()} " +
                "duration_s=${(durationMs / MS_PER_SECOND).formatMs()} fps=${fps.formatMs()} " +
                "width=$width height=$height rotation=$rotationDegrees " +
                "run_yolo=$runYolo run_depth=$runDepth",
        )

        val yolo = if (runYolo) {
            YoloObstacleDetector(
                context = this,
                backend = InferenceBackend.create(
                    context = this,
                    precision = InferenceBackend.Precision.QUANTIZED,
                ),
            )
        } else {
            null
        }
        val depth = if (runDepth) DepthAnythingRunner(this) else null
        val corridor = if (runDepth) CorridorPipeline() else null

        try {
            processFrames(
                retriever = retriever,
                durationMs = durationMs,
                fps = fps,
                maxSeconds = maxSeconds,
                rotationDegrees = rotationDegrees,
                yolo = yolo,
                depth = depth,
                corridor = corridor,
            )
        } finally {
            yolo?.close()
            depth?.close()
            retriever.release()
        }
    }

    private fun processFrames(
        retriever: MediaMetadataRetriever,
        durationMs: Long,
        fps: Double,
        maxSeconds: Double?,
        rotationDegrees: Int,
        yolo: YoloObstacleDetector?,
        depth: DepthAnythingRunner?,
        corridor: CorridorPipeline?,
    ) {
        val frameIntervalUs = (US_PER_SECOND / fps).roundToLong().coerceAtLeast(1L)
        val maxUs = maxSeconds
            ?.let { (it * US_PER_SECOND).roundToLong() }
            ?: durationMs * US_PER_MS
        var presentationUs = 0L
        var processed = 0L
        var lastResult = YoloObstacleDetector.YoloResult(inferenceMs = 0.0, bestDetection = null)
        var lastDepthInferenceMs = 0.0
        var lastCommand: CorridorPlanner.CorridorCommand? = null

        while (presentationUs <= maxUs && !Thread.currentThread().isInterrupted) {
            val bitmap = retriever.getFrameAtTime(
                presentationUs,
                MediaMetadataRetriever.OPTION_CLOSEST,
            ) ?: break
            processed += 1
            val frameStartedNs = SystemClock.elapsedRealtimeNanos()
            val sampler = BitmapFrameSampler(bitmap, rotationDegrees = rotationDegrees)

            try {
                if (yolo != null) {
                    lastResult = yolo.detect(sampler)
                    Log.i(
                        TAG,
                        "yolo_inference inference_ms=${lastResult.inferenceMs.formatMs()} " +
                            "detection=${lastResult.bestDetection?.label ?: "none"}",
                    )
                    lastResult.timing?.let { Log.i(TAG, EvidenceLogContract.yoloTiming(it)) }
                }

                if (depth != null && corridor != null) {
                    val corridorStartedNs = SystemClock.elapsedRealtimeNanos()
                    val depthResult = depth.inferGridTimed(sampler)
                    val pipelineStartedNs = SystemClock.elapsedRealtimeNanos()
                    val corridorResult = corridor.process(
                        grid = depthResult.depthGrid,
                        detections = listOfNotNull(lastResult.bestDetection),
                    )
                    val pipelineMs = elapsedRealtimeMs(pipelineStartedNs)
                    val corridorTotalMs = elapsedRealtimeMs(corridorStartedNs)
                    lastDepthInferenceMs = depthResult.inferenceMs
                    lastCommand = corridorResult.state.command
                    depthResult.timing?.let { timing ->
                        Log.i(
                            TAG,
                            EvidenceLogContract.corridorLiveTiming(
                                depthTiming = timing,
                                pipelineMs = pipelineMs,
                                totalMs = corridorTotalMs,
                            ),
                        )
                    }
                    Log.i(
                        TAG,
                        EvidenceLogContract.corridorLiveOk(
                            depthMs = depthResult.inferenceMs,
                            result = corridorResult,
                            detections = if (lastResult.bestDetection == null) 0 else 1,
                        ),
                    )
                }

                Log.i(
                    TAG,
                    EvidenceLogContract.frameStats(
                        EvidenceLogContract.FrameStatsLog(
                            frames = processed,
                            gapCount = 0,
                            analysisMs = elapsedRealtimeMs(frameStartedNs),
                            yoloInferenceMs = lastResult.inferenceMs,
                            depthInferenceMs = lastDepthInferenceMs,
                            corridorCommand = lastCommand,
                            detectionLabel = lastResult.bestDetection?.label,
                            imageWidth = sampler.width,
                            imageHeight = sampler.height,
                        ),
                    ),
                )
            } finally {
                bitmap.recycle()
            }

            presentationUs += frameIntervalUs
        }

        Log.i(TAG, "replay_benchmark status=finished frames=$processed")
    }

    private fun elapsedRealtimeMs(startedNs: Long): Double =
        (SystemClock.elapsedRealtimeNanos() - startedNs).toDouble() / NS_PER_MS

    private fun Double.formatMs(): String =
        String.format(Locale.US, "%.2f", this)

    private fun String.sanitizeLogValue(): String =
        replace('\n', '_').replace('\r', '_').replace(' ', '_')

    private companion object {
        private const val TAG = "RoanaV0a"
        private const val EXTRA_VIDEO_PATH = "com.roana.app.extra.REPLAY_VIDEO_PATH"
        private const val EXTRA_FPS = "com.roana.app.extra.REPLAY_FPS"
        private const val EXTRA_MAX_SECONDS = "com.roana.app.extra.REPLAY_MAX_SECONDS"
        private const val EXTRA_ROTATION_DEGREES = "com.roana.app.extra.REPLAY_ROTATION_DEGREES"
        private const val EXTRA_RUN_YOLO = "com.roana.app.extra.REPLAY_RUN_YOLO"
        private const val EXTRA_RUN_DEPTH = "com.roana.app.extra.REPLAY_RUN_DEPTH"
        private const val DEFAULT_FPS = 10.0
        private const val MS_PER_SECOND = 1_000.0
        private const val US_PER_MS = 1_000L
        private const val US_PER_SECOND = 1_000_000.0
        private const val NS_PER_MS = 1_000_000.0
    }
}
