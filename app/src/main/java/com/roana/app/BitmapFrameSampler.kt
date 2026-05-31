package com.roana.app

import android.graphics.Bitmap
import java.nio.ByteBuffer

class BitmapFrameSampler(
    private val bitmap: Bitmap,
    private val rotationDegrees: Int = 0,
) : DepthFramePreprocessor.FastDepthInputSampler {
    private val pixels = IntArray(bitmap.width * bitmap.height).also { pixels ->
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
    }

    init {
        require(!bitmap.isRecycled) { "Bitmap is recycled" }
        require(rotationDegrees in SUPPORTED_ROTATIONS) {
            "Unsupported bitmap rotation $rotationDegrees"
        }
    }

    override val width: Int =
        if (rotationDegrees == 90 || rotationDegrees == 270) bitmap.height else bitmap.width

    override val height: Int =
        if (rotationDegrees == 90 || rotationDegrees == 270) bitmap.width else bitmap.height

    override fun rgbAt(x: Int, y: Int): DepthFramePreprocessor.RgbFloat {
        val color = pixelAt(x, y)
        return DepthFramePreprocessor.RgbFloat(
            red = ((color shr RED_SHIFT) and BYTE_MASK) / BYTE_MAX.toFloat(),
            green = ((color shr GREEN_SHIFT) and BYTE_MASK) / BYTE_MAX.toFloat(),
            blue = (color and BYTE_MASK) / BYTE_MAX.toFloat(),
        )
    }

    fun fillYoloInputNearest(
        targetWidth: Int,
        targetHeight: Int,
        output: ByteBuffer,
        scratch: ByteArray,
        lumaOnly: Boolean = true,
    ): ByteBuffer {
        require(targetWidth > 0 && targetHeight > 0) { "Target dimensions must be positive" }
        val expectedBytes = targetWidth * targetHeight * RGB_CHANNELS
        require(output.capacity() == expectedBytes) {
            "Expected $expectedBytes-byte YOLO input buffer, got ${output.capacity()}"
        }
        require(scratch.size == expectedBytes) {
            "Expected $expectedBytes-byte YOLO input scratch, got ${scratch.size}"
        }

        val sourceXs = IntArray(targetWidth) { targetX ->
            nearestSource(targetX, width, targetWidth, offset = 0)
        }
        val sourceYs = IntArray(targetHeight) { targetY ->
            nearestSource(targetY, height, targetHeight, offset = 0)
        }
        var outputIndex = 0
        for (targetY in 0 until targetHeight) {
            val sourceY = sourceYs[targetY]
            for (targetX in 0 until targetWidth) {
                val sourceX = sourceXs[targetX]
                if (lumaOnly) {
                    val luma = lumaByteAt(sourceX, sourceY).toByte()
                    scratch[outputIndex] = luma
                    scratch[outputIndex + 1] = luma
                    scratch[outputIndex + 2] = luma
                } else {
                    val color = pixelAt(sourceX, sourceY)
                    scratch[outputIndex] = ((color shr RED_SHIFT) and BYTE_MASK).toByte()
                    scratch[outputIndex + 1] = ((color shr GREEN_SHIFT) and BYTE_MASK).toByte()
                    scratch[outputIndex + 2] = (color and BYTE_MASK).toByte()
                }
                outputIndex += RGB_CHANNELS
            }
        }

        output.clear()
        output.put(scratch)
        output.rewind()
        return output
    }

    override fun fillDepthInputNearest(
        targetWidth: Int,
        targetHeight: Int,
        output: ByteBuffer,
        scratch: FloatArray,
        sourceXs: IntArray,
        sourceYs: IntArray,
    ): ByteBuffer {
        require(targetWidth > 0 && targetHeight > 0) { "Target dimensions must be positive" }
        val expectedBytes = targetWidth * targetHeight * RGB_CHANNELS * FLOAT_SIZE
        require(output.capacity() == expectedBytes) {
            "Expected $expectedBytes-byte depth input buffer, got ${output.capacity()}"
        }
        require(scratch.size == targetWidth * targetHeight * RGB_CHANNELS) {
            "Expected ${targetWidth * targetHeight * RGB_CHANNELS}-float depth scratch, got ${scratch.size}"
        }
        require(sourceXs.size == targetWidth) {
            "Expected $targetWidth cached depth x coordinates, got ${sourceXs.size}"
        }
        require(sourceYs.size == targetHeight) {
            "Expected $targetHeight cached depth y coordinates, got ${sourceYs.size}"
        }

        val cropSize = minOf(width, height)
        val xOffset = (width - cropSize) / 2
        val yOffset = (height - cropSize) / 2
        for (targetX in 0 until targetWidth) {
            sourceXs[targetX] = nearestSource(targetX, cropSize, targetWidth, xOffset)
        }
        for (targetY in 0 until targetHeight) {
            sourceYs[targetY] = nearestSource(targetY, cropSize, targetHeight, yOffset)
        }

        var outputIndex = 0
        for (targetY in 0 until targetHeight) {
            val sourceY = sourceYs[targetY]
            for (targetX in 0 until targetWidth) {
                val luma = lumaByteAt(sourceXs[targetX], sourceY) / BYTE_MAX.toFloat()
                scratch[outputIndex] = luma
                scratch[outputIndex + 1] = luma
                scratch[outputIndex + 2] = luma
                outputIndex += RGB_CHANNELS
            }
        }

        output.clear()
        output.asFloatBuffer().put(scratch)
        output.rewind()
        return output
    }

    private fun pixelAt(x: Int, y: Int): Int {
        val sourceX: Int
        val sourceY: Int
        when (rotationDegrees) {
            0 -> {
                sourceX = x
                sourceY = y
            }
            90 -> {
                sourceX = y
                sourceY = bitmap.height - 1 - x
            }
            180 -> {
                sourceX = bitmap.width - 1 - x
                sourceY = bitmap.height - 1 - y
            }
            270 -> {
                sourceX = bitmap.width - 1 - y
                sourceY = x
            }
            else -> error("Unsupported bitmap rotation $rotationDegrees")
        }
        return pixels[sourceY * bitmap.width + sourceX]
    }

    private fun lumaByteAt(x: Int, y: Int): Int {
        val color = pixelAt(x, y)
        val red = (color shr RED_SHIFT) and BYTE_MASK
        val green = (color shr GREEN_SHIFT) and BYTE_MASK
        val blue = color and BYTE_MASK
        return ((red * RED_LUMA) + (green * GREEN_LUMA) + (blue * BLUE_LUMA)) / LUMA_SCALE
    }

    private fun nearestSource(
        target: Int,
        sourceSize: Int,
        targetSize: Int,
        offset: Int,
    ): Int =
        (offset + ((target * sourceSize) + (sourceSize / 2)) / targetSize)
            .coerceIn(offset, offset + sourceSize - 1)

    private companion object {
        private const val RGB_CHANNELS = 3
        private const val FLOAT_SIZE = 4
        private const val RED_SHIFT = 16
        private const val GREEN_SHIFT = 8
        private const val BYTE_MASK = 0xFF
        private const val BYTE_MAX = 255
        private const val RED_LUMA = 299
        private const val GREEN_LUMA = 587
        private const val BLUE_LUMA = 114
        private const val LUMA_SCALE = 1000
        private val SUPPORTED_ROTATIONS = setOf(0, 90, 180, 270)
    }
}
