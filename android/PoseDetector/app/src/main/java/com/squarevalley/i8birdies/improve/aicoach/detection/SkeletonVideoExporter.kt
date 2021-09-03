package com.squarevalley.i8birdies.improve.aicoach.detection

import android.content.Context
import android.media.*
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.osmapps.framework.util.FileUtil
import com.osmapps.golf.common.bean.domain.practice2.JointDetectionResult
import com.osmapps.golf.common.bean.domain.practice2.SwingDetectionResult
import java.io.File
import java.nio.ByteBuffer

abstract class ExportException(message: String) : Exception(message)

class VideoTrackNotFoundException : ExportException("video track not found")
class VideoFormatNotSupportException : ExportException("video format not support")
class ExportPathException : ExportException("export path error")

@RequiresApi(Build.VERSION_CODES.M)
private class MuxerWrapper(
    val muxer: MediaMuxer,
    val jointResult: JointDetectionResult,
    val exportFile: String,
    val segmentIndex: Int,
    val segment: Pair<Int, Int>
) {

    var startTimeUs: Long = -1
    var endTimeUs: Long = -1
    var videoTrackIndex = -1
    var audioTrackIndex = -1

    fun addTrack(videoDecoderFormat: MediaFormat, audioDecoderFormat: MediaFormat?) {
        videoTrackIndex = muxer.addTrack(videoDecoderFormat)
        audioDecoderFormat?.let {
            audioTrackIndex = muxer.addTrack(it)
        }
    }
}

/**
 * @author wulei
 */
@RequiresApi(Build.VERSION_CODES.M)
class SkeletonVideoExporter {

    companion object {

        private var skeletonVideoDir: File? = null
        private const val TAG = "SkeletonVideoExporter"

        private fun getSkeletonVideoDir(): File? {
            if (skeletonVideoDir == null) {
                val newPath = FileUtil.getAppStorageDirectory("skeletonVideo", true)
                skeletonVideoDir = File(newPath)
            }
            skeletonVideoDir?.mkdirs()
            return skeletonVideoDir
        }

        fun export(
            context: Context,
            uri: Uri,
            jointDetectionResult: JointDetectionResult,
            swingDetectionResult: SwingDetectionResult,
            progressHandler: ((swingIndex: Int, jointDetectionResult: JointDetectionResult, exportFile: String) -> Unit)? = null
        ) {
            val path = uri.path
            checkNotNull(path) { "path should not be null" }
            Log.i(TAG, "export path: $path")
            val videoExtractor = SkeletonMediaUtil.createMediaExtractor(context, uri)
            val videoInputTrack = SkeletonMediaUtil.getAndSelectVideoTrackIndex(videoExtractor)
            if (videoInputTrack < 0) {
                throw VideoTrackNotFoundException()
            }
            val videoDecoderFormat = videoExtractor.getTrackFormat(videoInputTrack)
            val width = videoDecoderFormat.getInteger(MediaFormat.KEY_WIDTH)
            val height = videoDecoderFormat.getInteger(MediaFormat.KEY_HEIGHT)
            val frameCount = if (videoDecoderFormat.containsKey("frame-count")) {
                videoDecoderFormat.getInteger("frame-count")
            } else {
                -1
            }
            val frameRate = videoDecoderFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
            val duration = videoDecoderFormat.getLong(MediaFormat.KEY_DURATION)
            val rotation = if (videoDecoderFormat.containsKey(MediaFormat.KEY_ROTATION)) {
                videoDecoderFormat.getInteger(MediaFormat.KEY_ROTATION)
            } else {
                0
            }
            val bitRate = if (videoDecoderFormat.containsKey(MediaFormat.KEY_BIT_RATE)) {
                videoDecoderFormat.getInteger(MediaFormat.KEY_BIT_RATE)
            } else {
                0
            }

            val mime = videoDecoderFormat.getString(MediaFormat.KEY_MIME)!!
            Log.i(
                TAG,
                "mime: $mime, frameCount: $frameCount, width: $width, height: $height, frameRate: $frameRate, " +
                        "duration: $duration, rotation: $rotation, bitRate: $bitRate"
            )

            val videoEncoderFormat = MediaFormat.createVideoFormat(mime, width, height)
            // Set some properties. Failing to specify some of these can cause the MediaCodec
            // configure() call to throw an unhelpful exception.
            videoEncoderFormat.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
            )
            videoEncoderFormat.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            videoEncoderFormat.setLong(MediaFormat.KEY_DURATION, duration)
            videoEncoderFormat.setInteger(MediaFormat.KEY_ROTATION, rotation)
            videoEncoderFormat.setInteger(
                MediaFormat.KEY_BIT_RATE,
                SkeletonMediaUtil.getVideoBitRate(width, height, bitRate)
            )
            videoEncoderFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 0)

