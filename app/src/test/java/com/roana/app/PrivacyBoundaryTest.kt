package com.roana.app

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

class PrivacyBoundaryTest {
    @Test
    fun manifestOnlyRequestsCameraPermissionForV0() {
        val permissions = manifestPermissions()

        assertEquals(setOf("android.permission.CAMERA"), permissions)
        assertFalse(permissions.contains("android.permission.INTERNET"))
        assertFalse(permissions.contains("android.permission.ACCESS_NETWORK_STATE"))
        assertFalse(permissions.contains("android.permission.WRITE_EXTERNAL_STORAGE"))
        assertFalse(permissions.contains("android.permission.READ_EXTERNAL_STORAGE"))
        assertFalse(permissions.contains("android.permission.READ_MEDIA_IMAGES"))
        assertFalse(permissions.contains("android.permission.READ_MEDIA_VIDEO"))
    }

    @Test
    fun appSourceDoesNotUseNetworkOrFrameStorageApis() {
        val sourceText = File("src/main/java").walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .joinToString(separator = "\n") { it.readText() }

        val forbiddenTokens = listOf(
            "HttpURLConnection",
            "OkHttp",
            "Retrofit",
            "Socket(",
            "URL(",
            "MediaStore",
            "FileOutputStream",
            "openFileOutput",
            "getExternalFilesDir",
            "insertImage",
        )

        forbiddenTokens.forEach { token ->
            assertFalse("Forbidden V0 privacy boundary token found: $token", sourceText.contains(token))
        }
    }

    @Test
    fun appSourceDoesNotAddOutOfScopeV0GuidanceOrIdentityFeatures() {
        val sourceText = File("src/main/java").walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .joinToString(separator = "\n") { it.readText().lowercase() }

        val forbiddenTokens = listOf(
            "crosswalk",
            "cross street",
            "cross the street",
            "traffic light",
            "outdoor navigation",
            "face recognition",
            "identity",
            "vlm",
            "cloud",
        )

        forbiddenTokens.forEach { token ->
            assertFalse("Forbidden V0 product-boundary token found: $token", sourceText.contains(token))
        }
    }

    @Test
    fun manifestDisablesBackupForCapturedState() {
        val application = manifestDocument()
            .documentElement
            .getElementsByTagName("application")
            .item(0) as Element

        assertEquals("false", application.getAttribute("android:allowBackup"))
    }

    private fun manifestPermissions(): Set<String> {
        val nodes = manifestDocument().documentElement.getElementsByTagName("uses-permission")
        return (0 until nodes.length)
            .map { nodes.item(it) as Element }
            .map { it.getAttribute("android:name") }
            .toSet()
    }

    private fun manifestDocument() =
        DocumentBuilderFactory.newInstance()
            .newDocumentBuilder()
            .parse(File("src/main/AndroidManifest.xml"))

    private fun File.walkTopDown(): Sequence<File> =
        walk().asSequence()
}
