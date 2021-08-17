//package com.nodaynonight.posedetector
//
//import android.content.Context
//import android.media.*
//import android.net.Uri
//import android.os.*
//import android.view.Surface
//import androidx.annotation.RequiresApi
//import java.io.IOException
//import java.util.*
//import java.util.concurrent.atomic.AtomicReference
//
///**
// * @author wulei
// */
//@RequiresApi(Build.VERSION_CODES.M)
//class SkeletonVideoExporter2(
//    private val context: Context,
//    private val uri: Uri
//) {
//
//    companion object {
//        private const val OUTPUT_VIDEO_MIME = "video/avc"
//        private const val OUTPUT_AUDIO_MIME = "audio/mp4a-latm"
//
//        private const val OUTPUT_AUDIO_MIME_TYPE = "audio/mp4a-latm" // Advanced Audio Coding
//        private const val OUTPUT_AUDIO_CHANNEL_COUNT = 2 // Must match the input stream.
//
//        private const val OUTPUT_AUDIO_BIT_RATE = 128 * 1024
//        private const val OUTPUT_AUDIO_AAC_PROFILE = MediaCodecInfo.CodecProfileLevel.AACObjectHE
//        private const val OUTPUT_AUDIO_SAMPLE_RATE_HZ = 44100 // Must match the input stream.
//
//    }
//
//    // We will get these from the decoders when notified of a format change.
//
//    private var mDecoderOutputVideoFormat: MediaFormat? = null
//    private var mDecoderOutputAudioFormat: MediaFormat? = null
//
//    // We will get these from the encoders when notified of a format change.
//    private var mEncoderOutputVideoFormat: MediaFormat? = null
//    private var mEncoderOutputAudioFormat: MediaFormat? = null
//
//    // We will determine these once we have the output format.
//    private var mOutputVideoTrack = -1
//    private var mOutputAudioTrack = -1
//
//    // Whether things are done on the video side.
//    private var mVideoExtractorDone = false
//    private var mVideoDecoderDone = false
//    private var mVideoEncoderDone = false
//
//    // Whether things are done on the audio side.
//    private var mAudioExtractorDone = false
//    private var mAudioDecoderDone = false
//    private var mAudioEncoderDone = false
//    private var mPendingAudioDecoderOutputBufferIndices = LinkedList<Int>()
//    private var mPendingAudioDecoderOutputBufferInfos = LinkedList<MediaCodec.BufferInfo>()
//    private var mPendingAudioEncoderInputBufferIndices = LinkedList<Int>()
//
//    private var mPendingVideoEncoderOutputBufferIndices = LinkedList<Int>()
//    private var mPendingVideoEncoderOutputBufferInfos = LinkedList<MediaCodec.BufferInfo>()
//    private var mPendingAudioEncoderOutputBufferIndices = LinkedList<Int>()
//    private var mPendingAudioEncoderOutputBufferInfos = LinkedList<MediaCodec.BufferInfo>()
//
//    private var mMuxing = false
//
//    private var mVideoExtractedFrameCount = 0
//    private var mVideoDecodedFrameCount = 0
//    private var mVideoEncodedFrameCount = 0
//
//    private var mAudioExtractedFrameCount = 0
//    private var mAudioDecodedFrameCount = 0
//    private var mAudioEncodedFrameCount = 0
//
//    private var mVideoExtractor: MediaExtractor? = null
//    private var mAudioExtractor: MediaExtractor? = null
//    private var mVideoDecoder: MediaCodec? = null
//    private var mAudioDecoder: MediaCodec? = null
//    private var mVideoEncoder: MediaCodec? = null
//    private var mAudioEncoder: MediaCodec? = null
//    private var mMuxer: MediaMuxer? = null
//
//    private val lock = Object()
//
//    @Throws(ExportException::class)
//    fun export() {
//        val path = uri.path
//        checkNotNull(path) { "path should not be null" }
//        println("export path: $path")
//        mVideoExtractor = createExtractor()
//        val videoExtractor = mVideoExtractor!!
//        val videoInputTrack = getAndSelectVideoTrackIndex(videoExtractor)
//        if (videoInputTrack < 0) {
//            return
//        }
//
//        val inputFormat = videoExtractor.getTrackFormat(videoInputTrack)
//        val width = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
//        val height = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
//        val frameRate = inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
//        val duration = inputFormat.getLong(MediaFormat.KEY_DURATION)
//        val rotation = if (inputFormat.containsKey(MediaFormat.KEY_ROTATION)) {
//            inputFormat.getInteger(MediaFormat.KEY_ROTATION)
//        } else {
//            0
//        }
//        val bitRate = if (inputFormat.containsKey(MediaFormat.KEY_BIT_RATE)) {
//            inputFormat.getInteger(MediaFormat.KEY_BIT_RATE)
//        } else {
//            0
//        }
//
//        val videoOutputFormat = MediaFormat.createVideoFormat(OUTPUT_VIDEO_MIME, width, height)
//        videoOutputFormat.apply {
//            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
//            setInteger(MediaFormat.KEY_BIT_RATE, getCompressedBitRate(width, height, bitRate))
//            setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
//            // 10 seconds between I-frames
//            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 10)
//        }
//
//        val outputDir =
//            context.getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: throw ExportPathException()
//        val outputFile = "${outputDir.absolutePath}/exported.mp4"//${SystemClock.uptimeMillis()}.mp4"
//
//        println(
//            "width: $width, height: $height, frameRate: $frameRate, " +
//                    "duration: $duration, rotation: $rotation, bitRate: $bitRate, outputFile: $outputFile"
//        )
//
//        var videoEncoderInfo: MediaCodecInfo? = null
//        var audioEncoderInfo: MediaCodecInfo? = null
//        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.forEach { codeInfo ->
//            if (codeInfo.isEncoder) {
//                codeInfo.supportedTypes.forEach { type ->
//                    if (type.lowercase() == OUTPUT_VIDEO_MIME) {
//                        videoEncoderInfo = codeInfo
//                    } else if (type.lowercase() == OUTPUT_AUDIO_MIME) {
//                        audioEncoderInfo = codeInfo
//                    }
//                }
//            }
//        }
//
//        if (videoEncoderInfo == null) {
//            throw EncoderCodecException()
//        }
//
//        // Create a MediaCodec for the desired codec, then configure it as an encoder with
//        // our desired properties. Request a Surface to use for input.
//        val inputSurfaceReference = AtomicReference<Surface>()
//        mVideoEncoder = createVideoEncoder(videoEncoderInfo!!, videoOutputFormat, inputSurfaceReference)
//        mVideoDecoder = createVideoDecoder(inputFormat)
//
//        val audioExtractor = createExtractor()
//        mAudioExtractor = audioExtractor
//        val audioInputTrack: Int = getAndSelectAudioTrackIndex(audioExtractor)
//        if (audioInputTrack >= 0 && audioEncoderInfo != null) {
//            val audioInputFormat: MediaFormat = audioExtractor.getTrackFormat(audioInputTrack)
//            val outputAudioFormat = MediaFormat.createAudioFormat(
//                OUTPUT_AUDIO_MIME_TYPE, OUTPUT_AUDIO_SAMPLE_RATE_HZ, OUTPUT_AUDIO_CHANNEL_COUNT
//            )
//            outputAudioFormat.setInteger(MediaFormat.KEY_BIT_RATE, OUTPUT_AUDIO_BIT_RATE)
//            outputAudioFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, OUTPUT_AUDIO_AAC_PROFILE)
//
//            // Create a MediaCodec for the desired codec, then configure it as an encoder with
//            // our desired properties. Request a Surface to use for input.
//            mAudioEncoder = createAudioEncoder(audioEncoderInfo!!, outputAudioFormat)
//            // Create a MediaCodec for the decoder, based on the extractor's format.
//            mAudioDecoder = createAudioDecoder(audioInputFormat)
//        }
//        mMuxer = MediaMuxer(outputFile, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
//
//        try {
//            awaitEncode()
//        } finally {
//            // Try to release everything we acquired, even if one of the releases fails, in which
//            // case we save the first exception we got and re-throw at the end (unless something
//            // other exception has already been thrown). This guarantees the first exception thrown
//            // is reported as the cause of the error, everything is (attempted) to be released, and
//            // all other exceptions appear in the logs.
//            try {
//                if (mVideoExtractor != null) {
//                    mVideoExtractor?.release()
//                }
//            } catch (ignored: Exception) {
//            }
//            try {
//                if (mAudioExtractor != null) {
//                    mAudioExtractor?.release()
//                }
//            } catch (ignored: Exception) {
//            }
//            try {
//                if (mVideoDecoder != null) {
//                    mVideoDecoder?.stop()
//                    mVideoDecoder?.release()
//                }
//            } catch (ignored: Exception) {
//            }
//            try {
//                if (mVideoEncoder != null) {
//                    mVideoEncoder?.stop()
//                    mVideoEncoder?.release()
//                }
//            } catch (ignored: Exception) {
//            }
//            try {
//                if (mAudioDecoder != null) {
//                    mAudioDecoder?.stop()
//                    mAudioDecoder?.release()
//                }
//            } catch (ignored: Exception) {
//            }
//            try {
//                if (mAudioEncoder != null) {
//                    mAudioEncoder?.stop()
//                    mAudioEncoder?.release()
//                }
//            } catch (ignored: Exception) {
//            }
//            try {
//                if (mMuxer != null) {
//                    mMuxer?.stop()
//                    mMuxer?.release()
//                }
//            } catch (ignored: Exception) {
//            }
//            if (mVideoDecoderHandlerThread != null) {
//                mVideoDecoderHandlerThread?.quitSafely()
//            }
//            mVideoExtractor = null
//            mAudioExtractor = null
//            mVideoDecoder = null
//            mAudioDecoder = null
//            mVideoEncoder = null
//            mAudioEncoder = null
//            mMuxer = null
//            mVideoDecoderHandlerThread = null
//        }
//    }
//
//    private fun awaitEncode() {
//        synchronized(lock) {
//            while (!mVideoEncoderDone || !mAudioEncoderDone) {
//                try {
//                    lock.wait()
//                } catch (ie: InterruptedException) {
//                }
//            }
//        }
//    }
//
//    inner class CallbackHandler(l: Looper) : Handler(l) {
//        var codec: MediaCodec? = null
//            private set
//        private var mEncoder = false
//        private var mCallback: MediaCodec.Callback? = null
//        private var mMime: String? = null
//        private var mSetDone = false
//        override fun handleMessage(msg: Message) {
//            try {
//                codec =
//                    if (mEncoder) MediaCodec.createEncoderByType(mMime!!) else MediaCodec.createDecoderByType(mMime!!)
//            } catch (ioe: IOException) {
//            }
//            codec!!.setCallback(mCallback)
//            synchronized(lock) {
//                mSetDone = true
//                lock.notifyAll()
//            }
//        }
//
//        fun create(encoder: Boolean, mime: String?, callback: MediaCodec.Callback?) {
//            mEncoder = encoder
//            mMime = mime
//            mCallback = callback
//            mSetDone = false
//            sendEmptyMessage(0)
//            synchronized(lock) {
//                while (!mSetDone) {
//                    try {
//                        lock.wait()
//                    } catch (ie: InterruptedException) {
//                    }
//                }
//            }
//        }
//    }
//
//    private var mVideoDecoderHandlerThread: HandlerThread? = null
//    private var mVideoDecoderHandler: CallbackHandler? = null
//
//    /**
//     * Creates a decoder for the given format, which outputs to the given surface.
//     *
//     * @param inputFormat the format of the stream to decode
//     * @param surface into which to decode the frames
//     */
//    @Throws(IOException::class)
//    private fun createVideoDecoder(inputFormat: MediaFormat, surface: Surface? = null): MediaCodec {
//        mVideoDecoderHandlerThread = HandlerThread("DecoderThread")
//        mVideoDecoderHandlerThread!!.start()
//        mVideoDecoderHandler = CallbackHandler(mVideoDecoderHandlerThread!!.looper)
//        val callback: MediaCodec.Callback = object : MediaCodec.Callback() {
//            override fun onError(codec: MediaCodec, exception: MediaCodec.CodecException) {}
//            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
//                mDecoderOutputVideoFormat = codec.outputFormat
//            }
//
//            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
//                // Extract video from file and feed to decoder.
//                // We feed packets regardless of whether the muxer is set up or not.
//                // If the muxer isn't set up yet, the encoder output will be queued up,
//                // finally blocking the decoder as well.
//                val decoderInputBuffer = codec.getInputBuffer(index)
//                while (!mVideoExtractorDone) {
//                    val size = mVideoExtractor!!.readSampleData(decoderInputBuffer!!, 0)
//                    val presentationTime = mVideoExtractor!!.sampleTime
//                    if (size >= 0) {
//                        codec.queueInputBuffer(
//                            index,
//                            0,
//                            size,
//                            presentationTime,
//                            mVideoExtractor!!.sampleFlags
//                        )
//                    }else {
//                        codec.queueInputBuffer(
//                            index,
//                            0,
//                            0,
//                            0,
//                            MediaCodec.BUFFER_FLAG_END_OF_STREAM
//                        )
//                        mVideoExtractorDone = true
//                    }
//                    mVideoExtractor!!.advance()
//                    mVideoExtractedFrameCount++
//                    if (size >= 0) break
//                }
//            }
//
//            override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
//                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
//                    codec.releaseOutputBuffer(index, false)
//                    return
//                }
//                val render = info.size != 0
//                codec.releaseOutputBuffer(index, render)
//                if (render) {
//                    // render
//                }
//                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
//                    mVideoDecoderDone = true
//                    mVideoEncoder!!.signalEndOfInputStream()
//                }
//                mVideoDecodedFrameCount++
//            }
//        }
//        // Create the decoder on a different thread, in order to have the callbacks there.
//        // This makes sure that the blocking waiting and rendering in onOutputBufferAvailable
//        // won't block other callbacks (e.g. blocking encoder output callbacks), which
//        // would otherwise lead to the transcoding pipeline to lock up.
//
//        // Since API 23, we could just do setCallback(callback, mVideoDecoderHandler) instead
//        // of using a custom Handler and passing a message to create the MediaCodec there.
//
//        // When the callbacks are received on a different thread, the updating of the variables
//        // that are used for state logging (mVideoExtractedFrameCount, mVideoDecodedFrameCount,
//        // mVideoExtractorDone and mVideoDecoderDone) should ideally be synchronized properly
//        // against accesses from other threads, but that is left out for brevity since it's
//        // not essential to the actual transcoding.
//        mVideoDecoderHandler!!.create(
//            false, getMimeTypeFor(inputFormat), callback
//        )
//        val decoder = mVideoDecoderHandler!!.codec
//        decoder!!.configure(inputFormat, surface, null, 0)
//        decoder.start()
//        return decoder
//    }
//
//    /**
//     * Creates an encoder for the given format using the specified codec, taking input from a
//     * surface.
//     *
//     *
//     * The surface to use as input is stored in the given reference.
//     *
//     * @param codecInfo of the codec to use
//     * @param format of the stream to be produced
//     * @param surfaceReference to store the surface to use as input
//     */
//    @Throws(IOException::class)
//    private fun createVideoEncoder(
//        codecInfo: MediaCodecInfo,
//        format: MediaFormat,
//        surfaceReference: AtomicReference<Surface>
//    ): MediaCodec {
//        val encoder = MediaCodec.createByCodecName(codecInfo.name)
//        encoder.setCallback(object : MediaCodec.Callback() {
//            override fun onError(codec: MediaCodec, exception: MediaCodec.CodecException) {}
//            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
//                check(mOutputVideoTrack < 0) { "video encoder changed its output format again?" }
//                mEncoderOutputVideoFormat = codec.outputFormat
//                setupMuxer()
//            }
//
//            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {}
//            override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
//                muxVideo(index, info)
//            }
//        })
//        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
//        // Must be called before start() is.
//        surfaceReference.set(encoder.createInputSurface())
//        encoder.start()
//        return encoder
//    }
//
//    /**
//     * Creates a decoder for the given format.
//     *
//     * @param inputFormat the format of the stream to decode
//     */
//    @Throws(IOException::class)
//    private fun createAudioDecoder(inputFormat: MediaFormat): MediaCodec {
//        val decoder = MediaCodec.createDecoderByType(getMimeTypeFor(inputFormat)!!)
//        decoder.setCallback(object : MediaCodec.Callback() {
//            override fun onError(codec: MediaCodec, exception: MediaCodec.CodecException) {}
//            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
//                mDecoderOutputAudioFormat = codec.outputFormat
//            }
//
//            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
//                val decoderInputBuffer = codec.getInputBuffer(index)
//                while (!mAudioExtractorDone) {
//                    val size = mAudioExtractor!!.readSampleData(decoderInputBuffer!!, 0)
//                    val presentationTime = mAudioExtractor!!.sampleTime
//                    if (size >= 0) {
//                        codec.queueInputBuffer(
//                            index,
//                            0,
//                            size,
//                            presentationTime,
//                            mAudioExtractor!!.sampleFlags
//                        )
//                    } else {
//                        codec.queueInputBuffer(
//                            index,
//                            0,
//                            0,
//                            0,
//                            MediaCodec.BUFFER_FLAG_END_OF_STREAM
//                        )
//                        mAudioExtractorDone = true
//                    }
//                    mAudioExtractor!!.advance()
//                    mAudioExtractedFrameCount++
//                    if (size >= 0) break
//                }
//            }
//
//            override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
//                val decoderOutputBuffer = codec.getOutputBuffer(index)
//                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
//                    codec.releaseOutputBuffer(index, false)
//                    return
//                }
//                mPendingAudioDecoderOutputBufferIndices.add(index)
//                mPendingAudioDecoderOutputBufferInfos.add(info)
//                mAudioDecodedFrameCount++
//                tryEncodeAudio()
//            }
//        })
//        decoder.configure(inputFormat, null, null, 0)
//        decoder.start()
//        return decoder
//    }
//
//    /**
//     * Creates an encoder for the given format using the specified codec.
//     *
//     * @param codecInfo of the codec to use
//     * @param format of the stream to be produced
//     */
//    @Throws(IOException::class)
//    private fun createAudioEncoder(codecInfo: MediaCodecInfo, format: MediaFormat): MediaCodec? {
//        val encoder = MediaCodec.createByCodecName(codecInfo.name)
//        encoder.setCallback(object : MediaCodec.Callback() {
//            override fun onError(codec: MediaCodec, exception: MediaCodec.CodecException) {}
//            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
//                check(mOutputAudioTrack < 0) { "audio encoder changed its output format again?" }
//                mEncoderOutputAudioFormat = codec.outputFormat
//                setupMuxer()
//            }
//
//            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
//                mPendingAudioEncoderInputBufferIndices.add(index)
//                tryEncodeAudio()
//            }
//
//            override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
//                muxAudio(index, info)
//            }
//        })
//        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
//        encoder.start()
//        return encoder
//    }
//
//    // No need to have synchronization around this, since both audio encoder and
//    // decoder callbacks are on the same thread.
//    private fun tryEncodeAudio() {
//        if (mPendingAudioEncoderInputBufferIndices.size == 0 ||
//            mPendingAudioDecoderOutputBufferIndices.size == 0
//        ) return
//        val decoderIndex = mPendingAudioDecoderOutputBufferIndices.poll()
//        val encoderIndex = mPendingAudioEncoderInputBufferIndices.poll()
//        val info = mPendingAudioDecoderOutputBufferInfos.poll()
//        val encoderInputBuffer = mAudioEncoder!!.getInputBuffer(encoderIndex)
//        val size = info.size
//        val presentationTime = info.presentationTimeUs
//
//        if (size >= 0) {
//            val decoderOutputBuffer = mAudioDecoder!!.getOutputBuffer(decoderIndex)!!.duplicate()
//            decoderOutputBuffer.position(info.offset)
//            decoderOutputBuffer.limit(info.offset + size)
//            encoderInputBuffer!!.position(0)
//            encoderInputBuffer.put(decoderOutputBuffer)
//            mAudioEncoder!!.queueInputBuffer(
//                encoderIndex,
//                0,
//                size,
//                presentationTime,
//                info.flags
//            )
//        }
//        mAudioDecoder!!.releaseOutputBuffer(decoderIndex, false)
//        if ((info.flags
//                    and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
//        ) {
//            mAudioDecoderDone = true
//        }
//    }
//
//    private fun setupMuxer() {
//        if (!mMuxing && mEncoderOutputVideoFormat != null) {
//            mOutputVideoTrack = mMuxer!!.addTrack(mEncoderOutputVideoFormat!!)
//            if (mEncoderOutputAudioFormat != null) {
//                mOutputAudioTrack = mMuxer!!.addTrack(mEncoderOutputAudioFormat!!)
//            }
//            mMuxer!!.start()
//            mMuxing = true
//            var info: MediaCodec.BufferInfo?
//            while (mPendingVideoEncoderOutputBufferInfos.poll().also { info = it } != null) {
//                val index = mPendingVideoEncoderOutputBufferIndices.poll().toInt()
//                muxVideo(index, info!!)
//            }
//            while (mPendingAudioEncoderOutputBufferInfos.poll().also { info = it } != null) {
//                val index = mPendingAudioEncoderOutputBufferIndices.poll().toInt()
//                muxAudio(index, info!!)
//            }
//        }
//    }
//
//    private fun muxVideo(index: Int, info: MediaCodec.BufferInfo) {
//        if (!mMuxing) {
//            mPendingVideoEncoderOutputBufferIndices.add(index)
//            mPendingVideoEncoderOutputBufferInfos.add(info)
//            return
//        }
//        val encoderOutputBuffer = mVideoEncoder!!.getOutputBuffer(index)
//        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
//            // Simply ignore codec config buffers.
//            mVideoEncoder!!.releaseOutputBuffer(index, false)
//            return
//        }
//        if (info.size != 0) {
//            mMuxer!!.writeSampleData(
//                mOutputVideoTrack, encoderOutputBuffer!!, info
//            )
//        }
//        mVideoEncoder!!.releaseOutputBuffer(index, false)
//        mVideoEncodedFrameCount++
//        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
//            synchronized(lock) {
//                mVideoEncoderDone = true
//                lock.notifyAll()
//            }
//        }
//    }
//
//    private fun muxAudio(index: Int, info: MediaCodec.BufferInfo) {
//        if (!mMuxing) {
//            mPendingAudioEncoderOutputBufferIndices.add(index)
//            mPendingAudioEncoderOutputBufferInfos.add(info)
//            return
//        }
//        val encoderOutputBuffer = mAudioEncoder!!.getOutputBuffer(index)
//        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
//            // Simply ignore codec config buffers.
//            mAudioEncoder!!.releaseOutputBuffer(index, false)
//            return
//        }
//        if (info.size != 0) {
//            mMuxer!!.writeSampleData(
//                mOutputAudioTrack, encoderOutputBuffer!!, info
//            )
//        }
//        mAudioEncoder!!.releaseOutputBuffer(index, false)
//        mAudioEncodedFrameCount++
//        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
//            synchronized(lock) {
//                mAudioEncoderDone = true
//                lock.notifyAll()
//            }
//        }
//    }
//
//    private fun getCompressedBitRate(width: Int, height: Int, bitRate: Int): Int {
//        val pixels = width * height
//        val kbps = if (pixels >= 1920 * 1080) {
//            4992
//        } else if (pixels >= 1280 * 720) {
//            2496
//        } else if (pixels >= 960 * 540) {
//            1856
//        } else {
//            1216
//        }
//        val compressed = kbps * 1024
//        if (bitRate in 1 until compressed) {
//            return bitRate
//        }
//        return compressed
//    }
//
//    private fun getAndSelectVideoTrackIndex(extractor: MediaExtractor): Int {
//        for (index in 0 until extractor.trackCount) {
//            if (isVideoFormat(extractor.getTrackFormat(index))) {
//                extractor.selectTrack(index)
//                return index
//            }
//        }
//        return -1
//    }
//
//    private fun getAndSelectAudioTrackIndex(extractor: MediaExtractor): Int {
//        for (index in 0 until extractor.trackCount) {
//            if (isAudioFormat(extractor.getTrackFormat(index))) {
//                extractor.selectTrack(index)
//                return index
//            }
//        }
//        return -1
//    }
//
//    private fun isVideoFormat(format: MediaFormat): Boolean {
//        return getMimeTypeFor(format)?.startsWith("video/") ?: false
//    }
//
//    private fun isAudioFormat(format: MediaFormat): Boolean {
//        return getMimeTypeFor(format)?.startsWith("audio/") ?: false
//    }
//
//    private fun getMimeTypeFor(format: MediaFormat): String? {
//        return format.getString(MediaFormat.KEY_MIME)
//    }
//
//    private fun createExtractor(): MediaExtractor {
//        val extractor = MediaExtractor()
//        extractor.setDataSource(context, uri, null)
//        return extractor
//    }
//}