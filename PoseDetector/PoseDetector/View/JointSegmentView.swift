//
//  JointSegmentView.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/6.
//

import UIKit
import Vision

class JointSegmentView: UIView {
    
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
    
    private let jointRadius: CGFloat = 3.0
    private let jointLayer = CAShapeLayer()
    private var jointPath = UIBezierPath()
    
    private let jointSegmentWidth: CGFloat = 2.0
    private let jointSegmentLayer = CAShapeLayer()
    private var jointSegmentPath = UIBezierPath()
    
    private let detectManager = PoseDetectionManager.shared
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    func resetView() {
        jointLayer.path = nil
        jointSegmentLayer.path = nil
    }
    
    private func setupLayer() {
        jointSegmentLayer.lineCap = .round
        jointSegmentLayer.lineWidth = jointSegmentWidth
        jointSegmentLayer.fillColor = UIColor.clear.cgColor
        jointSegmentLayer.strokeColor = UIColor.green.cgColor
        layer.addSublayer(jointSegmentLayer)
        
        let jointColor = UIColor.white.cgColor
        jointLayer.fillColor = jointColor
        jointLayer.strokeColor = jointColor
        layer.addSublayer(jointLayer)
    }
    
    func updateJoints<T: NormalizedGeometryConverting & UIView>(cgImage: CGImage, orientation: CGImagePropertyOrientation, sourceView: T) {
        let joints = detectManager.detect(cgImage: cgImage, orientation: orientation)
        DispatchQueue.main.async {
            let normalizedFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
            self.frame = sourceView.viewRectConverted(fromNormalizedContentsRect: normalizedFrame)
            self.updatePathLayer(joints: joints)
        }
    }
    
    func updateJoints<T: NormalizedGeometryConverting & UIView>(sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, sourceView: T) {
        let joints = detectManager.detect(sampleBuffer: sampleBuffer, orientation: orientation)
        DispatchQueue.main.async {
            if self.frame.width == 0 && sourceView.frame.width > 0 {
                let normalizedFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
                self.frame = sourceView.viewRectConverted(fromNormalizedContentsRect: normalizedFrame)
            }
            self.updatePathLayer(joints: joints)
        }
    }
    
    private func updatePathLayer(joints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        let flipVertical = CGAffineTransform.verticalFlip
        let scaleToBounds = CGAffineTransform(scaleX: bounds.width, y: bounds.height)
        var scaledJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        // add all joints
        jointPath.removeAllPoints()
        for entry in joints {
            let scaledPoint =  entry.value.location.applying(flipVertical).applying(scaleToBounds)
            let path = UIBezierPath(arcCenter: scaledPoint, radius: jointRadius, startAngle: CGFloat(0), endAngle: CGFloat.pi * 2, clockwise: true)
            jointPath.append(path)
            scaledJoints[entry.key] = scaledPoint
        }
        
        // add all segments
        jointSegmentPath.removeAllPoints()
        var firstJonit: Bool!
        for segments in allSegments {
            firstJonit = true
            for joint in segments {
                if let jointScaled = scaledJoints[joint] {
                    if firstJonit {
                        jointSegmentPath.move(to: jointScaled)
                        firstJonit = false
                    } else {
                        jointSegmentPath.addLine(to: jointScaled)
                    }
                }
            }
        }
        jointLayer.path = jointPath.cgPath
        jointSegmentLayer.path = jointSegmentPath.cgPath
    }
}
