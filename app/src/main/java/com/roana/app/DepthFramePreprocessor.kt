package com.roana.app

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.floor
import kotlin.math.min

class DepthFramePreprocessor(
    val targetWidth: Int = DEPTH_INPUT_WIDTH,
    val targetHeight: Int = DEPTH_INPUT_HEIGHT,
) {
    init {
        require(targetWidth > 0 && targetHeight > 0) { "Target dimensions must be positive" }
    }

    val inputByteCount: Int = targetWidth * targetHeight * RGB_CHANNELS * FLOAT_SIZE

    fun newInputBuffer(): ByteBuffer =
        ByteBuffer.allocateDirect(inputByteCount).order(ByteOrder.nativeOrder())

    fun toInputBuffer(frame: RgbFrame): ByteBuffer =
        fillInputBuffer(frame, newInputBuffer())

    fun fillInputBuffer(frame: RgbFrame, output: ByteBuffer): ByteBuffer =
        fillInputBuffer(frame.asSampler(), output)

    fun fillInputBuffer(sampler: RgbSampler, output: ByteBuffer): ByteBuffer {
        require(output.capacity() == inputByteCount) {
            "Expected $inputByteCount-byte depth input buffer, got ${output.capacity()}"
        }

        val cropSize = min(sampler.width, sampler.height).toFloat()
        val xOffset = (sampler.width - cropSize) / 2f
        val yOffset = (sampler.height - cropSize) / 2f

        output.clear()
        for (targetY in 0 until targetHeight) {
            val sourceY = yOffset + ((targetY + 0.5f) * cropSize / targetHeight) - 0.5f
            for (targetX in 0 until targetWidth) {
                val sourceX = xOffset + ((targetX + 0.5f) * cropSize / targetWidth) - 0.5f
                val color = sampleBilinear(sampler, sourceX, sourceY)
                output.putFloat(color.red)
                output.putFloat(color.green)
                output.putFloat(color.blue)
            }
        }
        output.rewind()
        return output
    }

    private fun sampleBilinear(sampler: RgbSampler, sourceX: Float, sourceY: Float): RgbFloat {
        val left = floor(sourceX).toInt().coerceIn(0, sampler.width - 1)
        val top = floor(sourceY).toInt().coerceIn(0, sampler.height - 1)
        val right = (left + 1).coerceAtMost(sampler.width - 1)
        val bottom = (top + 1).coerceAtMost(sampler.height - 1)
        val xWeight = (sourceX - left).coerceIn(0f, 1f)
        val yWeight = (sourceY - top).coerceIn(0f, 1f)

        val topLeft = sampler.rgbAt(left, top)
        val topRight = sampler.rgbAt(right, top)
        val bottomLeft = sampler.rgbAt(left, bottom)
        val bottomRight = sampler.rgbAt(right, bottom)

        return RgbFloat(
            red = bilinear(
                topLeft.red,
                topRight.red,
                bottomLeft.red,
                bottomRight.red,
                xWeight,
                yWeight,
            ),
            green = bilinear(
                topLeft.green,
                topRight.green,
                bottomLeft.green,
                bottomRight.green,
                xWeight,
                yWeight,
            ),
            blue = bilinear(
                topLeft.blue,
                topRight.blue,
                bottomLeft.blue,
                bottomRight.blue,
                xWeight,
                yWeight,
            ),
        )
    }

    private fun bilinear(
        topLeft: Float,
        topRight: Float,
        bottomLeft: Float,
        bottomRight: Float,
        xWeight: Float,
        yWeight: Float,
    ): Float {
        val top = topLeft + (topRight - topLeft) * xWeight
        val bottom = bottomLeft + (bottomRight - bottomLeft) * xWeight
        return top + (bottom - top) * yWeight
    }

    data class RgbFrame(
        val width: Int,
        val height: Int,
        val pixels: IntArray,
    ) {
        init {
            require(width > 0 && height > 0) { "RGB frame dimensions must be positive" }
            require(pixels.size == width * height) {
                "RGB frame pixel count ${pixels.size} does not match ${width}x$height"
            }
        }

        fun asSampler(): RgbSampler =
            object : RgbSampler {
                override val width: Int = this@RgbFrame.width
                override val height: Int = this@RgbFrame.height

                override fun rgbAt(x: Int, y: Int): RgbFloat =
                    this@RgbFrame.rgbAt(x, y)
            }

        fun rgbAt(x: Int, y: Int): RgbFloat {
            val pixel = pixels[y * width + x]
            return RgbFloat(
                red = ((pixel shr RED_SHIFT) and BYTE_MASK) / BYTE_MAX,
                green = ((pixel shr GREEN_SHIFT) and BYTE_MASK) / BYTE_MAX,
                blue = (pixel and BYTE_MASK) / BYTE_MAX,
            )
        }
    }

    data class RgbFloat(
        val red: Float,
        val green: Float,
        val blue: Float,
    )

    interface RgbSampler {
        val width: Int
        val height: Int

        fun rgbAt(x: Int, y: Int): RgbFloat
    }

    companion object {
        const val DEPTH_INPUT_WIDTH = 518
        const val DEPTH_INPUT_HEIGHT = 518
        const val RGB_CHANNELS = 3
        const val FLOAT_SIZE = 4
        private const val RED_SHIFT = 16
        private const val GREEN_SHIFT = 8
        private const val BYTE_MASK = 0xFF
        private const val BYTE_MAX = 255f
    }
}
