package com.roana.app

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class InferenceBackendPolicyTest {
    @Test
    fun productionRuntimeDoesNotSelectCpuFallback() {
        val productionSource = File("src/main/java").walkTopDown()
            .filter {
                it.isFile &&
                    it.extension == "kt" &&
                    it.name != "QnnModelSmoke.kt"
            }
            .joinToString(separator = "\n") { it.readText() }

        val forbiddenTokens = listOf(
            "cpu_xnnpack",
            "setUseXNNPACK",
            "InferenceBackend.cpu",
            "selected=cpu",
            "usesDelegate",
            "failureReason",
        )

        forbiddenTokens.forEach { token ->
            assertFalse("Forbidden production fallback token found: $token", productionSource.contains(token))
        }
        assertTrue(productionSource.contains("inference_backend selected=qnn_htp"))
    }

    @Test
    fun qnnSmokeCpuInterpreterIsMetadataOnly() {
        val smokeSource = File("src/main/java/com/roana/app/QnnModelSmoke.kt").readText()

        assertTrue(smokeSource.contains("Metadata-only interpreter"))
        assertTrue(smokeSource.contains("setUseXNNPACK"))
        assertFalse(smokeSource.contains("selected=cpu"))
        assertFalse(smokeSource.contains("InferenceBackend.cpu"))
    }

    private fun File.walkTopDown(): Sequence<File> =
        walk().asSequence()
}
