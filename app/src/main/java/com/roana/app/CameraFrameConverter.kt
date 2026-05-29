package com.roana.app

import android.graphics.ImageFormat
import androidx.camera.core.ImageProxy
import java.nio.ByteBuffer
import kotlin.math.floor
import kotlin.math.roundToInt

object CameraFrameConverter {
    fun toRgbFrame(image: ImageProxy): DepthFramePreprocessor.RgbFrame {
        require(image.format == ImageFormat.YUV_420_888) {
            "Expected YUV_420_888 image, got ${image.format}"
        }
        return yuv420ToRgbFrame(image.toYuvFrame())
    }

    fun toYuvSampler(image: ImageProxy): DepthFramePreprocessor.RgbSampler {
        require(image.format == ImageFormat.YUV_420_888) {
            "Expected YUV_420_888 image, got ${image.format}"
        }
        return image.toYuvFrame()
    }

    fun fillRgbInput(
        image: ImageProxy,
        targetWidth: Int,
        targetHeight: Int,
        output: ByteBuffer,
    ): ByteBuffer {
        require(image.format == ImageFormat.YUV_420_888) {
            "Expected YUV_420_888 image, got ${image.format}"
        }
        return fillRgbInput(
            sampler = image.toYuvFrame(),
            targetWidth = targetWidth,
            targetHeight = targetHeight,
            output = output,
        )
    }

    fun fillYuv420RgbInput(
        width: Int,
        height: Int,
        rotationDegrees: Int,
        yPlane: YuvPlane,
        uPlane: YuvPlane,
        vPlane: YuvPlane,
        targetWidth: Int,
        targetHeight: Int,
        output: ByteBuffer,
    ): ByteBuffer =
        fillRgbInput(
            sampler = YuvFrame(
                sourceWidth = width,
                sourceHeight = height,
                rotationDegrees = rotationDegrees,
                yPlane = yPlane,
                uPlane = uPlane,
                vPlane = vPlane,
            ),
            targetWidth = targetWidth,
            targetHeight = targetHeight,
            output = output,
        )

    fun yuv420ToRgbFrame(
        width: Int,
        height: Int,
        rotationDegrees: Int,
        yPlane: YuvPlane,
        uPlane: YuvPlane,
        vPlane: YuvPlane,
    ): DepthFramePreprocessor.RgbFrame =
        yuv420ToRgbFrame(
            YuvFrame(
                sourceWidth = width,
                sourceHeight = height,
                rotationDegrees = rotationDegrees,
                yPlane = yPlane,
                uPlane = uPlane,
                vPlane = vPlane,
            ),
        )

    private fun fillRgbInput(
        sampler: YuvFrame,
        targetWidth: Int,
        targetHeight: Int,
        output: ByteBuffer,
    ): ByteBuffer {
        require(targetWidth > 0 && targetHeight > 0) { "Target dimensions must be positive" }
        val expectedBytes = targetWidth * targetHeight * RGB_CHANNELS
        require(output.capacity() == expectedBytes) {
            "Expected $expectedBytes-byte RGB input buffer, got ${output.capacity()}"
        }

        output.clear()
        for (targetY in 0 until targetHeight) {
            val sourceY = ((targetY + 0.5f) * sampler.height / targetHeight) - 0.5f
            for (targetX in 0 until targetWidth) {
                val sourceX = ((targetX + 0.5f) * sampler.width / targetWidth) - 0.5f
                sampler.putBilinearRgb(sourceX, sourceY, output)
            }
        }
        output.rewind()
        return output
    }

    private fun yuv420ToRgbFrame(sampler: YuvFrame): DepthFramePreprocessor.RgbFrame {
        val pixels = IntArray(sampler.width * sampler.height)
        for (targetY in 0 until sampler.height) {
            for (targetX in 0 until sampler.width) {
                pixels[targetY * sampler.width + targetX] = sampler.rgbIntAt(targetX, targetY)
            }
        }

        return DepthFramePreprocessor.RgbFrame(
            width = sampler.width,
            height = sampler.height,
            pixels = pixels,
        )
    }

    private fun ImageProxy.toYuvFrame(): YuvFrame =
        YuvFrame(
            sourceWidth = width,
            sourceHeight = height,
            rotationDegrees = imageInfo.rotationDegrees,
            yPlane = planes[0].toYuvPlane(),
            uPlane = planes[1].toYuvPlane(),
            vPlane = planes[2].toYuvPlane(),
        )

