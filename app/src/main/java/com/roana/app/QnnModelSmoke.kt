package com.roana.app

import android.content.Context
import android.util.Log
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.util.Locale
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.Tensor

class QnnModelSmoke(private val context: Context) {
    fun runYolo(
        variant: QnnVariant = QnnVariant.DEFAULT,
        timingIterations: Int = 0,
    ) {
        run(
            spec = ModelSpec(
                name = "yolo",
                asset = YOLO_ASSET,
                precision = InferenceBackend.Precision.QUANTIZED,
            ),
            variant = variant,
            timingIterations = timingIterations,
        )
    }

    fun runDepth(
        variant: QnnVariant = QnnVariant.DEFAULT,
        timingIterations: Int = 0,
    ) {
        run(
            spec = ModelSpec(
                name = "depth",
                asset = DEPTH_ASSET,
                precision = InferenceBackend.Precision.FP16,
            ),
            variant = variant,
            timingIterations = timingIterations,
        )
    }

    private fun run(
        spec: ModelSpec,
        variant: QnnVariant,
        timingIterations: Int,
    ) {
        val startedNs = System.nanoTime()
        val model = loadModel(spec.asset)
        logCpuMetadata(spec, model)

        val backend = InferenceBackend.create(
            context = context,
            precision = spec.precision,
            variant = variant,
        )
        if (!backend.usesDelegate) {
            Log.w(
                TAG,
                "qnn_model_smoke status=unavailable model=${spec.name} " +
                    "asset=${spec.asset} precision=${spec.precision.logValue} " +
                    "variant=${variant.id} backend=${backend.name} " +
                    "reason=${backend.failureReason ?: "none"}",
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
                        "variant=${variant.id} backend=${backend.name} " +
                        "load_ms=${"%.2f".format(Locale.US, loadMs)} " +
                        "inputs=${inputSummary(interpreter)} outputs=${outputSummary(interpreter)}",
                )
                if (timingIterations > 0) {
                    runTiming(spec, variant, interpreter, timingIterations)
                }
            }
        } catch (error: Exception) {
            Log.e(
                TAG,
                "qnn_model_smoke status=failed model=${spec.name} " +
                    "asset=${spec.asset} precision=${spec.precision.logValue} " +
                    "variant=${variant.id} backend=${backend.name} " +
                    "error=${error.javaClass.simpleName} " +
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

    private fun runTiming(
        spec: ModelSpec,
        variant: QnnVariant,
        interpreter: Interpreter,
        iterations: Int,
    ) {
        val inputBuffer = interpreter.getInputTensor(0).newZeroBuffer()
        val outputs = (0 until interpreter.outputTensorCount).associateWith { outputIndex ->
            interpreter.getOutputTensor(outputIndex).newZeroBuffer() as Any
        }
        val inputs = arrayOf<Any>(inputBuffer)

        runInterpreter(interpreter, inputs, outputs)
        val runTimesMs = DoubleArray(iterations)
        for (index in 0 until iterations) {
            inputBuffer.rewind()
            outputs.values.forEach { output ->
                if (output is ByteBuffer) {
                    output.rewind()
                }
            }
            val startedNs = System.nanoTime()
            runInterpreter(interpreter, inputs, outputs)
            runTimesMs[index] = (System.nanoTime() - startedNs).toDouble() / NS_PER_MS
        }

        val averageMs = runTimesMs.average()
        val minMs = runTimesMs.minOrNull() ?: 0.0
        val maxMs = runTimesMs.maxOrNull() ?: 0.0
        Log.i(
            TAG,
            "qnn_model_timing status=ok model=${spec.name} variant=${variant.id} " +
                "iterations=$iterations avg_ms=${"%.2f".format(Locale.US, averageMs)} " +
                "min_ms=${"%.2f".format(Locale.US, minMs)} " +
                "max_ms=${"%.2f".format(Locale.US, maxMs)}",
        )
    }

    private fun runInterpreter(
        interpreter: Interpreter,
        inputs: Array<Any>,
        outputs: Map<Int, Any>,
    ) {
        if (outputs.size == 1) {
            interpreter.run(inputs[0], outputs.getValue(0))
        } else {
            interpreter.runForMultipleInputsOutputs(inputs, outputs)
        }
    }

    private fun Tensor.newZeroBuffer(): ByteBuffer {
        val byteCount = shape().product() * dataType().byteSize()
        return ByteBuffer.allocateDirect(byteCount).order(ByteOrder.nativeOrder())
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

private fun IntArray.product(): Int =
    fold(1) { product, value -> product * value }

private fun DataType.byteSize(): Int =
    when (this) {
        DataType.FLOAT32, DataType.INT32 -> 4
        DataType.UINT8, DataType.INT8, DataType.BOOL -> 1
        else -> error("Unsupported tensor data type $this")
    }

private fun String.sanitizeLogValue(): String =
    replace('\n', ' ')
        .replace('\r', ' ')
        .replace(' ', '_')
