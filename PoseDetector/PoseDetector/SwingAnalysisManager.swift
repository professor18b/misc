//
//  SwingAnalysisManager.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/29.
//

import Vision

class SwingAnalysisManager {
    
    static let shared = SwingAnalysisManager()
    
    private init() {
    }
    
    func getAnalyzedResult(detectedResult: DetectedResult) -> AnalyzedResult {
        let context = createAnalyzeContext(detectedResult: detectedResult)
        var keyFrames = [[-1,-1,-1], [-1,-1,-1], [-1,-1,-1]]
        if context.scaled > 0 {
            let poseSegments = analyzePoses(context: context)
            print(poseSegments)
        }
        return AnalyzedResult(scaled: context.scaled, detectedResult: detectedResult, keyFrames: keyFrames)
    }
    
    private func createAnalyzeContext(detectedResult: DetectedResult) -> AnalyzedContext {
        let locationPerPixel = (1 / detectedResult.size.width, 1 / detectedResult.size.height)
        let verticalDistance = getVerticalDistance(detectedResult: detectedResult)
        let horizontalDistance = verticalDistance * (detectedResult.size.width / detectedResult.size.height)
        print("verticalDistance: \(verticalDistance), horizontalDistance:\(horizontalDistance)")
        let scaled: CGFloat
        if verticalDistance > 0 {
            // we consider 0.56 is a standard vertical distance to draw skeleton line
            scaled = verticalDistance / 0.56
        } else {
            scaled = 0
        }
        return AnalyzedContext(locationPerPixel: locationPerPixel,
                              scaled: scaled,
                              detectedResult: detectedResult)
    }
    
    private func getVerticalDistance(detectedResult: DetectedResult) -> CGFloat {
        var lastMaxEyeInY: CGFloat = 0
        var lastMinAnkleInY: CGFloat = 1
        for joints in detectedResult.joints {
            let leftEyeY = joints[.leftEye]?.location.y ?? 0
            let rightEyeY = joints[.rightEye]?.location.y ?? 0
            let max = fmax(leftEyeY, rightEyeY)
            if max > lastMaxEyeInY {
                lastMaxEyeInY = max
            }
//            print("leftEye: \(leftEyeY)), rightEye: \(rightEyeY)")
//            print("leftEye: \(leftEyeY*detectedResult.size.height), rightEye: \(rightEyeY*detectedResult.size.height)")
            
            let leftAnkleY = joints[.leftAnkle]?.location.y ?? 0
            let rightAnkleY = joints[.rightAnkle]?.location.y ?? 0
            let min = fmin(leftAnkleY, rightAnkleY)
            if min < lastMinAnkleInY {
                lastMinAnkleInY = min
            }
//            print("lefAnkle: \(leftAnkleY)), rightAnkle: \(rightAnkleY)")
//            print("lefAnkle: \(leftAnkleY*detectedResult.size.height), rightAnkle: \(rightAnkleY*detectedResult.size.height)")
        }
        print("maxEyeInY: \(lastMaxEyeInY), maxEyeInYInPixel: \(lastMaxEyeInY * detectedResult.size.height)")
        print("minAnkleInY: \(lastMinAnkleInY), minAnkleInY: \(lastMinAnkleInY * detectedResult.size.height)")
        if( lastMaxEyeInY < 1 && lastMinAnkleInY > 0) {
            return lastMaxEyeInY - lastMinAnkleInY
        }
        return 0
    }
    
