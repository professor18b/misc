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
    
    private let analysisManager = SwingAnalysisManager.shared
    private let jointColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.8)
    private let jointSegmentColor = CGColor(red: 0, green: 1, blue: 0, alpha: 0.8)
    
    let frame: CGRect
    let orientation: CGImagePropertyOrientation
    
    private var scaled: CGFloat?
    private var jointRadius: CGFloat = 0
    private var jointDiameter: CGFloat = 0
    
    private let scalingTransform: CGAffineTransform
    private let contextRotation: CGFloat?
    private let contextTranslation: CGPoint?
    
    init(videoSize: CGSize, orientation: CGImagePropertyOrientation) {
        self.orientation = orientation
        switch orientation {
        case .right:
            frame = CGRect(x: 0, y: 0, width: videoSize.height, height: videoSize.width)
            contextRotation = .pi / 2
            contextTranslation = CGPoint(x: videoSize.width, y: 0)
        default:
            frame = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height)
            contextRotation = nil
            contextTranslation = nil
        }
        
        scalingTransform = CGAffineTransform(scaleX: frame.width, y: frame.height)
      print("videoSize: \(videoSize)")
      print("frame: \(frame)")
    }
    
    func render(in cgContext: CGContext, joints: [String: DetectedPoint], debugContext: DebugContext? = nil) {
        // calculate scale
        scaled = calculateScale(joints: joints)
        if let scaled = scaled {
            jointRadius = 9 * scaled
            jointDiameter = jointRadius * 2
        }
        
        // transform points
        var transformedJoints: [String: CGPoint] = [:]
        for entry in joints {
            let point = entry.value.location.applying(scalingTransform)
            transformedJoints[entry.key] = point
        }
        cgContext.saveGState()
        if let translation = contextTranslation {
            cgContext.translateBy(x: translation.x, y: translation.y)
        }
        if let rotation = contextRotation {
            cgContext.rotate(by: rotation)
        }
        
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
                if let startPoint = transformedJoints[start.keyName] {
                    if let endPoint = transformedJoints[end.keyName] {
                        cgContext.move(to: startPoint)
                        cgContext.addLine(to: endPoint)
                    }
                }
                index += 1
            }
        }
        cgContext.drawPath(using: .stroke)
        // draw all the joints
        cgContext.setFillColor(jointColor)
        for entry in transformedJoints {
            addJointCirclr(cgContext: cgContext, point: entry.value)
        }
        cgContext.drawPath(using: .fill)
      
      cgContext.setFillColor(CGColor(red: 1, green: 0.5, blue: 1, alpha: 0.8))
      addJointCirclr(cgContext: cgContext, point: CGPoint(x: 10.0,y: 10.0))
      addJointCirclr(cgContext: cgContext, point: CGPoint(x: 100.0,y: 10.0))
      addJointCirclr(cgContext: cgContext, point: CGPoint(x: 500.0,y: 10.0))
      addJointCirclr(cgContext: cgContext, point: CGPoint(x: 800.0,y: 10.0))
      
      addJointCirclr(cgContext: cgContext, point: CGPoint(x: 100.0,y: 10.0))
      addJointCirclr(cgContext: cgContext, point: CGPoint(x: 100.0,y: 100.0))
      addJointCirclr(cgContext: cgContext, point: CGPoint(x: 100.0,y: 500.0))
      addJointCirclr(cgContext: cgContext, point: CGPoint(x: 100.0,y: 800.0))
      addJointCirclr(cgContext: cgContext, point: CGPoint(x: 100.0,y: 1000.0))
      cgContext.drawPath(using: .fill)
    
        
        // debug --------------------------
        if let context = debugContext {
            // draw writed wrist track
            var lastCenterPoint: CGPoint? = nil
            if !context.writedFrameJoints.isEmpty {
                cgContext.setStrokeColor(CGColor(red: 0, green: 0.5, blue: 0.5, alpha: 0.6))
                index = 0
                while index < context.writedFrameJoints.count - 1 {
                    let start = context.writedFrameJoints[index]
                    let startLeftPoint =  start[VNHumanBodyPoseObservation.JointName.leftWrist.keyName]?.location.applying(scalingTransform)
                    let startRightPoint =  start[VNHumanBodyPoseObservation.JointName.rightWrist.keyName]?.location.applying(scalingTransform)
                    let startCenter = getCenterPoint(leftPoint: startLeftPoint, rightPoint: startRightPoint)
                    let end = context.writedFrameJoints[index + 1]
                    let endLeftPoint =  end[VNHumanBodyPoseObservation.JointName.leftWrist.keyName]?.location.applying(scalingTransform)
                    let endRightPoint =  end[VNHumanBodyPoseObservation.JointName.rightWrist.keyName]?.location.applying(scalingTransform)
                    let endCenter = getCenterPoint(leftPoint: endLeftPoint, rightPoint: endRightPoint)
                    if startCenter != nil && endCenter != nil {
                        cgContext.move(to: startCenter!)
                        cgContext.addLine(to: endCenter!)
                        lastCenterPoint = endCenter
                    }
                    index += 1
                }
                cgContext.drawPath(using: .stroke)
            }
            
            // draw wrists
            cgContext.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 0.8))
            addJointCirclr(cgContext: cgContext, point: transformedJoints[VNHumanBodyPoseObservation.JointName.leftWrist.keyName])
            addJointCirclr(cgContext: cgContext, point: transformedJoints[VNHumanBodyPoseObservation.JointName.rightWrist.keyName])
            cgContext.drawPath(using: .fill)
            
            // draw center wrist
            if let wristCenterPoint = getCenterPoint(
                leftPoint: transformedJoints[VNHumanBodyPoseObservation.JointName.leftWrist.keyName],
                rightPoint: transformedJoints[VNHumanBodyPoseObservation.JointName.rightWrist.keyName]
            ) {
                addJointCirclr(cgContext: cgContext, point: wristCenterPoint)
                cgContext.setFillColor(CGColor(red: 1, green: 0.5, blue: 1, alpha: 0.8))
                cgContext.drawPath(using: .fill)
                // draw current wrist track
                if let lastCenterPoint = lastCenterPoint {
                    cgContext.move(to: lastCenterPoint)
                    cgContext.addLine(to: wristCenterPoint)
                }
                cgContext.drawPath(using: .stroke)
                
                // draw wrist to neck
                cgContext.setStrokeColor(CGColor(red: 1, green: 0, blue: 1, alpha: 0.8))
                if let neckPoint = transformedJoints[VNHumanBodyPoseObservation.JointName.neck.keyName] {
                    cgContext.move(to: wristCenterPoint)
                    cgContext.addLine(to: neckPoint)
                    cgContext.drawPath(using: .stroke)
                }
            }
            
            
            // draw frame index
            let fontName = "Courier" as CFString
            let font = CTFontCreateWithName(fontName, 60, nil)
            let attributes = [NSAttributedString.Key.font: font]
            let attributedString = NSAttributedString(string: "\(context.writingFrameIndex)", attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributedString)
            cgContext.textPosition = CGPoint(x: 80, y: frame.height - 120)
            
            CTLineDraw(line, cgContext)
        }
        //-------------------------------------------
        cgContext.restoreGState()
    }
    
    private func calculateScale(joints: [String: DetectedPoint]) -> CGFloat? {
        if let neck = joints[VNHumanBodyPoseObservation.JointName.neck.keyName] {
            if let root = joints[VNHumanBodyPoseObservation.JointName.root.keyName] {
                let distanceY = abs(neck.location.y - root.location.y)
                // we consider 0.13155192136764526 is a standard value
                return (distanceY / 0.13155192136764526) * (frame.height / 1920)
            }
        }
        return nil
    }
    
    private func getCenterPoint(leftPoint: CGPoint?, rightPoint: CGPoint?, maxDistanceInPixel: CGFloat = 60) -> CGPoint? {
        if leftPoint != nil && rightPoint != nil {
            if abs(leftPoint!.x - rightPoint!.x) < maxDistanceInPixel && abs(leftPoint!.y - rightPoint!.y) < maxDistanceInPixel {
                return CGPoint(x: (leftPoint!.x + rightPoint!.x) / 2, y: (leftPoint!.y + rightPoint!.y) / 2)
            }
        }
        return nil
    }
    
    private func addJointCirclr(cgContext: CGContext, point: CGPoint?) {
        if let point = point {
            let rect = CGRect(x: point.x - jointRadius, y: point.y - jointRadius, width: jointDiameter, height: jointDiameter)
            cgContext.addEllipse(in: rect)
        }
    }
}
