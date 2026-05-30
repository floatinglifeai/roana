package com.roana.app

import android.content.Context
import android.util.Log
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter

class DepthAnythingRunner(
    context: Context,
    private var backend: InferenceBackend =
        InferenceBackend.create(
            context = context,
            precision = InferenceBackend.Precision.FP16,
        ),
    private val preprocessor: DepthFramePreprocessor = DepthFramePreprocessor(),
) : AutoCloseable {
    private val modelBuffer = context.assets.openFd(MODEL_ASSET).use { descriptor ->
        FileInputStream(descriptor.fileDescriptor).channel.use { channel ->
            channel.map(FileChannel.MapMode.READ_ONLY, descriptor.startOffset, descriptor.declaredLength)
        }
    }
    private val interpreter = createInterpreterWithFallback()
    private val inputTensor = interpreter.getInputTensor(0)
    private val outputTensor = interpreter.getOutputTensor(0)
    private val inputBuffer = preprocessor.newInputBuffer()
    private val outputBuffer = DepthAnythingTensor.newOutputBuffer()
    private val outputScratch = DepthAnythingTensor.newOutputScratch()

    val backendName: String
        get() = backend.name
    val inputShape: IntArray = inputTensor.shape().copyOf()
    val outputShape: IntArray = outputTensor.shape().copyOf()

    init {
        require(inputShape.contentEquals(intArrayOf(1, DepthAnythingTensor.INPUT_HEIGHT, DepthAnythingTensor.INPUT_WIDTH, RGB_CHANNELS))) {
            "Unexpected Depth Anything input shape ${inputShape.contentToString()}"
        }
        require(inputTensor.dataType() == DataType.FLOAT32) {
            "Unexpected Depth Anything input type ${inputTensor.dataType()}"
        }
        require(outputShape.contentEquals(intArrayOf(1, DepthAnythingTensor.OUTPUT_HEIGHT, DepthAnythingTensor.OUTPUT_WIDTH, DepthAnythingTensor.OUTPUT_CHANNELS))) {
            "Unexpected Depth Anything output shape ${outputShape.contentToString()}"
        }
        require(outputTensor.dataType() == DataType.FLOAT32) {
            "Unexpected Depth Anything output type ${outputTensor.dataType()}"
        }
    }

    fun infer(frame: DepthFramePreprocessor.RgbFrame): DepthResult =
        infer(frame.asSampler())

    fun infer(sampler: DepthFramePreprocessor.RgbSampler): DepthResult =
        infer(preprocessor.fillInputBuffer(sampler, inputBuffer), includeDepthMap = true)

    fun inferGrid(sampler: DepthFramePreprocessor.RgbSampler): DepthGridResult =
        inferGridTimed(sampler)

    fun inferGrid(inputBuffer: ByteBuffer): DepthGridResult =
        runInterpreter(inputBuffer).let { inferenceMs ->
            DepthGridResult(
                depthGrid = DepthAnythingTensor.outputToPlannerGrid(outputBuffer, scratch = outputScratch),
                inferenceMs = inferenceMs,
            )
        }

    fun inferGridTimed(sampler: DepthFramePreprocessor.RgbSampler): DepthGridResult {
        val totalStartedNs = System.nanoTime()
        val inputStartedNs = System.nanoTime()
        val preparedInput = preprocessor.fillInputBuffer(sampler, inputBuffer)
        val inputMs = elapsedMs(inputStartedNs)

        val inferenceMs = runInterpreter(preparedInput)

        val gridStartedNs = System.nanoTime()
        val depthGrid = DepthAnythingTensor.outputToPlannerGrid(outputBuffer, scratch = outputScratch)
        val gridMs = elapsedMs(gridStartedNs)

        return DepthGridResult(
            depthGrid = depthGrid,
            inferenceMs = inferenceMs,
            timing = DepthTiming(
                inputMs = inputMs,
                inferenceMs = inferenceMs,
                outputGridMs = gridMs,
                totalMs = elapsedMs(totalStartedNs),
            ),
        )
    }

    fun infer(inputBuffer: ByteBuffer): DepthResult =
        infer(inputBuffer, includeDepthMap = true)

    private fun infer(
        inputBuffer: ByteBuffer,
        includeDepthMap: Boolean,
    ): DepthResult {
        val inferenceMs = runInterpreter(inputBuffer)
        val depthMap = if (includeDepthMap) DepthAnythingTensor.flattenOutput(outputBuffer) else null
        return DepthResult(
            depthMap = depthMap,
            depthGrid = DepthAnythingTensor.outputToPlannerGrid(outputBuffer, scratch = outputScratch),
            inferenceMs = inferenceMs,
        )
    }

    private fun runInterpreter(inputBuffer: ByteBuffer): Double {
        require(inputBuffer.capacity() == preprocessor.inputByteCount) {
            "Expected ${preprocessor.inputByteCount}-byte depth input buffer, got ${inputBuffer.capacity()}"
        }

        val startedNs = System.nanoTime()
        inputBuffer.rewind()
        outputBuffer.clear()
        interpreter.run(inputBuffer, outputBuffer)
        outputBuffer.rewind()
        return elapsedMs(startedNs)
    }

    private fun elapsedMs(startedNs: Long): Double =
        (System.nanoTime() - startedNs).toDouble() / NS_PER_MS

    override fun close() {
        interpreter.close()
        backend.close()
    }

    private fun createInterpreterWithFallback(): Interpreter =
        try {
            Interpreter(
                modelBuffer,
                backend.applyTo(Interpreter.Options().setNumThreads(2)),
            )
        } catch (error: Exception) {
            if (!backend.usesDelegate) {
                throw error
            }

            Log.w(TAG, "depth_backend selected=cpu_xnnpack reason=qnn_interpreter_failed", error)
            backend.close()
            backend = InferenceBackend.cpu(
                reason = "${error.javaClass.simpleName}:${error.message.orEmpty()}",
            )
            Interpreter(
                modelBuffer,
                backend.applyTo(Interpreter.Options().setNumThreads(2)),
            )
        }

    data class DepthResult(
        val depthMap: DepthAnythingTensor.DepthMap?,
        val depthGrid: CorridorPlanner.DepthGrid,
        val inferenceMs: Double,
    )

    data class DepthGridResult(
        val depthGrid: CorridorPlanner.DepthGrid,
        val inferenceMs: Double,
        val timing: DepthTiming? = null,
    )

    data class DepthTiming(
        val inputMs: Double,
        val inferenceMs: Double,
        val outputGridMs: Double,
        val totalMs: Double,
    )

    private companion object {
        private const val TAG = "RoanaV0a"
        private const val MODEL_ASSET = "depth_anything_v2.tflite"
        private const val RGB_CHANNELS = 3
        private const val NS_PER_MS = 1_000_000.0
    }
}
