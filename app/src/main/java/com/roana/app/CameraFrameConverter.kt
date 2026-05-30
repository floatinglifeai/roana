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

    fun fillRgbInputNearest(
        image: ImageProxy,
        targetWidth: Int,
        targetHeight: Int,
        output: ByteBuffer,
        scratch: ByteArray? = null,
        lumaOnly: Boolean = false,
    ): ByteBuffer {
        require(image.format == ImageFormat.YUV_420_888) {
            "Expected YUV_420_888 image, got ${image.format}"
        }
        return fillRgbInputNearest(
            sampler = image.toYuvFrame(),
            targetWidth = targetWidth,
            targetHeight = targetHeight,
            output = output,
            scratch = scratch,
            lumaOnly = lumaOnly,
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

    fun fillYuv420RgbInputNearest(
        width: Int,
        height: Int,
        rotationDegrees: Int,
        yPlane: YuvPlane,
        uPlane: YuvPlane,
        vPlane: YuvPlane,
        targetWidth: Int,
        targetHeight: Int,
        output: ByteBuffer,
        scratch: ByteArray? = null,
        lumaOnly: Boolean = false,
    ): ByteBuffer =
        fillRgbInputNearest(
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
            scratch = scratch,
            lumaOnly = lumaOnly,
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

    private fun fillRgbInputNearest(
        sampler: YuvFrame,
        targetWidth: Int,
        targetHeight: Int,
        output: ByteBuffer,
        scratch: ByteArray?,
        lumaOnly: Boolean,
    ): ByteBuffer =
        sampler.fillRgbInputNearest(
            targetWidth = targetWidth,
            targetHeight = targetHeight,
            output = output,
            scratch = scratch,
            lumaOnly = lumaOnly,
        )

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
            val sourceX: Int
            val sourceY: Int
            when (rotationDegrees) {
                0 -> {
                    sourceX = x
                    sourceY = y
                }
                90 -> {
                    sourceX = y
                    sourceY = sourceHeight - 1 - x
                }
                180 -> {
                    sourceX = sourceWidth - 1 - x
                    sourceY = sourceHeight - 1 - y
                }
                270 -> {
                    sourceX = sourceWidth - 1 - y
                    sourceY = x
                }
                else -> error("Unsupported YUV rotation $rotationDegrees")
            }
            return yuvToRgbInt(
                y = yPlane.valueAt(sourceX, sourceY),
                u = uPlane.valueAt(sourceX / 2, sourceY / 2),
                v = vPlane.valueAt(sourceX / 2, sourceY / 2),
            )
        }

        fun fillDepthInputNearest(
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
                    val luma = lumaFloatAt(sourceXs[targetX], sourceY)
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

        fun fillRgbInputNearest(
            targetWidth: Int,
            targetHeight: Int,
            output: ByteBuffer,
            scratch: ByteArray? = null,
            lumaOnly: Boolean = false,
        ): ByteBuffer {
            require(targetWidth > 0 && targetHeight > 0) { "Target dimensions must be positive" }
            val expectedBytes = targetWidth * targetHeight * RGB_CHANNELS
            require(output.capacity() == expectedBytes) {
                "Expected $expectedBytes-byte RGB input buffer, got ${output.capacity()}"
            }
            if (scratch != null) {
                require(scratch.size == expectedBytes) {
                    "Expected $expectedBytes-byte RGB input scratch, got ${scratch.size}"
                }
            }

            output.clear()
            var outputIndex = 0
            for (targetY in 0 until targetHeight) {
                val sourceY = nearestSource(targetY, height, targetHeight, offset = 0)
                for (targetX in 0 until targetWidth) {
                    val sourceX = nearestSource(targetX, width, targetWidth, offset = 0)
                    if (scratch != null) {
                        writeRgbBytesAt(sourceX, sourceY, scratch, outputIndex, lumaOnly)
                        outputIndex += RGB_CHANNELS
                    } else {
                        putRgbByteAt(sourceX, sourceY, output, lumaOnly)
                    }
                }
            }
            if (scratch != null) {
                output.put(scratch)
            }
            output.rewind()
            return output
        }

        private fun nearestSource(
            target: Int,
            sourceSize: Int,
            targetSize: Int,
            offset: Int,
        ): Int =
            (offset + ((target * sourceSize) + (sourceSize / 2)) / targetSize)
                .coerceIn(offset, offset + sourceSize - 1)

        private fun lumaFloatAt(x: Int, y: Int): Float {
            val sourceX: Int
            val sourceY: Int
            when (rotationDegrees) {
                0 -> {
                    sourceX = x
                    sourceY = y
                }
                90 -> {
                    sourceX = y
                    sourceY = sourceHeight - 1 - x
                }
                180 -> {
                    sourceX = sourceWidth - 1 - x
                    sourceY = sourceHeight - 1 - y
                }
                270 -> {
                    sourceX = sourceWidth - 1 - y
                    sourceY = x
                }
                else -> error("Unsupported YUV rotation $rotationDegrees")
            }
            return yPlane.valueAt(sourceX, sourceY) / BYTE_MAX.toFloat()
        }

        private fun putRgbByteAt(x: Int, y: Int, output: ByteBuffer, lumaOnly: Boolean) {
            if (lumaOnly) {
                val luma = lumaByteAt(x, y).toByte()
                output.put(luma)
                output.put(luma)
                output.put(luma)
                return
            }
            val rgb = rgbIntAt(x, y)
            output.put(channel(rgb, RED_SHIFT).toByte())
            output.put(channel(rgb, GREEN_SHIFT).toByte())
            output.put(channel(rgb, BLUE_SHIFT).toByte())
        }

        private fun writeRgbBytesAt(
            x: Int,
            y: Int,
            output: ByteArray,
            offset: Int,
            lumaOnly: Boolean,
        ) {
            if (lumaOnly) {
                val luma = lumaByteAt(x, y).toByte()
                output[offset] = luma
                output[offset + 1] = luma
                output[offset + 2] = luma
                return
            }
            val rgb = rgbIntAt(x, y)
            output[offset] = channel(rgb, RED_SHIFT).toByte()
            output[offset + 1] = channel(rgb, GREEN_SHIFT).toByte()
            output[offset + 2] = channel(rgb, BLUE_SHIFT).toByte()
        }

        private fun lumaByteAt(x: Int, y: Int): Int {
            val sourceX: Int
            val sourceY: Int
            when (rotationDegrees) {
                0 -> {
                    sourceX = x
                    sourceY = y
                }
                90 -> {
                    sourceX = y
                    sourceY = sourceHeight - 1 - x
                }
                180 -> {
                    sourceX = sourceWidth - 1 - x
                    sourceY = sourceHeight - 1 - y
                }
                270 -> {
                    sourceX = sourceWidth - 1 - y
                    sourceY = x
                }
                else -> error("Unsupported YUV rotation $rotationDegrees")
            }
            return yPlane.valueAt(sourceX, sourceY)
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
        val red = (y + (1_436 * vOffset / 1_024)).coerceIn(0, BYTE_MASK)
        val green = (y - ((352 * uOffset + 731 * vOffset) / 1_024)).coerceIn(0, BYTE_MASK)
        val blue = (y + (1_815 * uOffset / 1_024)).coerceIn(0, BYTE_MASK)
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

    data class YuvPlane(
        private val buffer: ByteBuffer,
        private val rowStride: Int,
        private val pixelStride: Int,
    ) {
        private val baseOffset = buffer.position()

        fun valueAt(x: Int, y: Int): Int =
            buffer.get(baseOffset + y * rowStride + x * pixelStride).toInt() and BYTE_MASK
    }

    private const val RGB_CHANNELS = 3
    private const val FLOAT_SIZE = 4
    private const val RED_SHIFT = 16
    private const val GREEN_SHIFT = 8
    private const val BLUE_SHIFT = 0
    private const val BYTE_MASK = 0xFF
    private const val BYTE_MAX = 255
    private val SUPPORTED_ROTATIONS = setOf(0, 90, 180, 270)
}
