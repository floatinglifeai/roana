package com.roana.app

import android.util.Log
import com.qualcomm.qti.QnnDelegate
import org.tensorflow.lite.Delegate
import org.tensorflow.lite.Interpreter

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
            preferQnn: Boolean = true,
            precision: Precision = Precision.QUANTIZED,
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
                val options = QnnDelegate.Options().apply {
                    setBackendType(QnnDelegate.Options.BackendType.HTP_BACKEND)
                    setHtpPerformanceMode(
                        QnnDelegate.Options.HtpPerformanceMode.HTP_PERFORMANCE_BURST,
                    )
                    setHtpPrecision(precision.toQnnPrecision())
                    setHtpPerfCtrlStrategy(
                        QnnDelegate.Options.HtpPerfCtrlStrategy.HTP_PERF_CTRL_AUTO,
                    )
                    setHtpOptimizationStrategy(
                        QnnDelegate.Options.HtpOptimizationStrategy.HTP_OPTIMIZE_FOR_INFERENCE,
                    )
                    setHtpPdSession(QnnDelegate.Options.HtpPdSession.HTP_PD_SESSION_UNSIGNED)
                }
                val delegate = QnnDelegate(options)
                Log.i(TAG, "inference_backend selected=qnn_htp precision=${precision.logValue}")
                InferenceBackend(QNN_HTP, delegate = delegate, failureReason = null)
            }.getOrElse { error ->
                val reason = "${error.javaClass.simpleName}:${error.message.orEmpty()}"
                Log.w(
                    TAG,
                    "inference_backend selected=cpu_xnnpack precision=${precision.logValue} " +
                        "reason=qnn_create_failed:$reason",
                )
                InferenceBackend(CPU_XNNPACK, delegate = null, failureReason = reason)
            }
        }

        fun cpu(reason: String? = null): InferenceBackend =
            InferenceBackend(CPU_XNNPACK, delegate = null, failureReason = reason)

        private const val TAG = "RoanaV0a"
        private const val QNN_HTP = "qnn_htp"
        private const val CPU_XNNPACK = "cpu_xnnpack"
    }

    enum class Precision(val logValue: String) {
        QUANTIZED("quantized"),
        FP16("fp16"),
    }
}

private fun InferenceBackend.Precision.toQnnPrecision(): QnnDelegate.Options.HtpPrecision =
    when (this) {
        InferenceBackend.Precision.QUANTIZED ->
            QnnDelegate.Options.HtpPrecision.HTP_PRECISION_QUANTIZED
        InferenceBackend.Precision.FP16 ->
            QnnDelegate.Options.HtpPrecision.HTP_PRECISION_FP16
    }
