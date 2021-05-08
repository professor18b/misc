//
//  SkeletonRender.swift
//  PoseDetector
//
//  Created by WuLei on 2021/5/8.
//

import CoreGraphics
import Vision
import CoreText

class SkeletonRender {
    
    private static let joinsOfFace: [VNHumanBodyPoseObservation.JointName] = [
        .rightEar,
        .rightEye,
        .leftEye,
        .leftEar,
        .nose
    ]

    private static let segmentsOfRightArm: [VNHumanBodyPoseObservation.JointName] = [
        .rightShoulder,
        .rightElbow,
        .rightWrist
    ]

    private static let segmentsOfLeftArm: [VNHumanBodyPoseObservation.JointName] = [
        .leftShoulder,
        .leftElbow,
        .leftWrist
    ]
    
    private static let segmentsOfShoulder: [VNHumanBodyPoseObservation.JointName] = [
        .rightShoulder,
        .neck,
        .leftShoulder,
        
    ]
    
    private static let segmentsOfSpine: [VNHumanBodyPoseObservation.JointName] = [
        .neck,
        .root,
    ]
    
    private static let segmentsOfHip: [VNHumanBodyPoseObservation.JointName] = [
        .rightHip,
        .root,
        .leftHip,
    ]

    private static let segmentsOfRightLeg: [VNHumanBodyPoseObservation.JointName] = [
        .rightHip,
        .rightKnee,
        .rightAnkle
    ]

    private static let segmentsOfLeftLeg: [VNHumanBodyPoseObservation.JointName] = [
        .leftHip,
        .leftKnee,
        .leftAnkle
    ]
    
    private let allSegments = [segmentsOfRightArm, segmentsOfLeftArm, segmentsOfShoulder, segmentsOfSpine, segmentsOfHip, segmentsOfRightLeg, segmentsOfLeftLeg]
    
    private let jointRadius: CGFloat = 9
    private let jointDiameter: CGFloat = 18
    private let jointColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.8)
    private let jointSegmentColor = CGColor(red: 0, green: 1, blue: 0, alpha: 0.8)
    
    let frame: CGRect
    
    init(frame: CGRect) {
        self.frame = frame
    }
    
    func render(in cgContext: CGContext, joints: [VNHumanBodyPoseObservation.JointName : VNRecognizedPoint], frameIndex: Int = -1) {
        // scale points
        let scaleToBounds = CGAffineTransform(scaleX: frame.width, y: frame.height)
        var scaledJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for entry in joints {
            let scaledPoint =  entry.value.location.applying(scaleToBounds)
            scaledJoints[entry.key] = scaledPoint
        }
        cgContext.saveGState()
        // draw all the joint segments
        cgContext.setStrokeColor(jointSegmentColor)
        cgContext.setLineCap(.round)
        cgContext.setLineWidth(jointRadius)
        
        var index = 0
        for segments in allSegments {
            index = 0
            while index < segments.count - 1 {
                let start = segments[index]
                let end = segments[index + 1]
                if let startScaled = scaledJoints[start] {
                    if let endScaled = scaledJoints[end] {
                        cgContext.move(to: startScaled)
                        cgContext.addLine(to: endScaled)
                    }
                }
                index += 1
            }
        }
        cgContext.drawPath(using: .stroke)
        // draw all the joints
        cgContext.setFillColor(jointColor)
        for entry in scaledJoints {
            addJointCirclr(cgContext: cgContext, point: entry.value)
        }
        cgContext.drawPath(using: .fill)
        // debug wrist --------------------------
        cgContext.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 0.8))
        addJointCirclr(cgContext: cgContext, point: scaledJoints[.leftWrist])
        addJointCirclr(cgContext: cgContext, point: scaledJoints[.rightWrist])
        cgContext.drawPath(using: .fill)
        
        cgContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.8))
        if let leftWristPoint = scaledJoints[.leftWrist] {
            if let rightWristPoint = scaledJoints[.rightWrist] {
                let centerPoint = CGPoint(x: (leftWristPoint.x + rightWristPoint.x) / 2, y: (leftWristPoint.y + rightWristPoint.y) / 2)
                addJointCirclr(cgContext: cgContext, point: centerPoint)
            }
        }
        cgContext.drawPath(using: .fill)
        //------------------------------------------
        
        if frameIndex >= 0 {
            // draw frame index
            let margin: CGFloat = 80
            let fontName = "Courier" as CFString
            let font = CTFontCreateWithName(fontName, 60, nil)
            let attributes = [NSAttributedString.Key.font: font]
            let attributedString = NSAttributedString(string: "\(frameIndex)", attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributedString)
            cgContext.textPosition = CGPoint(x: margin, y: frame.height - margin)
            CTLineDraw(line, cgContext)
        }
        cgContext.restoreGState()
    }
    
    private func addJointCirclr(cgContext: CGContext, point: CGPoint?) {
        if let point = point {
            let rect = CGRect(x: point.x - jointRadius, y: point.y - jointRadius, width: jointDiameter, height: jointDiameter)
            cgContext.addEllipse(in: rect)
        }
    }
}
