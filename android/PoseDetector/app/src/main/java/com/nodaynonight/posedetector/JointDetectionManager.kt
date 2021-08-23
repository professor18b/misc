package com.nodaynonight.posedetector

import android.media.Image
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import com.osmapps.golf.common.bean.domain.misc.Point
import com.osmapps.golf.common.bean.domain.practice2.JointDetectionResult.DetectedPoint
import com.osmapps.golf.common.bean.domain.practice2.JointDetectionResult.JointName
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * @author wulei
 */
class JointDetectionManager private constructor() {

    companion object {

        @JvmStatic
        val INSTANCE = JointDetectionManager()
        private val executor = Executors.newSingleThreadExecutor()
    }

    private val options =
        PoseDetectorOptions.Builder().setDetectorMode(PoseDetectorOptions.STREAM_MODE).setExecutor(executor).build()

    fun detect(
        buffer: ByteBuffer,
        width: Int,
        height: Int,
        rotationDegree: Int
    ): Array<DetectedPoint?> {
        val inputImage = InputImage.fromByteBuffer(buffer, width, height, rotationDegree, InputImage.IMAGE_FORMAT_YV12)
        return detect(inputImage)
    }

    fun detect(image: Image, rotationDegree: Int): Array<DetectedPoint?> {
        val inputImage = InputImage.fromMediaImage(image, rotationDegree)
        return detect(inputImage)
    }

    private fun detect(inputImage: InputImage): Array<DetectedPoint?> {
        val poseDetector = PoseDetection.getClient(options)
        val task = poseDetector.process(inputImage)
        val pose = Tasks.await(task)
        var leftShoulder: DetectedPoint? = null
        var rightShoulder: DetectedPoint? = null
        var leftHip: DetectedPoint? = null
        var rightHip: DetectedPoint? = null
        val detectedPoints = Array<DetectedPoint?>(JointName.count()) { null }
        pose.allPoseLandmarks.forEach { poseLandmark ->
            JointName.parseFromMLKit(poseLandmark.landmarkType)?.let {
                val point =
                    Point(poseLandmark.position.x.toDouble(), poseLandmark.position.y.toDouble())
                val detectedPoint = DetectedPoint(point, 1.0)
                detectedPoints[it.index()] = detectedPoint
                when (it) {
                    JointName.LEFT_SHOULDER -> leftShoulder = detectedPoint
                    JointName.RIGHT_SHOULDER -> rightShoulder = detectedPoint
                    JointName.LEFT_HIP -> leftHip = detectedPoint
                    JointName.RIGHT_HIP -> rightHip = detectedPoint
                    else -> {
                    }
                }
            }
        }
        if (leftShoulder != null && rightShoulder != null) {
            detectedPoints[JointName.NECK.index()] = getMiddlePoint(leftShoulder!!, rightShoulder!!)
        }
        if (leftHip != null && rightHip != null) {
            detectedPoints[JointName.ROOT.index()] = getMiddlePoint(leftHip!!, rightHip!!)
        }
        return detectedPoints
    }

    private fun getMiddlePoint(left: DetectedPoint, right: DetectedPoint): DetectedPoint {
        return DetectedPoint(
            Point((left.point.x + right.point.x) / 2, (left.point.y + right.point.y) / 2), 1.0
        )
    }
}