            // add audio
            val audioExtractor = SkeletonMediaUtil.createMediaExtractor(context, uri)
            val audioInputTrack = SkeletonMediaUtil.getAndSelectAudioTrackIndex(audioExtractor)
            var audioDecoderFormat: MediaFormat? = null
            if (audioInputTrack >= 0) {
                audioDecoderFormat = audioExtractor.getTrackFormat(audioInputTrack)
            }

            val muxers = createMuxers(jointDetectionResult, swingDetectionResult)

            var currentMuxerIndex = 0
            var currentFrameIndex = -1
            muxVideo(videoExtractor, videoDecoderFormat, videoEncoderFormat, object : OnVideoEncoderListener {
                override fun onOutputEncoded(
                    frameIndex: Int,
                    byteBuffer: ByteBuffer,
                    bufferInfo: MediaCodec.BufferInfo
                ) {
                    muxers.find { frameIndex >= it.segment.first && frameIndex <= it.segment.second }?.apply {
                        if (segmentIndex > currentMuxerIndex) {
                            println("onOutputEncoded end -- frameIndex: $frameIndex, segmentIndex: $currentMuxerIndex, segment: ${muxers[currentMuxerIndex].segment}")
                            progressHandler?.invoke(currentMuxerIndex, jointResult, exportFile)
                            currentMuxerIndex = segmentIndex
                        }

                        muxer.writeSampleData(videoTrackIndex, byteBuffer, bufferInfo)
                        if (startTimeUs == -1L) {
                            println("onOutputEncoded start -- frameIndex: $frameIndex, segmentIndex: $segmentIndex, segment: ${muxers[currentMuxerIndex].segment}")
                            startTimeUs = bufferInfo.presentationTimeUs
                        }
                        endTimeUs = bufferInfo.presentationTimeUs

                        currentFrameIndex = frameIndex
                    }
                }

                override fun onOutputFormatChanged(frameIndex: Int, outputFormat: MediaFormat) {
                    println("onOutputFormatChanged -- frameIndex: $frameIndex, outputFormat: $outputFormat")
                    muxers.forEach { muxerWrapper ->
                        muxerWrapper.addTrack(outputFormat, audioDecoderFormat)
                        muxerWrapper.muxer.setOrientationHint(rotation)
                        muxerWrapper.muxer.start()
                    }
                }
            })
            val currentMuxer = muxers[currentMuxerIndex]
            println("onOutputEncoded end -- frameIndex: $currentFrameIndex, segmentIndex: $currentMuxerIndex, segment: ${currentMuxer.segment}")
            progressHandler?.invoke(currentMuxerIndex, currentMuxer.jointResult, currentMuxer.exportFile)
            videoExtractor.release()
            Log.i(TAG, "************** export video finished")
            if (audioDecoderFormat != null) {
                muxAudio(audioExtractor, audioDecoderFormat) { byteBuffer, bufferInfo ->
                    val timeUs = bufferInfo.presentationTimeUs
                    muxers.find { timeUs >= it.startTimeUs && timeUs <= it.endTimeUs }?.apply {
                        muxer.writeSampleData(audioTrackIndex, byteBuffer, bufferInfo)
                    }
                }
                audioExtractor.release()
                Log.i(TAG, "************** export audio finished")
            }
            muxers.forEach { it.muxer.stop() }
            muxers.forEach { it.muxer.release() }

