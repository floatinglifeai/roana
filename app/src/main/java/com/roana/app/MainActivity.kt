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

    private var ttsReady = false
    private var cameraBound = false
    private var readyAnnouncementSpoken = false

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
        setupTextToSpeech()
        requestCameraPermissionOrStart()
    }

    override fun onDestroy() {
        cameraExecutor.shutdown()
        if (::textToSpeech.isInitialized) {
            textToSpeech.stop()
            textToSpeech.shutdown()
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
                val result = textToSpeech.setLanguage(Locale.US)
                ttsReady = result != TextToSpeech.LANG_MISSING_DATA &&
                    result != TextToSpeech.LANG_NOT_SUPPORTED
                Log.i(TAG, "tts_init status=success ready=$ttsReady")
                maybeAnnounceReady()
            } else {
                Log.w(TAG, "tts_init status=failure code=$status")
            }
        }
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
                            TimingAnalyzer { stats -> updateStats(stats) },
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
            statusView.text =
                "Frames ${stats.frames} | analysis ${stats.analysisMs.roundToInt()} ms | gaps ${stats.gapCount}"
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
    }

    private class TimingAnalyzer(
        private val onStats: (FrameStats) -> Unit,
    ) : ImageAnalysis.Analyzer {
        private var frames = 0L
        private var gapCount = 0L
        private var lastCameraTimestampNs = 0L
        private var lastLogTimeMs = 0L

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

                val inferenceStartNs = SystemClock.elapsedRealtimeNanos()
                val inferenceMs =
                    (SystemClock.elapsedRealtimeNanos() - inferenceStartNs).toDouble() / NS_PER_MS
                val analysisMs =
                    (SystemClock.elapsedRealtimeNanos() - analysisStartNs).toDouble() / NS_PER_MS

                val nowMs = SystemClock.elapsedRealtime()
                if (nowMs - lastLogTimeMs >= LOG_INTERVAL_MS) {
                    lastLogTimeMs = nowMs
                    Log.i(
                        TAG,
                        "frame_stats frames=$frames gap_count=$gapCount " +
                            "analysis_ms=${"%.2f".format(Locale.US, analysisMs)} " +
                            "inference_ms=${"%.2f".format(Locale.US, inferenceMs)} " +
                            "image=${image.width}x${image.height}",
                    )
                    onStats(FrameStats(frames, gapCount, analysisMs, inferenceMs))
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
    )

    private companion object {
        private const val TAG = "RoanaV0a"
        private const val LOG_INTERVAL_MS = 1_000L
        private const val FRAME_GAP_WARNING_MS = 150L
        private const val NS_PER_MS = 1_000_000L
    }
}
