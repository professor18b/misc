package com.squarevalley.i8birdies.improve.aicoach.detection

import android.content.Context
import android.media.Image
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import androidx.annotation.RequiresApi
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
import com.osmapps.golf.common.bean.domain.misc.Point
import com.osmapps.golf.common.bean.domain.misc.Size
import com.osmapps.golf.common.bean.domain.practice2.JointDetectionResult
import com.osmapps.golf.common.bean.domain.practice2.JointDetectionResult.DetectedPoint
import com.osmapps.golf.common.bean.domain.practice2.JointDetectionResult.JointName
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * @author wulei
 */
@RequiresApi(Build.VERSION_CODES.M)
class JointDetectionManager private constructor() {

    companion object {

        @JvmStatic
        val INSTANCE = JointDetectionManager()
        private val executor = Executors.newSingleThreadExecutor()
    }

    private val options =
        AccuratePoseDetectorOptions.Builder().setDetectorMode(AccuratePoseDetectorOptions.STREAM_MODE).setExecutor(
            executor
        ).build()

    fun detect(
        buffer: ByteBuffer,
        width: Int,
        height: Int,
        rotationDegree: Int
    ): List<DetectedPoint?> {
        val inputImage =
            InputImage.fromByteBuffer(
                buffer, width, height, rotationDegree,
                InputImage.IMAGE_FORMAT_NV21
            )
        return detect(inputImage)
    }

    fun detect(image: Image, rotationDegree: Int): List<DetectedPoint?> {
        val inputImage = InputImage.fromMediaImage(image, rotationDegree)
        return detect(inputImage)
    }

    fun detectVideo(
        context: Context, uri: Uri,
        progressHandler: ((index: Int, frameCount: Int) -> Unit)? = null
    ): JointDetectionResult? {
        val path = uri.path
        checkNotNull(path) { "path should not be null" }
        println("detect path: $path")
        val extractor = SkeletonMediaUtil.createMediaExtractor(context, uri)
        val videoInputTrack = SkeletonMediaUtil.getAndSelectVideoTrackIndex(extractor)
        if (videoInputTrack < 0) {
            return null
        }
        val decoderFormat = extractor.getTrackFormat(videoInputTrack)
        val mime = decoderFormat.getString(MediaFormat.KEY_MIME)!!

        val decoder = try {
            MediaCodec.createDecoderByType(mime)
        } catch (e: Exception) {
            return null
        }

        val width = decoderFormat.getInteger(MediaFormat.KEY_WIDTH)
        val height = decoderFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val frameCount = if (decoderFormat.containsKey("frame-count")) {
            decoderFormat.getInteger("frame-count")
        } else {
            -1
        }
        val frameRate = decoderFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
        val duration = decoderFormat.getLong(MediaFormat.KEY_DURATION)
        val rotation = if (decoderFormat.containsKey(MediaFormat.KEY_ROTATION)) {
            decoderFormat.getInteger(MediaFormat.KEY_ROTATION)
        } else {
            0
        }
        val bitRate = if (decoderFormat.containsKey(MediaFormat.KEY_BIT_RATE)) {
            decoderFormat.getInteger(MediaFormat.KEY_BIT_RATE)
        } else {
            0
        }
        var frameIndex = 0

        println(
            "mime: $mime, frameCount: $frameCount, width: $width, height: $height, frameRate: $frameRate, " +
                    "duration: $duration, rotation: $rotation, bitRate: $bitRate"
        )
        val progressTotal = if (frameCount < 0) {
            (frameRate * duration / 1000000 + 0.5).toInt()
        } else {
            frameCount
        }

        decoder.configure(decoderFormat, null, null, 0)
        decoder.start()

        val decoderBufferInfo = MediaCodec.BufferInfo()
        val detectedPoints = arrayListOf<List<DetectedPoint?>>()
        loop@ while (true) {
            val decoderInputBufferIndex = decoder.dequeueInputBuffer(1000)
            if (decoderInputBufferIndex >= 0) {
                decoder.getInputBuffer(decoderInputBufferIndex)?.let { byteBuffer ->
                    val chunkSize = extractor.readSampleData(byteBuffer, 0)
                    if (chunkSize < 0) {
                        // end of stream
                        decoder.queueInputBuffer(
                            decoderInputBufferIndex,
                            0,
                            0,
                            0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM
                        )
                    } else {
                        val sampleTime = extractor.sampleTime
                        val flags =
                            if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                                MediaCodec.BUFFER_FLAG_KEY_FRAME
                            } else {
                                0
                            }
                        decoder.queueInputBuffer(
                            decoderInputBufferIndex,
                            0,
                            chunkSize,
                            sampleTime,
                            flags
                        )
                        extractor.advance()
                    }
                }
            }

            when (val decoderOutputBufferIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, 1000)) {
                MediaCodec.INFO_TRY_AGAIN_LATER,
                MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED,
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    // no output available yet
                }
                else -> {
                    check(decoderOutputBufferIndex >= 0)
                    val doRender = (decoderBufferInfo.size != 0)
                    if (doRender) {
                        decoder.getOutputImage(decoderOutputBufferIndex)?.let { image ->
                            val joints = detect(image, rotation)
                            progressHandler?.invoke(frameIndex, progressTotal)
                            detectedPoints.add(joints)
                            frameIndex += 1
                        }
                    }
                    decoder.releaseOutputBuffer(decoderOutputBufferIndex, doRender)

                    if ((decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        break@loop
                    }
                }
            }
        }
        decoder.stop()
        val size = if (rotation == 90 || rotation == 270) {
            Size(height, width)
        } else {
            Size(width, height)
        }

        println("frameIndex: $frameIndex, frameCount: $frameCount")
        return JointDetectionResult(size, frameRate.toFloat(), frameCount, rotation, detectedPoints)
    }

    private fun detect(inputImage: InputImage): List<DetectedPoint?> {
        val poseDetector = PoseDetection.getClient(options)
        val task = poseDetector.process(inputImage)
        val pose = Tasks.await(task)
        var leftShoulder: DetectedPoint? = null
        var rightShoulder: DetectedPoint? = null
        var leftHip: DetectedPoint? = null
        var rightHip: DetectedPoint? = null
        val detectedPoints = arrayListOf<DetectedPoint?>()
        repeat(JointName.count()) {
            detectedPoints.add(null)
        }
        pose.allPoseLandmarks.forEach { poseLandmark ->
            JointName.parseFromMLKit(poseLandmark.landmarkType)?.let {
                val point =
                    Point.fromRotatedImage(
                        poseLandmark.position.x.toDouble(),
                        poseLandmark.position.y.toDouble(),
                        inputImage.width, inputImage.height, inputImage.rotationDegrees
                    )
                if (point != null) {
                    val detectedPoint = DetectedPoint(point, poseLandmark.inFrameLikelihood.toDouble())
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