            Log.i(TAG, "************** export finished")
        }

        private fun createMuxers(
            jointDetectionResult: JointDetectionResult,
            swingDetectionResult: SwingDetectionResult
        ): List<MuxerWrapper> {
            val outputDir = getSkeletonVideoDir() ?: throw ExportPathException()
            val muxers = mutableListOf<MuxerWrapper>()
            var index = 0
            swingDetectionResult.detectedSwings.forEach { detectedSwing ->
                val outputFile = "${outputDir.absolutePath}/exported$index.mp4"//${SystemClock.uptimeMillis()}.mp4"
                val muxer = MediaMuxer(outputFile, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                val jointResult = jointDetectionResult.splitBy(detectedSwing)
                muxers.add(
                    MuxerWrapper(
                        muxer, jointResult, outputFile, index,
                        Pair(detectedSwing.setupSegment.start, detectedSwing.followThroughSegment.end)
                    )
                )
                index++
            }
            return muxers
        }

        private fun muxAudio(
            extractor: MediaExtractor,
            decoderFormat: MediaFormat,
            muxerHandler: (byteBuffer: ByteBuffer, bufferInfo: MediaCodec.BufferInfo) -> Unit
        ) {
            val mime = decoderFormat.getString(MediaFormat.KEY_MIME)!!
            Log.i(TAG, "mime: $mime")
            val maxInputSize = if (decoderFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                decoderFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
            } else {
                1024 * 1024
            }

            val buffer = ByteBuffer.allocate(maxInputSize)
            val bufferInfo = MediaCodec.BufferInfo()
            while (true) {
                val chunkSize = extractor.readSampleData(buffer, 0)
                if (chunkSize > 0) {
                    if (extractor.sampleTime > 0) {
                        bufferInfo.offset = 0
                        bufferInfo.presentationTimeUs = extractor.sampleTime
                        bufferInfo.flags = extractor.sampleFlags
                        bufferInfo.size = chunkSize
                        muxerHandler(buffer, bufferInfo)
                    }
                    extractor.advance()
                } else {
                    break
                }
            }
        }

        private fun getAudioEncoderFormat(decoderFormat: MediaFormat): MediaFormat {
            val mime = decoderFormat.getString(MediaFormat.KEY_MIME)
            checkNotNull(mime) { "mime should not be null" }

            val sampleRateHz = decoderFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channelCount = decoderFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val aacProfile = if (decoderFormat.containsKey(MediaFormat.KEY_AAC_PROFILE)) {
                decoderFormat.getInteger(MediaFormat.KEY_AAC_PROFILE)
            } else {
                0
            }
            val bitRate = if (decoderFormat.containsKey(MediaFormat.KEY_BIT_RATE)) {
                decoderFormat.getInteger(MediaFormat.KEY_BIT_RATE)
            } else {
                0
            }

            Log.i(
                TAG,
                "mime: $mime, sampleRateHz: $sampleRateHz, channelCount: $channelCount, aacProfile: $aacProfile, " +
                        "bitRate: $bitRate"
            )

            val encoderFormat = MediaFormat.createAudioFormat(mime, sampleRateHz, channelCount)

            encoderFormat.setInteger(
                MediaFormat.KEY_AAC_PROFILE, if (aacProfile == 0) {
                    MediaCodecInfo.CodecProfileLevel.AACObjectHE
                } else {
                    aacProfile
                }
            )
            encoderFormat.setInteger(MediaFormat.KEY_BIT_RATE, getAudioBitRate(bitRate))
            return encoderFormat
        }

        private fun getAudioBitRate(bitRate: Int): Int {
            val value = 64 * 1024
            if (bitRate == 0 || bitRate > value) {
                return value
            }
            return bitRate
        }

        @Throws(VideoFormatNotSupportException::class)
        private fun muxVideo(
            extractor: MediaExtractor,
            decoderFormat: MediaFormat,
            encoderFormat: MediaFormat,
            listener: OnVideoEncoderListener
        ) {
            val decoder = try {
                MediaCodec.createDecoderByType(decoderFormat.getString(MediaFormat.KEY_MIME)!!)
            } catch (e: Exception) {
                throw VideoFormatNotSupportException()
            }
            val encoder = try {
                MediaCodec.createEncoderByType(encoderFormat.getString(MediaFormat.KEY_MIME)!!)
            } catch (e: Exception) {
                throw VideoFormatNotSupportException()
            }

            encoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val surface = encoder.createInputSurface()
            encoder.start()
            decoder.configure(decoderFormat, surface, null, 0)
            decoder.start()

            var decodeDone = false
            val bufferInfo = MediaCodec.BufferInfo()
            var encodedCount = 0
            var decoderCount = 0

            loop@ while (true) {
                if (!decodeDone) {
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

                    when (val decoderOutputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, 1000)) {
                        MediaCodec.INFO_TRY_AGAIN_LATER,
                        MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED,
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        }
                        else -> {
                            check(decoderOutputBufferIndex >= 0)
                            val doRender = (bufferInfo.size != 0)
                            if (doRender) {
                                decoderCount++
                            }
                            decoder.releaseOutputBuffer(decoderOutputBufferIndex, doRender)
                            if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                encoder.signalEndOfInputStream()
                                decodeDone = true
                            }
                        }
                    }
                }

                when (val encoderOutputBufferIndex = encoder.dequeueOutputBuffer(bufferInfo, 1000)) {
                    MediaCodec.INFO_TRY_AGAIN_LATER -> {

                    }
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        listener.onOutputFormatChanged(encodedCount, encoder.outputFormat)
                    }
                    else -> {
                        check(encoderOutputBufferIndex >= 0)
                        if (bufferInfo.size != 0) {
                            encoder.getOutputBuffer(encoderOutputBufferIndex)?.let { buffer ->
                                listener.onOutputEncoded(encodedCount, buffer, bufferInfo)
                                encodedCount++
                            }
                        }

                        encoder.releaseOutputBuffer(encoderOutputBufferIndex, false)
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            break@loop
                        }
                    }
                }
            }
            decoder.stop()
            encoder.stop()
            Log.i(TAG, "muxVideo: decoderCount: $decoderCount, encodedCount: $encodedCount")
        }
    }
}

interface OnVideoEncoderListener {
    fun onOutputEncoded(frameIndex: Int, byteBuffer: ByteBuffer, bufferInfo: MediaCodec.BufferInfo)
    fun onOutputFormatChanged(frameIndex: Int, outputFormat: MediaFormat)
}
