package com.nodaynonight.posedetector

import android.app.Activity.RESULT_OK
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import com.nodaynonight.posedetector.databinding.FragmentFirstBinding
import com.osmapps.golf.model.practice2.SwingDetectionManager
import com.squarevalley.i8birdies.improve.aicoach.detection.JointDetectionManager
import com.squarevalley.i8birdies.improve.aicoach.detection.SkeletonVideoExporter
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            1 -> {
                if (resultCode == RESULT_OK) {
                    data?.data?.let {
                        thread {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
//                                val segments = mutableListOf<SwingDetectionResult.SwingSegment>()
//                                segments.add(SwingDetectionResult.SwingSegment(0, 10))
//                                segments.add(SwingDetectionResult.SwingSegment(11, 20))
//                                segments.add(SwingDetectionResult.SwingSegment(21, 30))
//                                segments.add(SwingDetectionResult.SwingSegment(31, 40))
//
//                                val detectedSwing = SwingDetectionResult.DetectedSwing.fromSegments(
//                                    SwingDetectionResult.StandType.FACE_ON,
//                                    SwingDetectionResult.HandType.LEFT,
//                                    segments
//                                )
//
//                                val segments2 = mutableListOf<SwingDetectionResult.SwingSegment>()
//                                segments2.add(SwingDetectionResult.SwingSegment(50, 60))
//                                segments2.add(SwingDetectionResult.SwingSegment(61, 70))
//                                segments2.add(SwingDetectionResult.SwingSegment(71, 80))
//                                segments2.add(SwingDetectionResult.SwingSegment(81, 90))
//
//                                val detectedSwing2 = SwingDetectionResult.DetectedSwing.fromSegments(
//                                    SwingDetectionResult.StandType.FACE_ON,
//                                    SwingDetectionResult.HandType.LEFT,
//                                    segments2
//                                )
//                                val detectedSwings =
//                                    mutableListOf<SwingDetectionResult.DetectedSwing>(detectedSwing, detectedSwing2)
//
//                                val swingDetectionResult = SwingDetectionResult(1.0, detectedSwings)
                                val jointDetectionResult =
                                    JointDetectionManager.INSTANCE.detectVideo(requireContext(), it)
                                if (jointDetectionResult != null) {
                                    val swingDetectionResult =
                                        SwingDetectionManager.INSTANCE.detect(jointDetectionResult)
                                    if (!swingDetectionResult.detectedSwings.isNullOrEmpty()) {
                                        SkeletonVideoExporter.export(
                                            requireContext(),
                                            it,
                                            swingDetectionResult
                                        ) { current, total, exportFile ->
                                            println("exporting: $current/$total, exportFile:$exportFile")
                                        }
                                    } else {
                                        println("no swing found")
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