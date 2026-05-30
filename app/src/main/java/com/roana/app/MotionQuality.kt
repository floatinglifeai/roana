package com.roana.app

data class MotionQuality(
    val label: Label,
    val reason: String,
) {
    val trustsGuidance: Boolean
        get() = label == Label.STABLE

    enum class Label(
        val logValue: String,
    ) {
        STABLE("stable"),
        POINTING_DOWN("pointing_down"),
        UNSTABLE("unstable"),
    }
}

data class MotionQualitySample(
    val pitchDegrees: Double,
    val angularVelocityDegreesPerSecond: Double,
)

object MotionQualityClassifier {
    const val POINTING_DOWN_PITCH_DEGREES = -55.0
    const val UNSTABLE_ANGULAR_VELOCITY_DEGREES_PER_SECOND = 120.0

    fun classify(sample: MotionQualitySample?): MotionQuality {
        if (sample == null) {
            return MotionQuality(MotionQuality.Label.STABLE, "motion_unavailable")
        }

        if (sample.pitchDegrees <= POINTING_DOWN_PITCH_DEGREES) {
            return MotionQuality(MotionQuality.Label.POINTING_DOWN, "pitch_down")
        }

        if (kotlin.math.abs(sample.angularVelocityDegreesPerSecond) >=
            UNSTABLE_ANGULAR_VELOCITY_DEGREES_PER_SECOND
        ) {
            return MotionQuality(MotionQuality.Label.UNSTABLE, "high_angular_velocity")
        }

        return MotionQuality(MotionQuality.Label.STABLE, "motion_stable")
    }
}
