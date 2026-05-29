package com.roana.app

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class DepthFramePreprocessorTest {
    @Test
    fun singlePixelFrameFillsRgbFloatInput() {
        val preprocessor = DepthFramePreprocessor(targetWidth = 2, targetHeight = 1)
        val frame = DepthFramePreprocessor.RgbFrame(
            width = 1,
            height = 1,
            pixels = intArrayOf(rgb(red = 128, green = 64, blue = 32)),
        )

        val values = preprocessor.toInputBuffer(frame).readFloats()

        assertArrayEquals(
            floatArrayOf(
                128f / 255f,
                64f / 255f,
                32f / 255f,
                128f / 255f,
                64f / 255f,
                32f / 255f,
            ),
            values,
            FLOAT_TOLERANCE,
        )
    }

    @Test
    fun centerCropDropsLandscapeEdgesBeforeResize() {
        val preprocessor = DepthFramePreprocessor(targetWidth = 2, targetHeight = 2)
        val frame = DepthFramePreprocessor.RgbFrame(
            width = 4,
            height = 2,
            pixels = intArrayOf(
                rgb(255, 0, 0),
                rgb(0, 255, 0),
                rgb(0, 0, 255),
                rgb(255, 255, 255),
                rgb(255, 0, 0),
                rgb(0, 255, 0),
                rgb(0, 0, 255),
                rgb(255, 255, 255),
            ),
        )

        val values = preprocessor.toInputBuffer(frame).readFloats()

        assertArrayEquals(
            floatArrayOf(
                0f,
                1f,
                0f,
                0f,
                0f,
                1f,
                0f,
                1f,
                0f,
                0f,
                0f,
                1f,
            ),
            values,
            FLOAT_TOLERANCE,
        )
    }

    @Test
    fun onePixelResizeSamplesCenterOfCrop() {
        val preprocessor = DepthFramePreprocessor(targetWidth = 1, targetHeight = 1)
        val frame = DepthFramePreprocessor.RgbFrame(
            width = 2,
            height = 2,
            pixels = intArrayOf(
                rgb(255, 0, 0),
                rgb(0, 255, 0),
                rgb(0, 0, 255),
                rgb(255, 255, 255),
            ),
        )

        val values = preprocessor.toInputBuffer(frame).readFloats()

        assertArrayEquals(floatArrayOf(0.5f, 0.5f, 0.5f), values, FLOAT_TOLERANCE)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsMismatchedPixelCount() {
        DepthFramePreprocessor.RgbFrame(width = 2, height = 2, pixels = intArrayOf(rgb(0, 0, 0)))
    }

    @Test
    fun flattensDepthAnythingOutput() {
        val output = arrayOf(
            arrayOf(
                arrayOf(floatArrayOf(0.1f), floatArrayOf(0.2f)),
                arrayOf(floatArrayOf(0.3f), floatArrayOf(0.4f)),
            ),
        )

        val depthMap = DepthAnythingTensor.flattenOutput(output)

        assertEquals(2, depthMap.rows)
        assertEquals(2, depthMap.cols)
        assertArrayEquals(floatArrayOf(0.1f, 0.2f, 0.3f, 0.4f), depthMap.values, FLOAT_TOLERANCE)
    }

    private fun rgb(red: Int, green: Int, blue: Int): Int =
        (red shl 16) or (green shl 8) or blue

    private companion object {
        private const val FLOAT_TOLERANCE = 0.0001f
    }
}

private fun java.nio.ByteBuffer.readFloats(): FloatArray {
    rewind()
    return FloatArray(remaining() / java.lang.Float.BYTES) { float }
}
