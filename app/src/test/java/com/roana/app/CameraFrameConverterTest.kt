package com.roana.app

import java.nio.ByteBuffer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class CameraFrameConverterTest {
    @Test
    fun convertsNeutralYuvToRgbFrameWithoutJpegRoundTrip() {
        val frame = CameraFrameConverter.yuv420ToRgbFrame(
            width = 2,
            height = 2,
            rotationDegrees = 0,
            yPlane = plane(byteArrayOf(0, 64, 128.toByte(), 255.toByte()), rowStride = 2),
            uPlane = plane(byteArrayOf(128.toByte()), rowStride = 1),
            vPlane = plane(byteArrayOf(128.toByte()), rowStride = 1),
        )

        assertEquals(2, frame.width)
        assertEquals(2, frame.height)
        assertArrayEquals(
            intArrayOf(
                rgb(0, 0, 0),
                rgb(64, 64, 64),
                rgb(128, 128, 128),
                rgb(255, 255, 255),
            ),
            frame.pixels,
        )
    }

    @Test
    fun appliesClockwiseRotationWhenBuildingRgbFrame() {
        val frame = CameraFrameConverter.yuv420ToRgbFrame(
            width = 2,
            height = 3,
            rotationDegrees = 90,
            yPlane = plane(
                byteArrayOf(
                    10,
                    20,
                    30,
                    40,
                    50,
                    60,
                ),
                rowStride = 2,
            ),
            uPlane = plane(byteArrayOf(128.toByte(), 128.toByte()), rowStride = 1),
            vPlane = plane(byteArrayOf(128.toByte(), 128.toByte()), rowStride = 1),
        )

        assertEquals(3, frame.width)
        assertEquals(2, frame.height)
        assertArrayEquals(
            intArrayOf(
                rgb(50, 50, 50),
                rgb(30, 30, 30),
                rgb(10, 10, 10),
                rgb(60, 60, 60),
                rgb(40, 40, 40),
                rgb(20, 20, 20),
            ),
            frame.pixels,
        )
    }

    @Test
    fun yuvFrameCanFeedDepthInputWithoutIntermediateRgbFrame() {
        val sampler = CameraFrameConverter.YuvFrame(
            sourceWidth = 1,
            sourceHeight = 1,
            rotationDegrees = 0,
            yPlane = plane(byteArrayOf(128.toByte()), rowStride = 1),
            uPlane = plane(byteArrayOf(128.toByte()), rowStride = 1),
            vPlane = plane(byteArrayOf(128.toByte()), rowStride = 1),
        )
        val preprocessor = DepthFramePreprocessor(targetWidth = 1, targetHeight = 1)

        val values = preprocessor.fillInputBuffer(sampler, preprocessor.newInputBuffer()).readFloats()

        assertArrayEquals(floatArrayOf(128f / 255f, 128f / 255f, 128f / 255f), values, FLOAT_TOLERANCE)
    }

    @Test
    fun fillsRgbInputDirectlyFromYuvWithoutBitmapRoundTrip() {
        val buffer = ByteBuffer.allocateDirect(3)

        val input = CameraFrameConverter.fillYuv420RgbInput(
            width = 2,
            height = 2,
            rotationDegrees = 0,
            yPlane = plane(byteArrayOf(0, 64, 128.toByte(), 255.toByte()), rowStride = 2),
            uPlane = plane(byteArrayOf(128.toByte()), rowStride = 1),
            vPlane = plane(byteArrayOf(128.toByte()), rowStride = 1),
            targetWidth = 1,
            targetHeight = 1,
            output = buffer,
        )

        assertEquals(buffer, input)
        assertArrayEquals(byteArrayOf(112, 112, 112), buffer.readBytes())
    }

    @Test
    fun fillsRgbInputAfterApplyingCameraRotation() {
        val buffer = ByteBuffer.allocateDirect(6)

        CameraFrameConverter.fillYuv420RgbInput(
            width = 2,
            height = 3,
            rotationDegrees = 90,
            yPlane = plane(
                byteArrayOf(
                    10,
                    20,
                    30,
                    40,
                    50,
                    60,
                ),
                rowStride = 2,
            ),
            uPlane = plane(byteArrayOf(128.toByte(), 128.toByte()), rowStride = 1),
            vPlane = plane(byteArrayOf(128.toByte(), 128.toByte()), rowStride = 1),
            targetWidth = 2,
            targetHeight = 1,
            output = buffer,
        )

        assertArrayEquals(byteArrayOf(50, 50, 50, 20, 20, 20), buffer.readBytes())
    }

    private fun plane(
        bytes: ByteArray,
        rowStride: Int,
        pixelStride: Int = 1,
    ): CameraFrameConverter.YuvPlane =
        CameraFrameConverter.YuvPlane(
            buffer = ByteBuffer.wrap(bytes),
            rowStride = rowStride,
            pixelStride = pixelStride,
        )

    private fun rgb(red: Int, green: Int, blue: Int): Int =
        (red shl 16) or (green shl 8) or blue

    private companion object {
        private const val FLOAT_TOLERANCE = 0.0001f
    }
}

private fun ByteBuffer.readFloats(): FloatArray {
    rewind()
    return FloatArray(remaining() / java.lang.Float.BYTES) { float }
}

private fun ByteBuffer.readBytes(): ByteArray {
    rewind()
    return ByteArray(remaining()).also { get(it) }
}
