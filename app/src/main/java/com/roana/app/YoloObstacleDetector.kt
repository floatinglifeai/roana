package com.roana.app

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import androidx.camera.core.ImageProxy
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.roundToInt
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter

class YoloObstacleDetector(
    context: Context,
    backend: InferenceBackend,
) : AutoCloseable {
    private var backend = backend
    private val labels = context.assets.open(LABELS_ASSET).bufferedReader().useLines { lines ->
        lines.map { it.trim() }.filter { it.isNotEmpty() }.toList()
    }
    private val modelBuffer = context.assets.openFd(MODEL_ASSET).use { descriptor ->
        FileInputStream(descriptor.fileDescriptor).channel.use { channel ->
            channel.map(FileChannel.MapMode.READ_ONLY, descriptor.startOffset, descriptor.declaredLength)
        }
    }
    private val interpreter = createInterpreterWithFallback()
    private val inputShape = interpreter.getInputTensor(0).shape()
    private val inputWidth = inputShape[2]
    private val inputHeight = inputShape[1]
    private val inputBuffer = ByteBuffer
        .allocateDirect(inputWidth * inputHeight * RGB_CHANNELS)
        .order(ByteOrder.nativeOrder())
    private val outputTensors = (0 until interpreter.getOutputTensorCount()).map { index ->
        val tensor = interpreter.getOutputTensor(index)
        val shape = tensor.shape()
        val quantization = tensor.quantizationParams()
        TensorOutput(
            index = index,
            shape = shape,
            quantization = Quantization(
                scale = quantization.scale,
                zeroPoint = quantization.zeroPoint,
            ),
            buffer = ByteBuffer
                .allocateDirect(shape.product() * BYTE_SIZE)
                .order(ByteOrder.nativeOrder()),
        )
    }
    private val outputMap: Map<Int, Any> = outputTensors.associate { it.index to it.buffer as Any }
    private val scaleOutputs = buildScaleOutputs()

    init {
        require(inputShape.contentEquals(intArrayOf(1, INPUT_SIZE, INPUT_SIZE, RGB_CHANNELS))) {
            "Expected [1,640,640,3] UINT8 YOLO input tensor, got ${inputShape.contentToString()}"
        }
        require(interpreter.getInputTensor(0).dataType() == DataType.UINT8) {
            "Expected UINT8 YOLO input tensor, got ${interpreter.getInputTensor(0).dataType()}"
        }
        require(labels.size == COCO_CLASS_COUNT) {
            "Expected $COCO_CLASS_COUNT COCO labels, got ${labels.size}"
        }
        require(scaleOutputs.size == YOLO_SCALE_COUNT) {
            "Expected $YOLO_SCALE_COUNT YOLO scale outputs, got ${scaleOutputs.size}"
        }
    }

    fun detect(image: ImageProxy): YoloResult {
        val startedNs = System.nanoTime()
        val bitmap = CameraFrameConverter.toBitmap(image, inputWidth, inputHeight)
        try {
            fillInput(bitmap)
        } finally {
            bitmap.recycle()
        }

        outputTensors.forEach { it.buffer.rewind() }
        interpreter.runForMultipleInputsOutputs(arrayOf(inputBuffer), outputMap)
        outputTensors.forEach { it.buffer.rewind() }

        val bestDetection = bestDetection()
        val inferenceMs = (System.nanoTime() - startedNs).toDouble() / NS_PER_MS
        return YoloResult(
            inferenceMs = inferenceMs,
            bestDetection = bestDetection,
        )
    }

    override fun close() {
        interpreter.close()
        backend.close()
    }

    private fun createInterpreterWithFallback(): Interpreter =
        try {
            Interpreter(modelBuffer, interpreterOptions(backend))
        } catch (error: Exception) {
            if (!backend.usesDelegate) {
                throw error
            }

            Log.w(
                TAG,
                "inference_backend selected=cpu_xnnpack precision=quantized " +
                    "reason=qnn_interpreter_failed",
                error,
            )
            backend.close()
            backend = InferenceBackend.cpu(
                reason = "${error.javaClass.simpleName}:${error.message.orEmpty()}",
            )
            Interpreter(modelBuffer, interpreterOptions(backend))
        }

    private fun interpreterOptions(backend: InferenceBackend): Interpreter.Options =
        backend.applyTo(
            Interpreter.Options().apply {
                setNumThreads(2)
            },
        )

    private fun buildScaleOutputs(): List<ScaleOutput> {
        outputTensors.forEach { output ->
            require(output.shape.size == 4 && output.shape[0] == 1) {
                "Expected 4D batch-one YOLO output tensor, got ${output.shape.contentToString()}"
            }
            require(interpreter.getOutputTensor(output.index).dataType() == DataType.INT8) {
                "Expected INT8 YOLO output tensor ${output.index}, got " +
                    interpreter.getOutputTensor(output.index).dataType()
            }
            require(output.quantization.scale > 0f) {
                "Expected quantized YOLO output tensor ${output.index}, got scale=${output.quantization.scale}"
            }
        }

        val boxOutputs = outputTensors.filter { it.channels == BOX_CHANNELS }
        val scoreOutputs = outputTensors.filter { it.channels == labels.size }
        return scoreOutputs.map { scores ->
            val boxes = boxOutputs.singleOrNull { boxes ->
                boxes.gridHeight == scores.gridHeight && boxes.gridWidth == scores.gridWidth
            } ?: error("Missing boxes output for scores shape ${scores.shape.contentToString()}")
            ScaleOutput(boxes = boxes, scores = scores)
        }.sortedByDescending { it.scores.gridWidth }
    }

    private fun fillInput(bitmap: Bitmap) {
        inputBuffer.rewind()
        val pixels = IntArray(inputWidth * inputHeight)
        bitmap.getPixels(pixels, 0, inputWidth, 0, 0, inputWidth, inputHeight)
        pixels.forEach { pixel ->
            inputBuffer.put(((pixel shr 16) and BYTE_MASK).toByte())
            inputBuffer.put(((pixel shr 8) and BYTE_MASK).toByte())
            inputBuffer.put((pixel and BYTE_MASK).toByte())
        }
        inputBuffer.rewind()
    }

    private fun bestDetection(): YoloDetection? {
        val personClass = labels.indexOf(PERSON_LABEL).takeIf { it >= 0 } ?: 0
        var bestScore = Float.NEGATIVE_INFINITY
        var bestRow = 0
        var bestCol = 0
        var bestScale: ScaleOutput? = null

        scaleOutputs.forEach { scale ->
            for (row in 0 until scale.scores.gridHeight) {
                for (col in 0 until scale.scores.gridWidth) {
                    val score = tensorValue(
                        output = scale.scores,
                        row = row,
                        col = col,
                        channel = personClass,
                    )
                    if (score > bestScore) {
                        bestScore = score
                        bestRow = row
                        bestCol = col
                        bestScale = scale
                    }
                }
            }
        }

        val detectionScore = bestScore.coerceIn(0f, 1f)
        val scale = bestScale
        if (scale == null || detectionScore < PERSON_ALERT_THRESHOLD) {
            return null
        }

        val box = decodeBox(scale.boxes, bestRow, bestCol)
        return YoloDetection(
            label = labels[personClass],
            score = detectionScore,
            centerX = ((box.left + box.right) / 2f).coerceIn(0f, 1f),
            centerY = ((box.top + box.bottom) / 2f).coerceIn(0f, 1f),
            width = max(0f, box.right - box.left).coerceAtMost(1f),
            height = max(0f, box.bottom - box.top).coerceAtMost(1f),
        )
    }

    private fun decodeBox(output: TensorOutput, row: Int, col: Int): NormalizedBox {
        val leftOffset = dflOffset(output, row, col, side = 0)
        val topOffset = dflOffset(output, row, col, side = 1)
        val rightOffset = dflOffset(output, row, col, side = 2)
        val bottomOffset = dflOffset(output, row, col, side = 3)
        val anchorX = col + ANCHOR_CENTER_OFFSET
        val anchorY = row + ANCHOR_CENTER_OFFSET

        return NormalizedBox(
            left = ((anchorX - leftOffset) / output.gridWidth).coerceIn(0f, 1f),
            top = ((anchorY - topOffset) / output.gridHeight).coerceIn(0f, 1f),
            right = ((anchorX + rightOffset) / output.gridWidth).coerceIn(0f, 1f),
            bottom = ((anchorY + bottomOffset) / output.gridHeight).coerceIn(0f, 1f),
        )
    }

    private fun dflOffset(output: TensorOutput, row: Int, col: Int, side: Int): Float {
        val logits = FloatArray(DFL_BINS)
        var maxLogit = Float.NEGATIVE_INFINITY
        for (bin in 0 until DFL_BINS) {
            val value = tensorValue(
                output = output,
                row = row,
                col = col,
                channel = side * DFL_BINS + bin,
            )
            logits[bin] = value
            if (value > maxLogit) {
                maxLogit = value
            }
        }

        var sum = 0f
        var weightedSum = 0f
        for (bin in 0 until DFL_BINS) {
            val probability = exp((logits[bin] - maxLogit).toDouble()).toFloat()
            sum += probability
            weightedSum += probability * bin
        }

        return if (sum > 0f) weightedSum / sum else 0f
    }

    private fun tensorValue(output: TensorOutput, row: Int, col: Int, channel: Int): Float {
        val offset = ((row * output.gridWidth + col) * output.channels) + channel
        return dequantize(output.buffer.get(offset), output.quantization)
    }

    private fun dequantize(value: Byte, quantization: Quantization): Float =
        quantization.scale * (value.toInt() - quantization.zeroPoint)

    data class YoloResult(
        val inferenceMs: Double,
        val bestDetection: YoloDetection?,
    )

    data class YoloDetection(
        val label: String,
        val score: Float,
        val centerX: Float,
        val centerY: Float,
        val width: Float,
        val height: Float,
    ) {
        fun scorePercent(): Int = (score * 100).roundToInt()
    }

    private data class TensorOutput(
        val index: Int,
        val shape: IntArray,
        val quantization: Quantization,
        val buffer: ByteBuffer,
    ) {
        val gridHeight: Int = shape[1]
        val gridWidth: Int = shape[2]
        val channels: Int = shape[3]
    }

    private data class Quantization(
        val scale: Float,
        val zeroPoint: Int,
    )

    private data class ScaleOutput(
        val boxes: TensorOutput,
        val scores: TensorOutput,
    )

    private data class NormalizedBox(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
    )

    private companion object {
        private const val TAG = "RoanaV0a"
        private const val MODEL_ASSET = "yolo11n-det-int8-smart.tflite"
        private const val LABELS_ASSET = "coco-labels.txt"
        private const val INPUT_SIZE = 640
        private const val RGB_CHANNELS = 3
        private const val BYTE_MASK = 0xFF
        private const val BYTE_SIZE = 1
        private const val COCO_CLASS_COUNT = 80
        private const val BOX_CHANNELS = 64
        private const val DFL_BINS = 16
        private const val YOLO_SCALE_COUNT = 3
        private const val ANCHOR_CENTER_OFFSET = 0.5f
        private const val NS_PER_MS = 1_000_000.0
        private const val PERSON_LABEL = "person"
        private const val PERSON_ALERT_THRESHOLD = 0.35f
    }
}

private fun IntArray.product(): Int = fold(1) { product, value -> product * value }
