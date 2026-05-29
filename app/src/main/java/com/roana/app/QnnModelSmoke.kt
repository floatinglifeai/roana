package com.roana.app

import android.content.Context
import android.util.Log
import java.io.FileInputStream
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.util.Locale
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.Tensor

class QnnModelSmoke(private val context: Context) {
    fun runYolo() {
        run(
            spec = ModelSpec(
                name = "yolo",
                asset = YOLO_ASSET,
                precision = InferenceBackend.Precision.QUANTIZED,
            ),
        )
    }

    fun runDepth() {
        run(
            spec = ModelSpec(
                name = "depth",
                asset = DEPTH_ASSET,
                precision = InferenceBackend.Precision.FP16,
            ),
        )
    }

    private fun run(spec: ModelSpec) {
        val startedNs = System.nanoTime()
        val model = loadModel(spec.asset)
        logCpuMetadata(spec, model)

        val backend = InferenceBackend.create(precision = spec.precision)
        if (!backend.usesDelegate) {
            Log.w(
                TAG,
                "qnn_model_smoke status=unavailable model=${spec.name} " +
                    "asset=${spec.asset} precision=${spec.precision.logValue} " +
                    "backend=${backend.name} reason=${backend.failureReason ?: "none"}",
            )
            backend.close()
            return
        }

        try {
            Interpreter(model.buffer, backend.applyTo(Interpreter.Options().setNumThreads(2))).use { interpreter ->
                val loadMs = (System.nanoTime() - startedNs).toDouble() / NS_PER_MS
                Log.i(
                    TAG,
                    "qnn_model_smoke status=loaded model=${spec.name} " +
                        "asset=${spec.asset} precision=${spec.precision.logValue} " +
                        "backend=${backend.name} load_ms=${"%.2f".format(Locale.US, loadMs)} " +
                        "inputs=${inputSummary(interpreter)} outputs=${outputSummary(interpreter)}",
                )
            }
        } catch (error: Exception) {
            Log.e(
                TAG,
                "qnn_model_smoke status=failed model=${spec.name} " +
                    "asset=${spec.asset} precision=${spec.precision.logValue} " +
                    "backend=${backend.name} error=${error.javaClass.simpleName} " +
                    "message=${error.message?.sanitizeLogValue() ?: "none"}",
                error,
            )
        } finally {
            backend.close()
        }
    }

    private fun logCpuMetadata(spec: ModelSpec, model: LoadedModel) {
        try {
            Interpreter(
                model.buffer,
                Interpreter.Options().setNumThreads(1).setUseXNNPACK(true),
            ).use { interpreter ->
                Log.i(
                    TAG,
                    "qnn_model_metadata model=${spec.name} asset=${spec.asset} " +
                        "bytes=${model.byteCount} precision=${spec.precision.logValue} " +
                        "inputs=${inputSummary(interpreter)} outputs=${outputSummary(interpreter)}",
                )
            }
        } catch (error: Exception) {
            Log.e(
                TAG,
                "qnn_model_metadata status=failed model=${spec.name} " +
                    "asset=${spec.asset} error=${error.javaClass.simpleName} " +
                    "message=${error.message?.sanitizeLogValue() ?: "none"}",
                error,
            )
        }
    }

    private fun loadModel(asset: String): LoadedModel =
        context.assets.openFd(asset).use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).channel.use { channel ->
                LoadedModel(
                    buffer = channel.map(
                        FileChannel.MapMode.READ_ONLY,
                        descriptor.startOffset,
                        descriptor.declaredLength,
                    ),
                    byteCount = descriptor.declaredLength,
                )
            }
        }

    private fun inputSummary(interpreter: Interpreter): String =
        tensorSummary(count = interpreter.inputTensorCount) { index ->
            interpreter.getInputTensor(index)
        }

    private fun outputSummary(interpreter: Interpreter): String =
        tensorSummary(count = interpreter.outputTensorCount) { index ->
            interpreter.getOutputTensor(index)
        }

    private fun tensorSummary(
        count: Int,
        tensorAt: (Int) -> Tensor,
    ): String =
        (0 until count).joinToString(separator = ";") { index ->
            val tensor = tensorAt(index)
            val quantization = tensor.quantizationParams()
            "$index:${tensor.dataType()}${tensor.shape().contentToString()}" +
                ":q=${"%.8f".format(Locale.US, quantization.scale)},${quantization.zeroPoint}"
        }

    private data class ModelSpec(
        val name: String,
        val asset: String,
        val precision: InferenceBackend.Precision,
    )

    private data class LoadedModel(
        val buffer: MappedByteBuffer,
        val byteCount: Long,
    )

    private companion object {
        private const val TAG = "RoanaV0a"
        private const val YOLO_ASSET = "yolo11n-det-int8-smart.tflite"
        private const val DEPTH_ASSET = "depth_anything_v2.tflite"
        private const val NS_PER_MS = 1_000_000.0
    }
}

private fun String.sanitizeLogValue(): String =
    replace('\n', ' ')
        .replace('\r', ' ')
        .replace(' ', '_')
