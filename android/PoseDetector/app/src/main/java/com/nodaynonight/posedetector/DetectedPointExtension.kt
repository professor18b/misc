package com.nodaynonight.posedetector

import com.osmapps.golf.common.bean.domain.practice2.JointDetectionResult

fun List<JointDetectionResult.DetectedPoint?>.getValidJointCount(): Int {
    return this.count { it != null }
}