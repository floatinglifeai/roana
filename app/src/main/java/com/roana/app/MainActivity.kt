package com.roana.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.SystemClock
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {
    private lateinit var previewView: PreviewView
    private lateinit var statusView: TextView
    private lateinit var cameraExecutor: ExecutorService
    private lateinit var textToSpeech: TextToSpeech
    private lateinit var obstacleDetector: YoloObstacleDetector

    private var ttsReady = false
    private var cameraBound = false
    private var readyAnnouncementSpoken = false
    private var personAlertSpoken = false
    private var debugDetectionProofSpoken = false
    private var debugDepthSmokeStarted = false

    private val cameraPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                statusView.text = "Starting camera"
                startCamera()
            } else {
                statusView.text = "Camera permission required"
                Log.w(TAG, "camera_permission_denied")
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        cameraExecutor = Executors.newSingleThreadExecutor()
        setupUi()
        obstacleDetector = YoloObstacleDetector(
            context = this,
            backend = InferenceBackend.create(precision = InferenceBackend.Precision.QUANTIZED),
        )
        setupTextToSpeech()
        maybeRunDebugDepthSmoke()
        requestCameraPermissionOrStart()
    }

    override fun onDestroy() {
        cameraExecutor.shutdown()
        if (::textToSpeech.isInitialized) {
            textToSpeech.stop()
            textToSpeech.shutdown()
        }
        if (::obstacleDetector.isInitialized) {
            obstacleDetector.close()
        }
        super.onDestroy()
    }

    private fun setupUi() {
        previewView = PreviewView(this).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        statusView = TextView(this).apply {
            setBackgroundColor(0x99000000.toInt())
            setPadding(24, 16, 24, 16)
            setTextColor(0xFFFFFFFF.toInt())
            text = "Waiting for camera"
            textSize = 14f
        }

        val statusLayoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply {
            gravity = Gravity.BOTTOM
        }

        setContentView(
            FrameLayout(this).apply {
                addView(previewView)
                addView(statusView, statusLayoutParams)
            },
        )
    }

    private fun setupTextToSpeech() {
        textToSpeech = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val locale = selectTextToSpeechLocale()
                val result = textToSpeech.setLanguage(locale)
                ttsReady = result != TextToSpeech.LANG_MISSING_DATA &&
                    result != TextToSpeech.LANG_NOT_SUPPORTED
                Log.i(TAG, "tts_language locale=$locale result=$result")
                Log.i(TAG, "tts_init status=success ready=$ttsReady")
                maybeAnnounceReady()
            } else {
                Log.w(TAG, "tts_init status=failure code=$status")
            }
        }
    }

    private fun selectTextToSpeechLocale(): Locale {
        val candidates = listOf(Locale.getDefault(), Locale.CHINA, Locale.US)
        return candidates.firstOrNull { locale ->
            val availability = textToSpeech.isLanguageAvailable(locale)
            availability >= TextToSpeech.LANG_AVAILABLE
        } ?: Locale.getDefault()
    }

    private fun requestCameraPermissionOrStart() {
        when {
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED -> startCamera()
            shouldShowRequestPermissionRationale(Manifest.permission.CAMERA) -> {
                statusView.text = "Camera permission required"
                cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
            }
            else -> cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener(
            {
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }

                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                    .build()
                    .also {
                        it.setAnalyzer(
                            cameraExecutor,
                            TimingAnalyzer(
                                detector = obstacleDetector,
                                onStats = { stats -> updateStats(stats) },
                                onDetection = { detection -> announceDetection(detection) },
                            ),
                        )
                    }

                try {
                    cameraProvider.unbindAll()
                    cameraProvider.bindToLifecycle(
                        this,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analysis,
                    )
                    cameraBound = true
                    statusView.text = "Camera active"
                    Log.i(TAG, "camera_bound analyzer=keep_only_latest output=yuv_420_888")
                    maybeAnnounceReady()
                    maybeRunDebugDetectionProof()
                } catch (error: Exception) {
                    statusView.text = "Camera start failed"
                    Log.e(TAG, "camera_bind_failed", error)
                }
            },
            ContextCompat.getMainExecutor(this),
        )
    }

    private fun updateStats(stats: FrameStats) {
        runOnUiThread {
            val detectionText = stats.bestDetection?.let {
                " | ${it.label} ${it.scorePercent()}%"
            }.orEmpty()
            statusView.text =
                "Frames ${stats.frames} | yolo ${stats.inferenceMs.roundToInt()} ms | gaps ${stats.gapCount}$detectionText"
        }
    }

    private fun maybeAnnounceReady() {
        if (!ttsReady || !cameraBound || readyAnnouncementSpoken) {
            return
        }

        readyAnnouncementSpoken = true
        val utteranceId = "roana-ready-${SystemClock.uptimeMillis()}"
        textToSpeech.speak("Roana camera ready", TextToSpeech.QUEUE_FLUSH, null, utteranceId)
        Log.i(TAG, "tts_event id=$utteranceId message=camera_ready")
        maybeRunDebugDetectionProof()
    }

    private fun announceDetection(detection: YoloObstacleDetector.YoloDetection) {
        if (!ttsReady || personAlertSpoken) {
            return
        }

        personAlertSpoken = true
        val utteranceId = "roana-person-${SystemClock.uptimeMillis()}"
        textToSpeech.speak("Person ahead", TextToSpeech.QUEUE_ADD, null, utteranceId)
        Log.i(
            TAG,
            "tts_event id=$utteranceId message=person_ahead score=${"%.3f".format(Locale.US, detection.score)}",
        )
    }

    private fun maybeRunDebugDetectionProof() {
        if (
            !BuildConfig.DEBUG ||
            !intent.getBooleanExtra(EXTRA_DEBUG_PERSON_DETECTION, false) ||
            !ttsReady ||
            !cameraBound ||
            debugDetectionProofSpoken
        ) {
            return
        }

        debugDetectionProofSpoken = true
        val detection = YoloObstacleDetector.YoloDetection(
            label = "person",
            score = 0.99f,
            centerX = 0.5f,
            centerY = 0.5f,
            width = 0.4f,
            height = 0.6f,
        )
        Log.i(TAG, "debug_person_detection_proof enabled=true")
        announceDetection(detection)
    }

    private fun maybeRunDebugDepthSmoke() {
        if (
            !BuildConfig.DEBUG ||
            !intent.getBooleanExtra(EXTRA_DEBUG_DEPTH_SMOKE, false) ||
            debugDepthSmokeStarted
        ) {
            return
        }

        debugDepthSmokeStarted = true
        Thread {
            try {
                DepthAnythingSmoke(this).run()
            } catch (error: Exception) {
                Log.e(TAG, "depth_smoke status=failed", error)
            }
        }.apply {
            name = "RoanaDepthSmoke"
            start()
        }
    }

    private class TimingAnalyzer(
        private val detector: YoloObstacleDetector,
        private val onStats: (FrameStats) -> Unit,
        private val onDetection: (YoloObstacleDetector.YoloDetection) -> Unit,
    ) : ImageAnalysis.Analyzer {
        private var frames = 0L
        private var gapCount = 0L
        private var lastCameraTimestampNs = 0L
        private var lastLogTimeMs = 0L
        private var lastResult = YoloObstacleDetector.YoloResult(
            inferenceMs = 0.0,
            bestDetection = null,
        )

        override fun analyze(image: ImageProxy) {
            val analysisStartNs = SystemClock.elapsedRealtimeNanos()

            try {
                frames += 1
                val cameraTimestampNs = image.imageInfo.timestamp
                if (lastCameraTimestampNs > 0L) {
                    val cameraGapMs = (cameraTimestampNs - lastCameraTimestampNs) / NS_PER_MS
                    if (cameraGapMs > FRAME_GAP_WARNING_MS) {
                        gapCount += 1
                        Log.w(
                            TAG,
                            "camera_frame_gap gap_ms=$cameraGapMs total_gaps=$gapCount",
                        )
                    }
                }
                lastCameraTimestampNs = cameraTimestampNs

                if (frames % YOLO_FRAME_INTERVAL == 1L) {
                    try {
                        lastResult = detector.detect(image)
                        Log.i(
                            TAG,
                            "yolo_inference inference_ms=${"%.2f".format(Locale.US, lastResult.inferenceMs)} " +
                                "detection=${lastResult.bestDetection?.label ?: "none"}",
                        )
                        lastResult.bestDetection?.let { detection ->
                            Log.i(
                                TAG,
                                "yolo_detection label=${detection.label} " +
                                    "score=${"%.3f".format(Locale.US, detection.score)} " +
                                    "center=${"%.2f".format(Locale.US, detection.centerX)}," +
                                    "${"%.2f".format(Locale.US, detection.centerY)} " +
                                    "size=${"%.2f".format(Locale.US, detection.width)}x" +
                                    "%.2f".format(Locale.US, detection.height),
                            )
                            onDetection(detection)
                        }
                    } catch (error: Exception) {
                        Log.e(TAG, "yolo_error", error)
                    }
                }
                val analysisMs =
                    (SystemClock.elapsedRealtimeNanos() - analysisStartNs).toDouble() / NS_PER_MS

                val nowMs = SystemClock.elapsedRealtime()
                if (nowMs - lastLogTimeMs >= LOG_INTERVAL_MS) {
                    lastLogTimeMs = nowMs
                    Log.i(
                        TAG,
                        "frame_stats frames=$frames gap_count=$gapCount " +
                            "analysis_ms=${"%.2f".format(Locale.US, analysisMs)} " +
                            "inference_ms=${"%.2f".format(Locale.US, lastResult.inferenceMs)} " +
                            "detection=${lastResult.bestDetection?.label ?: "none"} " +
                            "image=${image.width}x${image.height}",
                    )
                    onStats(
                        FrameStats(
                            frames = frames,
                            gapCount = gapCount,
                            analysisMs = analysisMs,
                            inferenceMs = lastResult.inferenceMs,
                            bestDetection = lastResult.bestDetection,
                        ),
                    )
                }
            } finally {
                image.close()
            }
        }
    }

    private data class FrameStats(
        val frames: Long,
        val gapCount: Long,
        val analysisMs: Double,
        val inferenceMs: Double,
        val bestDetection: YoloObstacleDetector.YoloDetection?,
    )

    private companion object {
        private const val TAG = "RoanaV0a"
        private const val EXTRA_DEBUG_PERSON_DETECTION =
            "com.roana.app.extra.DEBUG_PERSON_DETECTION"
        private const val EXTRA_DEBUG_DEPTH_SMOKE =
            "com.roana.app.extra.DEBUG_DEPTH_SMOKE"
        private const val LOG_INTERVAL_MS = 1_000L
        private const val YOLO_FRAME_INTERVAL = 10L
        private const val FRAME_GAP_WARNING_MS = 150L
        private const val NS_PER_MS = 1_000_000L
    }
}
