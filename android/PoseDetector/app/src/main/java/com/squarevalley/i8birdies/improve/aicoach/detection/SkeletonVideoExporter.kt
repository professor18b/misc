package com.squarevalley.i8birdies.improve.aicoach.detection

import android.content.Context
import android.media.*
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.annotation.RequiresApi
import com.osmapps.golf.common.bean.domain.practice2.SwingDetectionResult
import java.nio.ByteBuffer


abstract class ExportException(message: String) : Exception(message)

class VideoTrackNotFoundException : ExportException("video track not found")
class VideoFormatNotSupportException : ExportException("video format not support")
class ExportPathException : ExportException("export path error")

private class MuxerWrapper(
    val muxer: MediaMuxer,
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
        fun export(
            context: Context,
            uri: Uri,
            swingDetectionResult: SwingDetectionResult,
            progressHandler: ((current: Int, total: Int, exportFile: String) -> Unit)? = null
        ) {
            val path = uri.path
            checkNotNull(path) { "path should not be null" }
            println("export path: $path")
            val videoExtractor = SkeletonMediaUtil.createMediaExtractor(context, uri)
            val videoInputTrack = SkeletonMediaUtil.getAndSelectVideoTrackIndex(videoExtractor)
            if (videoInputTrack < 0) {
                throw VideoTrackNotFoundException()
            }
            val videoDecoderFormat = videoExtractor.getTrackFormat(videoInputTrack)

            // add audio
            val audioExtractor = SkeletonMediaUtil.createMediaExtractor(context, uri)
            val audioInputTrack = SkeletonMediaUtil.getAndSelectAudioTrackIndex(audioExtractor)
            var audioDecoderFormat: MediaFormat? = null
            if (audioInputTrack >= 0) {
                audioDecoderFormat = audioExtractor.getTrackFormat(audioInputTrack)
            }

            val muxers = createMuxers(context, swingDetectionResult)
            muxers.forEach { muxerWrapper ->
                muxerWrapper.addTrack(videoDecoderFormat, audioDecoderFormat)
            }

            muxers.forEach { it.muxer.start() }

            var currentMuxerIndex = 0
            muxVideo(videoExtractor, videoDecoderFormat) { frameIndex, byteBuffer, bufferInfo ->
                muxers.find { frameIndex >= it.segment.first && frameIndex <= it.segment.second }?.apply {
                    muxer.writeSampleData(videoTrackIndex, byteBuffer, bufferInfo)
                    if (startTimeUs == -1L) {
                        startTimeUs = bufferInfo.presentationTimeUs
                    } else {
                        endTimeUs = bufferInfo.presentationTimeUs
                    }
                    if (segmentIndex > currentMuxerIndex) {
                        progressHandler?.invoke(currentMuxerIndex + 1, muxers.size, exportFile)
                        currentMuxerIndex = segmentIndex
                    }
                }
            }
            progressHandler?.invoke(currentMuxerIndex + 1, muxers.size, muxers[muxers.size - 1].exportFile)
            videoExtractor.release()
            println("************** export video finished")
            if (audioDecoderFormat != null) {
                muxAudio(audioExtractor, audioDecoderFormat) { byteBuffer, bufferInfo ->
                    val timeUs = bufferInfo.presentationTimeUs
                    muxers.find { timeUs >= it.startTimeUs && timeUs <= it.endTimeUs }?.apply {
                        muxer.writeSampleData(audioTrackIndex, byteBuffer, bufferInfo)
                    }
                }
                audioExtractor.release()
                println("************** export audio finished")
            }
            muxers.forEach { it.muxer.stop() }
            muxers.forEach { it.muxer.release() }

            println("************** export finished")
        }

        private fun createMuxers(
            context: Context,
            swingDetectionResult: SwingDetectionResult
        ): List<MuxerWrapper> {
            val outputDir = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: throw ExportPathException()
            val muxers = mutableListOf<MuxerWrapper>()
            var index = 0
            swingDetectionResult.detectedSwings.forEach { detectedSwing ->
                val outputFile = "${outputDir.absolutePath}/exported$index.mp4"//${SystemClock.uptimeMillis()}.mp4"
                val muxer = MediaMuxer(outputFile, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                muxers.add(
                    MuxerWrapper(
                        muxer, outputFile, index,
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
            println("mime: $mime")
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

            println(
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
            muxerHandler: (frameIndex: Int, byteBuffer: ByteBuffer, bufferInfo: MediaCodec.BufferInfo) -> Unit
        ) {
            val mime = decoderFormat.getString(MediaFormat.KEY_MIME)!!

            val decoder = try {
                MediaCodec.createDecoderByType(mime)
            } catch (e: Exception) {
                throw VideoFormatNotSupportException()
            }
            val encoder = try {
                MediaCodec.createEncoderByType(mime)
            } catch (e: Exception) {
                throw VideoFormatNotSupportException()
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

            println(
                "mime: $mime, frameCount: $frameCount, width: $width, height: $height, frameRate: $frameRate, " +
                        "duration: $duration, rotation: $rotation, bitRate: $bitRate"
            )

            val encoderFormat = MediaFormat.createVideoFormat(mime, width, height)
            // Set some properties. Failing to specify some of these can cause the MediaCodec
            // configure() call to throw an unhelpful exception.
            encoderFormat.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
            )
            encoderFormat.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            encoderFormat.setLong(MediaFormat.KEY_DURATION, duration)
            encoderFormat.setInteger(MediaFormat.KEY_ROTATION, rotation)
            encoderFormat.setInteger(
                MediaFormat.KEY_BIT_RATE,
                SkeletonMediaUtil.getVideoBitRate(width, height, bitRate)
            )
            encoderFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)


            encoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val encoderInputSurface = encoder.createInputSurface()
            encoder.start()
            decoder.configure(decoderFormat, encoderInputSurface, null, 0)
            decoder.start()

            val decoderBufferInfo = MediaCodec.BufferInfo()
            val encoderBufferInfo = MediaCodec.BufferInfo()
            var encodedCount = 0

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
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        // no output available yet
                    }
                    else -> {
                        check(decoderOutputBufferIndex >= 0)
                        val doRender = (decoderBufferInfo.size != 0)
                        if (doRender) {
//                            decoder.getOutputBuffer(decoderOutputBufferIndex)?.let { buffer ->
//                                val joints = JointDetectionManager.INSTANCE.detect(buffer, rotation)
//                                println("******** joints: ${joints.getValidJointCount()}")
//                                renderCount++
//                            }
                        }
                        decoder.releaseOutputBuffer(decoderOutputBufferIndex, doRender)

                        if ((decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            encoder.signalEndOfInputStream()
                        }
                    }
                }

                when (val encoderOutputBufferIndex = encoder.dequeueOutputBuffer(encoderBufferInfo, 1000)) {
                    MediaCodec.INFO_TRY_AGAIN_LATER,
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    }
                    else -> {
                        check(encoderOutputBufferIndex >= 0)
                        if (encoderBufferInfo.size != 0) {
                            encoder.getOutputBuffer(encoderOutputBufferIndex)?.let { buffer ->
                                muxerHandler(encodedCount, buffer, encoderBufferInfo)
                                encodedCount++
                            }
                        }

                        encoder.releaseOutputBuffer(encoderOutputBufferIndex, false)
                        if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            break@loop
                        }
                    }
                }
            }
            decoder.stop()
            encoder.stop()
            encoderInputSurface.release()
            println("muxVideo: frameCount: $frameCount, encodedCount: $encodedCount")
        }
    }
}