    class YuvFrame(
        private val sourceWidth: Int,
        private val sourceHeight: Int,
        private val rotationDegrees: Int,
        private val yPlane: YuvPlane,
        private val uPlane: YuvPlane,
        private val vPlane: YuvPlane,
    ) : DepthFramePreprocessor.RgbSampler {
        init {
            require(sourceWidth > 0 && sourceHeight > 0) { "YUV frame dimensions must be positive" }
            require(rotationDegrees in SUPPORTED_ROTATIONS) {
                "Unsupported YUV rotation $rotationDegrees"
            }
        }

        override val width: Int =
            if (rotationDegrees == 90 || rotationDegrees == 270) sourceHeight else sourceWidth
        override val height: Int =
            if (rotationDegrees == 90 || rotationDegrees == 270) sourceWidth else sourceHeight

        override fun rgbAt(x: Int, y: Int): DepthFramePreprocessor.RgbFloat {
            val rgb = rgbIntAt(x, y)
            return DepthFramePreprocessor.RgbFloat(
                red = ((rgb shr RED_SHIFT) and BYTE_MASK) / BYTE_MAX.toFloat(),
                green = ((rgb shr GREEN_SHIFT) and BYTE_MASK) / BYTE_MAX.toFloat(),
                blue = (rgb and BYTE_MASK) / BYTE_MAX.toFloat(),
            )
        }

        fun rgbIntAt(x: Int, y: Int): Int {
            val source = sourceCoordinates(
                targetX = x,
                targetY = y,
                sourceWidth = sourceWidth,
                sourceHeight = sourceHeight,
                rotationDegrees = rotationDegrees,
            )
            return yuvToRgbInt(
                y = yPlane.valueAt(source.x, source.y),
                u = uPlane.valueAt(source.x / 2, source.y / 2),
                v = vPlane.valueAt(source.x / 2, source.y / 2),
            )
        }
    }

    private fun YuvFrame.putBilinearRgb(
        sourceX: Float,
        sourceY: Float,
        output: ByteBuffer,
    ) {
        val left = floor(sourceX).toInt().coerceIn(0, width - 1)
        val top = floor(sourceY).toInt().coerceIn(0, height - 1)
        val right = (left + 1).coerceAtMost(width - 1)
        val bottom = (top + 1).coerceAtMost(height - 1)
        val xWeight = (sourceX - left).coerceIn(0f, 1f)
        val yWeight = (sourceY - top).coerceIn(0f, 1f)

        val topLeft = rgbIntAt(left, top)
        val topRight = rgbIntAt(right, top)
        val bottomLeft = rgbIntAt(left, bottom)
        val bottomRight = rgbIntAt(right, bottom)

        output.put(bilinearByte(topLeft, topRight, bottomLeft, bottomRight, RED_SHIFT, xWeight, yWeight))
        output.put(bilinearByte(topLeft, topRight, bottomLeft, bottomRight, GREEN_SHIFT, xWeight, yWeight))
        output.put(bilinearByte(topLeft, topRight, bottomLeft, bottomRight, BLUE_SHIFT, xWeight, yWeight))
    }

    private fun bilinearByte(
        topLeft: Int,
        topRight: Int,
        bottomLeft: Int,
        bottomRight: Int,
        shift: Int,
        xWeight: Float,
        yWeight: Float,
    ): Byte {
        val top = channel(topLeft, shift) +
            (channel(topRight, shift) - channel(topLeft, shift)) * xWeight
        val bottom = channel(bottomLeft, shift) +
            (channel(bottomRight, shift) - channel(bottomLeft, shift)) * xWeight
        return (top + (bottom - top) * yWeight).roundToByte().toByte()
    }

    private fun channel(rgb: Int, shift: Int): Int =
        (rgb shr shift) and BYTE_MASK

    private fun yuvToRgbInt(y: Int, u: Int, v: Int): Int {
        val uOffset = u - 128
        val vOffset = v - 128
        val red = (y + 1.402f * vOffset).roundToByte()
        val green = (y - 0.344136f * uOffset - 0.714136f * vOffset).roundToByte()
        val blue = (y + 1.772f * uOffset).roundToByte()
        return (red shl RED_SHIFT) or (green shl GREEN_SHIFT) or blue
    }

    private fun Float.roundToByte(): Int =
        roundToInt().coerceIn(0, BYTE_MASK)

    private fun ImageProxy.PlaneProxy.toYuvPlane(): YuvPlane =
        YuvPlane(
            buffer = buffer.duplicate(),
            rowStride = rowStride,
            pixelStride = pixelStride,
        )

    private fun sourceCoordinates(
        targetX: Int,
        targetY: Int,
        sourceWidth: Int,
        sourceHeight: Int,
        rotationDegrees: Int,
    ): PixelCoordinate =
        when (rotationDegrees) {
            0 -> PixelCoordinate(x = targetX, y = targetY)
            90 -> PixelCoordinate(x = targetY, y = sourceHeight - 1 - targetX)
            180 -> PixelCoordinate(x = sourceWidth - 1 - targetX, y = sourceHeight - 1 - targetY)
            270 -> PixelCoordinate(x = sourceWidth - 1 - targetY, y = targetX)
            else -> error("Unsupported YUV rotation $rotationDegrees")
        }

    data class YuvPlane(
        private val buffer: ByteBuffer,
        private val rowStride: Int,
        private val pixelStride: Int,
    ) {
        private val baseOffset = buffer.position()

        fun valueAt(x: Int, y: Int): Int =
            buffer.get(baseOffset + y * rowStride + x * pixelStride).toInt() and BYTE_MASK
    }

    private data class PixelCoordinate(
        val x: Int,
        val y: Int,
    )

    private const val RGB_CHANNELS = 3
    private const val RED_SHIFT = 16
    private const val GREEN_SHIFT = 8
    private const val BLUE_SHIFT = 0
    private const val BYTE_MASK = 0xFF
    private const val BYTE_MAX = 255
    private val SUPPORTED_ROTATIONS = setOf(0, 90, 180, 270)
}
