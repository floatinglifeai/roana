package com.roana.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import androidx.camera.core.ImageProxy
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

object CameraFrameConverter {
    fun toBitmap(
        image: ImageProxy,
        targetWidth: Int,
        targetHeight: Int,
    ): Bitmap {
        val rotated = toRotatedBitmap(image)
        val scaled = Bitmap.createScaledBitmap(rotated, targetWidth, targetHeight, true)
        if (scaled !== rotated) {
            rotated.recycle()
        }
        return scaled
    }

    fun toRgbFrame(image: ImageProxy): DepthFramePreprocessor.RgbFrame {
        val bitmap = toRotatedBitmap(image)
        return try {
            bitmap.toRgbFrame()
        } finally {
            bitmap.recycle()
        }
    }

    private fun toRotatedBitmap(image: ImageProxy): Bitmap {
        require(image.format == ImageFormat.YUV_420_888) {
            "Expected YUV_420_888 image, got ${image.format}"
        }

        val nv21 = image.yuv420888ToNv21()
        val jpegOutput = ByteArrayOutputStream()
        YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
            .compressToJpeg(Rect(0, 0, image.width, image.height), JPEG_QUALITY, jpegOutput)

        val source = BitmapFactory.decodeByteArray(
            jpegOutput.toByteArray(),
            0,
            jpegOutput.size(),
        )
        val matrix = Matrix().apply {
            postRotate(image.imageInfo.rotationDegrees.toFloat())
        }
        val rotated = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
        if (rotated !== source) {
            source.recycle()
        }
        return rotated
    }

    private fun Bitmap.toRgbFrame(): DepthFramePreprocessor.RgbFrame {
        val pixels = IntArray(width * height)
        getPixels(pixels, 0, width, 0, 0, width, height)
        return DepthFramePreprocessor.RgbFrame(
            width = width,
            height = height,
            pixels = pixels,
        )
    }

    private fun ImageProxy.yuv420888ToNv21(): ByteArray {
        val yPlane = planes[0]
        val uPlane = planes[1]
        val vPlane = planes[2]
        val output = ByteArray(width * height * 3 / 2)
        var outputOffset = 0

        copyPlane(
            buffer = yPlane.buffer,
            width = width,
            height = height,
            rowStride = yPlane.rowStride,
            pixelStride = yPlane.pixelStride,
            output = output,
            outputOffset = outputOffset,
            outputPixelStride = 1,
        )
        outputOffset += width * height

        val chromaWidth = width / 2
        val chromaHeight = height / 2
        for (row in 0 until chromaHeight) {
            for (col in 0 until chromaWidth) {
                output[outputOffset++] =
                    vPlane.buffer.get(row * vPlane.rowStride + col * vPlane.pixelStride)
                output[outputOffset++] =
                    uPlane.buffer.get(row * uPlane.rowStride + col * uPlane.pixelStride)
            }
        }

        return output
    }

    private fun copyPlane(
        buffer: ByteBuffer,
        width: Int,
        height: Int,
        rowStride: Int,
        pixelStride: Int,
        output: ByteArray,
        outputOffset: Int,
        outputPixelStride: Int,
    ) {
        var offset = outputOffset
        for (row in 0 until height) {
            for (col in 0 until width) {
                output[offset] = buffer.get(row * rowStride + col * pixelStride)
                offset += outputPixelStride
            }
        }
    }

    private const val JPEG_QUALITY = 80
}
