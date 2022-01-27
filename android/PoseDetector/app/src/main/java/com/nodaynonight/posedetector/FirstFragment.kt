package com.nodaynonight.posedetector

import android.app.Activity.RESULT_OK
import android.content.Intent
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import androidx.fragment.app.Fragment
import com.nodaynonight.posedetector.databinding.FragmentFirstBinding
import com.osmapps.golf.common.bean.domain.practice2.SwingDetectionResult
import com.osmapps.golf.common.gson.GsonFactory
import com.osmapps.golf.model.practice2.SwingDetectionManager
import com.squarevalley.i8birdies.improve.aicoach.detection.JointDetectionManager
import com.squarevalley.i8birdies.improve.aicoach.detection.SkeletonMediaUtil
import com.squarevalley.i8birdies.improve.aicoach.detection.SkeletonVideoExporter
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import java.io.FileOutputStream
import kotlin.concurrent.thread

/**
 * A simple [Fragment] subclass as the default destination in the navigation.
 */
class FirstFragment : Fragment() {

    private var _binding: FragmentFirstBinding? = null

    // This property is only valid between onCreateView and
    // onDestroyView.
    private val binding get() = _binding!!

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {

        _binding = FragmentFirstBinding.inflate(inflater, container, false)
        return binding.root

    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        binding.fab.setOnClickListener {
            val intent = Intent(Intent.ACTION_PICK, MediaStore.Video.Media.EXTERNAL_CONTENT_URI).apply {
//                addCategory(Intent.CATEGORY_OPENABLE)
                type = "video/*"
            }
            startActivityForResult(intent, 1)
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            1 -> {
                if (resultCode == RESULT_OK) {
                    binding.resultText.text = null
                    data?.data?.let {
                        thread {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val jointDetectionResult =
                                    JointDetectionManager.INSTANCE.detectVideo(requireContext(), it)
                                if (jointDetectionResult != null) {
                                    val json =
                                        GsonFactory.createCommonGsonBuilder().create().toJson(jointDetectionResult)
                                    var swingDetectionResult =
                                        SwingDetectionManager.INSTANCE.detect(jointDetectionResult)
                                    MainScope().launch {
                                        binding.resultText.setText("swing size: ${swingDetectionResult.detectedSwings?.size}")
                                        val outputDir =
                                            requireContext().getExternalFilesDir(Environment.DIRECTORY_MOVIES)!!
                                        val outputFile = "${outputDir.absolutePath}/joint.json"
                                        val fos = FileOutputStream(outputFile)
                                        fos.write(json.toByteArray())
                                        fos.close();
                                    }
                                    val exportedFilesSize = mutableMapOf<String, Int>()
                                    if (swingDetectionResult.detectedSwings.isNullOrEmpty()) {
                                        println("no swing found")
                                        val segments = mutableListOf<SwingDetectionResult.SwingSegment>()
                                        segments.add(SwingDetectionResult.SwingSegment(0, 11))
                                        segments.add(SwingDetectionResult.SwingSegment(11, 20))
                                        segments.add(SwingDetectionResult.SwingSegment(21, 30))
                                        segments.add(
                                            SwingDetectionResult.SwingSegment(
                                                31,
                                                jointDetectionResult.duration - 1
                                            )
                                        )

                                        val detectedSwing = SwingDetectionResult.DetectedSwing.fromSegments(
                                            SwingDetectionResult.StandType.FACE_ON,
                                            SwingDetectionResult.HandType.LEFT,
                                            segments
                                        )

                                        val segments2 = mutableListOf<SwingDetectionResult.SwingSegment>()
                                        segments2.add(SwingDetectionResult.SwingSegment(120, 160))
                                        segments2.add(SwingDetectionResult.SwingSegment(161, 170))
                                        segments2.add(SwingDetectionResult.SwingSegment(171, 180))
                                        segments2.add(SwingDetectionResult.SwingSegment(181, 190))

                                        val detectedSwing2 = SwingDetectionResult.DetectedSwing.fromSegments(
                                            SwingDetectionResult.StandType.FACE_ON,
                                            SwingDetectionResult.HandType.LEFT,
                                            segments2
                                        )
                                        val detectedSwings =
                                            mutableListOf<SwingDetectionResult.DetectedSwing>(
                                                detectedSwing,
//                                                detectedSwing2
                                            )

                                        swingDetectionResult = SwingDetectionResult(1.0, detectedSwings)
                                    }
                                    SkeletonVideoExporter.export(
                                        requireContext(),
                                        it,
                                        jointDetectionResult,
                                        swingDetectionResult,
                                    ) { current, joints, exportFile ->
                                        checkNotNull(exportFile)
                                        exportedFilesSize[exportFile] = joints.duration
                                        println("exporting: $current, exportFile:$exportFile, duration: ${joints.duration}")
                                    }
                                    exportedFilesSize.forEach { (exportFile, count) ->
                                        val extractor = SkeletonMediaUtil.createMediaExtractor(
                                            requireContext(),
                                            Uri.parse(exportFile)
                                        )
                                        val videoInputTrack =
                                            SkeletonMediaUtil.getAndSelectVideoTrackIndex(extractor)
                                        check(videoInputTrack >= 0)
                                        val decoderFormat = extractor.getTrackFormat(videoInputTrack)
                                        val mime = decoderFormat.getString(MediaFormat.KEY_MIME)!!
                                        val width = decoderFormat.getInteger(MediaFormat.KEY_WIDTH)
                                        val height = decoderFormat.getInteger(MediaFormat.KEY_HEIGHT)
                                        val frameRate = decoderFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
                                        val frameCount = if (decoderFormat.containsKey("frame-count")) {
                                            decoderFormat.getInteger("frame-count")
                                        } else {
                                            -1
                                        }
                                        val rotation = if (decoderFormat.containsKey(MediaFormat.KEY_ROTATION)) {
                                            decoderFormat.getInteger(MediaFormat.KEY_ROTATION)
                                        } else {
                                            -1
                                        }
                                        println("check -- file:$exportFile, mime: $mime, width: $width, height: $height, frameRate: $frameRate, rotation: $rotation, frameCount: $frameCount, jointsCount: $count")
                                    }

                                } else {
                                    println("no joint found")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}