package com.roana.app

import android.content.Context
import android.util.Log
import java.io.FileInputStream
import java.nio.channels.FileChannel
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter

class DepthAnythingSmoke(private val context: Context) {
    fun run() {
        val startedNs = System.nanoTime()
        val backend = InferenceBackend.create(precision = InferenceBackend.Precision.FP16)
        val modelBuffer = context.assets.openFd(MODEL_ASSET).use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).channel.use { channel ->
                channel.map(FileChannel.MapMode.READ_ONLY, descriptor.startOffset, descriptor.declaredLength)
            }
        }

        val opened = try {
            OpenedInterpreter(
                interpreter = Interpreter(
                    modelBuffer,
                    backend.applyTo(Interpreter.Options().setNumThreads(2)),
                ),
                backend = backend,
            )
        } catch (error: Exception) {
            if (!backend.usesDelegate) {
                throw error
            }

            Log.w(
                TAG,
                "depth_backend selected=cpu_xnnpack reason=qnn_interpreter_failed",
                error,
            )
            backend.close()
            val fallbackBackend = InferenceBackend.cpu(
                reason = "${error.javaClass.simpleName}:${error.message.orEmpty()}",
            )
            OpenedInterpreter(
                interpreter = Interpreter(
                    modelBuffer,
                    fallbackBackend.applyTo(Interpreter.Options().setNumThreads(2)),
                ),
                backend = fallbackBackend,
            )
        }

        opened.interpreter.use {
            val inputTensor = it.getInputTensor(0)
            val outputTensor = it.getOutputTensor(0)
            val loadMs = (System.nanoTime() - startedNs).toDouble() / NS_PER_MS
            require(inputTensor.shape().contentEquals(intArrayOf(1, 518, 518, 3))) {
                "Unexpected Depth Anything input shape ${inputTensor.shape().contentToString()}"
            }
            require(inputTensor.dataType() == DataType.FLOAT32) {
                "Unexpected Depth Anything input type ${inputTensor.dataType()}"
            }
            require(outputTensor.shape().contentEquals(intArrayOf(1, 518, 518, 1))) {
                "Unexpected Depth Anything output shape ${outputTensor.shape().contentToString()}"
            }
            require(outputTensor.dataType() == DataType.FLOAT32) {
                "Unexpected Depth Anything output type ${outputTensor.dataType()}"
            }
            Log.i(
                TAG,
                "depth_smoke status=loaded input=${inputTensor.shape().contentToString()} " +
                    "output=${outputTensor.shape().contentToString()} load_ms=" +
                    "%.2f".format(java.util.Locale.US, loadMs),
            )
        }

        opened.backend.close()
    }

    private data class OpenedInterpreter(
        val interpreter: Interpreter,
        val backend: InferenceBackend,
    )

    private companion object {
        private const val TAG = "RoanaV0a"
        private const val MODEL_ASSET = "depth_anything_v2.tflite"
        private const val NS_PER_MS = 1_000_000.0
    }
}
