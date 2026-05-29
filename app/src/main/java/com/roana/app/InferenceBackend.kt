package com.roana.app

import android.content.Context
import android.util.Log
import com.qualcomm.qti.QnnDelegate
import org.tensorflow.lite.Delegate
import org.tensorflow.lite.Interpreter
import java.io.File

class InferenceBackend private constructor(
    val name: String,
    val delegate: Delegate?,
    val failureReason: String?,
) : AutoCloseable {
    val usesDelegate: Boolean = delegate != null

    fun applyTo(options: Interpreter.Options): Interpreter.Options {
        if (delegate != null) {
            options.addDelegate(delegate)
        } else {
            options.setUseXNNPACK(true)
        }
        return options
    }

    override fun close() {
        delegate?.close()
    }

    companion object {
        fun create(
            context: Context? = null,
            preferQnn: Boolean = true,
            precision: Precision = Precision.QUANTIZED,
            variant: QnnVariant = QnnVariant.DEFAULT,
        ): InferenceBackend {
            if (!preferQnn) {
                Log.i(
                    TAG,
                    "inference_backend selected=cpu_xnnpack precision=${precision.logValue} reason=qnn_disabled",
                )
                return InferenceBackend(CPU_XNNPACK, delegate = null, failureReason = null)
            }

            val qnnVersion = runCatching {
                QnnDelegate.getVersion().joinToString(".")
            }.getOrElse { error ->
                "unavailable:${error.javaClass.simpleName}"
            }
            Log.i(TAG, "qnn_probe precision=${precision.logValue} version=$qnnVersion")

            val quantizedAvailable = runCatching {
                QnnDelegate.checkCapability(QnnDelegate.Capability.HTP_RUNTIME_QUANTIZED)
            }.getOrElse { error ->
                Log.w(TAG, "qnn_capability_failed capability=HTP_RUNTIME_QUANTIZED", error)
                false
            }
            val fp16Available = runCatching {
                QnnDelegate.checkCapability(QnnDelegate.Capability.HTP_RUNTIME_FP16)
            }.getOrElse { error ->
                Log.w(TAG, "qnn_capability_failed capability=HTP_RUNTIME_FP16", error)
                false
            }
            Log.i(
                TAG,
                "qnn_capabilities htp_quantized=$quantizedAvailable htp_fp16=$fp16Available",
            )

            val requiredCapabilityAvailable = when (precision) {
                Precision.QUANTIZED -> quantizedAvailable
                Precision.FP16 -> fp16Available
            }
            if (!requiredCapabilityAvailable) {
                val reason = "qnn_${precision.logValue}_unavailable"
                Log.i(
                    TAG,
                    "inference_backend selected=cpu_xnnpack precision=${precision.logValue} reason=$reason",
                )
                return InferenceBackend(CPU_XNNPACK, delegate = null, failureReason = reason)
            }

            return runCatching {
                val options = createQnnOptions(context, precision, variant)
                Log.i(
                    TAG,
                    "qnn_options variant=${variant.id} precision=${precision.logValue} " +
                        "library_path=${options.getLibraryPath().orEmpty().sanitizeLogValue()} " +
                        "skel_dir=${options.getSkelLibraryDir().orEmpty().sanitizeLogValue()} " +
                        "pd=${options.getHtpPdSession()} perf=${options.getHtpPerformanceMode()} " +
                        "perf_ctrl=${options.getHtpPerfCtrlStrategy()} " +
                        "opt=${options.getHtpOptimizationStrategy()} log=${options.getLogLevel()}",
                )
                val delegate = QnnDelegate(options)
                Log.i(
                    TAG,
                    "inference_backend selected=qnn_htp precision=${precision.logValue} " +
                        "variant=${variant.id}",
                )
                InferenceBackend(QNN_HTP, delegate = delegate, failureReason = null)
            }.getOrElse { error ->
                val reason = "${error.javaClass.simpleName}:${error.message.orEmpty()}"
                Log.w(
                    TAG,
                    "inference_backend selected=cpu_xnnpack precision=${precision.logValue} " +
                        "variant=${variant.id} reason=qnn_create_failed:$reason",
                )
                InferenceBackend(CPU_XNNPACK, delegate = null, failureReason = reason)
            }
        }

        fun cpu(reason: String? = null): InferenceBackend =
            InferenceBackend(CPU_XNNPACK, delegate = null, failureReason = reason)

        private fun createQnnOptions(
            context: Context?,
            precision: Precision,
            variant: QnnVariant,
        ): QnnDelegate.Options {
            val options = QnnDelegate.Options().apply {
                setBackendType(QnnDelegate.Options.BackendType.HTP_BACKEND)
                setHtpPerformanceMode(variant.performanceMode)
                setHtpPrecision(precision.toQnnPrecision())
                setHtpPerfCtrlStrategy(variant.perfCtrlStrategy)
                setHtpOptimizationStrategy(variant.optimizationStrategy)
                setHtpPdSession(variant.pdSession)
                setLogLevel(QnnDelegate.Options.LogLevel.LOG_LEVEL_DEBUG)
            }

            val nativeLibraryDir = context?.applicationInfo?.nativeLibraryDir
            if (variant.useExplicitNativePaths && !nativeLibraryDir.isNullOrBlank()) {
                options.setLibraryPath(File(nativeLibraryDir, QNN_HTP_LIBRARY).absolutePath)
                options.setSkelLibraryDir(nativeLibraryDir)
            }

            return options
        }

        private const val TAG = "RoanaV0a"
        private const val QNN_HTP = "qnn_htp"
        private const val CPU_XNNPACK = "cpu_xnnpack"
        private const val QNN_HTP_LIBRARY = "libQnnHtp.so"
    }

    enum class Precision(val logValue: String) {
        QUANTIZED("quantized"),
        FP16("fp16"),
    }
}