    private func analyzePoses(context: AnalyzedContext) -> [PoseSegment] {
        var poseSegments = [PoseSegment]()
        var lastWrist: (CGFloat?, CGFloat?)? = nil
        var lastPose: PoseType? = nil
        let thresholdX = context.locationPerPixel.0 * 5
        let thresholdY = context.locationPerPixel.1 * 5
        let joints = context.detectedResult.joints
        for frame in 0 ... joints.count-1 {
            print("frame: \(frame), left: \(joints[frame][.leftWrist]), right: \(joints[frame][.rightWrist])")
            if let currentWrist = getWristLocation(joints: joints[frame]) {
                if var lastWrist = lastWrist {
                    let currentPose: PoseType?
                    if currentWrist.1! - lastWrist.1! > thresholdY {
                        if currentWrist.0! - lastWrist.0! > thresholdX {
                            currentPose = .leftUp
                        } else if currentWrist.0! - lastWrist.0! < -thresholdX {
                            currentPose = .rightUp
                        } else {
                            currentPose = lastPose
                        }
                    } else if currentWrist.1! - lastWrist.1! < -thresholdY {
                        if currentWrist.0! - lastWrist.0! > thresholdX {
                            currentPose = .rightDown
                        } else if currentWrist.0! - lastWrist.0! < -thresholdX {
                            currentPose = .leftDown
                        } else {
                            currentPose = lastPose
                        }
                    } else if abs(currentWrist.0! - lastWrist.0!) < thresholdX {
                        currentPose = .moveLess
                    } else {
                        currentPose = nil
                    }
                    var currentPoseSegment: PoseSegment? = nil
                    if poseSegments.count > 0 {
                        currentPoseSegment = poseSegments[poseSegments.count - 1]
                    }
                    if currentPose != nil && lastPose != currentPose {
                        let start: Int
                        if frame == 1 {
                            start = 0
                        } else {
                            start = frame
                        }
                        poseSegments.append(PoseSegment(poseType: currentPose!, start: start, end: frame))
                    }
                    if currentPoseSegment != nil {
                        currentPoseSegment!.end = frame
                    }
                    lastWrist = currentWrist
                    lastPose = currentPose
                } else {
                    lastWrist = currentWrist
                    lastPose = nil
                }
            } else {
                lastWrist = nil
                lastPose = nil
            }
        }
        return poseSegments
    }
    
    private func getWristLocation(joints: [VNHumanBodyPoseObservation.JointName : VNRecognizedPoint]) -> (CGFloat?, CGFloat?)? {
        let x = getAverage(first: joints[.leftWrist]?.location.x, second: joints[.rightWrist]?.location.x)
        let y = getAverage(first: joints[.leftWrist]?.location.y, second: joints[.rightWrist]?.location.y)
        if x != nil && y != nil {
            return (x, y)
        }
        return nil
    }
    
    private func getAverage(first: CGFloat?, second: CGFloat?) -> CGFloat? {
        if first == nil && second == nil {
            return nil
        }
        let firstValue = first ?? second!
        let secondValue = second ?? first!
        return (firstValue + secondValue) / 2
    }
}

class AnalyzedResult {
    let scaled: CGFloat
    let detectedResult: DetectedResult
    let keyFrames: [[Int]]
    
    internal init(scaled: CGFloat, detectedResult: DetectedResult, keyFrames: [[Int]]) {
        self.scaled = scaled
        self.detectedResult = detectedResult
        self.keyFrames = keyFrames
    }
}

private class AnalyzedContext {
    let locationPerPixel: (CGFloat, CGFloat)
    let scaled: CGFloat
    let detectedResult: DetectedResult
    
    internal init(locationPerPixel: (CGFloat, CGFloat), scaled: CGFloat, detectedResult: DetectedResult) {
        self.locationPerPixel = locationPerPixel
        self.scaled = scaled
        self.detectedResult = detectedResult
    }
}

private enum PoseType {
    case moveLess
    case leftUp
    case rightUp
    case leftDown
    case rightDown
}

private class PoseSegment: CustomStringConvertible {
    let poseType: PoseType
    let start: Int
    var end: Int
    
    internal init(poseType: PoseType, start: Int, end: Int) {
        self.poseType = poseType
        self.start = start
        self.end = end
    }
    
    var description: String {
        return "{poseType=\(poseType), start=\(start), end=\(end)}"
    }
}