enum class QnnVariant(
    val id: String,
    val pdSession: QnnDelegate.Options.HtpPdSession,
    val useExplicitNativePaths: Boolean,
    val performanceMode: QnnDelegate.Options.HtpPerformanceMode =
        QnnDelegate.Options.HtpPerformanceMode.HTP_PERFORMANCE_BURST,
    val perfCtrlStrategy: QnnDelegate.Options.HtpPerfCtrlStrategy =
        QnnDelegate.Options.HtpPerfCtrlStrategy.HTP_PERF_CTRL_AUTO,
    val optimizationStrategy: QnnDelegate.Options.HtpOptimizationStrategy =
        QnnDelegate.Options.HtpOptimizationStrategy.HTP_OPTIMIZE_FOR_INFERENCE,
) {
    DEFAULT(
        id = "default",
        pdSession = QnnDelegate.Options.HtpPdSession.HTP_PD_SESSION_UNSIGNED,
        useExplicitNativePaths = false,
    ),
    EXPLICIT_PATHS(
        id = "explicit_paths",
        pdSession = QnnDelegate.Options.HtpPdSession.HTP_PD_SESSION_UNSIGNED,
        useExplicitNativePaths = true,
    ),
    SIGNED_PD(
        id = "signed_pd",
        pdSession = QnnDelegate.Options.HtpPdSession.HTP_PD_SESSION_SIGNED,
        useExplicitNativePaths = false,
    ),
    SIGNED_PD_EXPLICIT_PATHS(
        id = "signed_pd_explicit_paths",
        pdSession = QnnDelegate.Options.HtpPdSession.HTP_PD_SESSION_SIGNED,
        useExplicitNativePaths = true,
    ),
    DEFAULT_PERF_EXPLICIT_PATHS(
        id = "default_perf_explicit_paths",
        pdSession = QnnDelegate.Options.HtpPdSession.HTP_PD_SESSION_UNSIGNED,
        useExplicitNativePaths = true,
        performanceMode = QnnDelegate.Options.HtpPerformanceMode.HTP_PERFORMANCE_DEFAULT,
        perfCtrlStrategy = QnnDelegate.Options.HtpPerfCtrlStrategy.HTP_PERF_CTRL_AUTO,
    );

    companion object {
        fun fromId(id: String?): QnnVariant =
            entries.firstOrNull { it.id == id } ?: DEFAULT
    }
}

private fun InferenceBackend.Precision.toQnnPrecision(): QnnDelegate.Options.HtpPrecision =
    when (this) {
        InferenceBackend.Precision.QUANTIZED ->
            QnnDelegate.Options.HtpPrecision.HTP_PRECISION_QUANTIZED
        InferenceBackend.Precision.FP16 ->
            QnnDelegate.Options.HtpPrecision.HTP_PRECISION_FP16
    }

private fun String.sanitizeLogValue(): String =
    replace('\n', '_')
        .replace('\r', '_')
        .replace(' ', '_')
