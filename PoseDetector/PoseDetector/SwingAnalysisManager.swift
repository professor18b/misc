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
        let aspectRatio = detectedResult.size.height / detectedResult.size.width
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
        return AnalyzedContext(aspectRatio: aspectRatio, locationPerPixel: locationPerPixel, scaled: scaled, detectedResult: detectedResult)
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
        var poseSegments = analyzePreparing(context: context)
        return poseSegments
    }
    
    private func analyzePreparing(context: AnalyzedContext) ->  [PoseSegment] {
        var result = [PoseSegment]()
        var lowestWristLocation: CGPoint?
        var lastWristLocation: CGPoint?
        var poseSegment: PoseSegment?
        let thresholdX = 0.00096 * context.scaled
        let thresholdY = thresholdX * context.aspectRatio
        let thresholdFrame = Int(context.detectedResult.frameRate * 0.15)
        for index in (0 ... context.detectedResult.joints.count-1).reversed() {
            let joints = context.detectedResult.joints[index]
            //print("frame: \(index)")
            if let currentWristLocation = getValidLowestWristLocation(context: context, joints: joints) {
                if let currentRoot = joints[.root] {
                    if currentWristLocation.y < currentRoot.location.y {
                        var lastLocation = lowestWristLocation
                        if lastLocation == nil {
                            lastLocation = lastWristLocation
                        }
                        //print("currentWristLocation: \(currentWristLocation), lastLocation: \(lastLocation)")
                        if let lastLocation = lastLocation {
                            let distanceInLocationX = abs(lastLocation.x - currentWristLocation.x)
                            let distanceInLocationY = abs(lastLocation.y - currentWristLocation.y)
                            print("dx: \(distanceInLocationX), thresholdX: \(thresholdX), dy: \(distanceInLocationY), thresholdY: \(thresholdY)")
                            if distanceInLocationX < thresholdX && distanceInLocationY < thresholdY {
                                // preparing
                                if poseSegment == nil {
                                    poseSegment = PoseSegment(poseType: .preparing, start: index, end: index + 1)
                                    assert(lowestWristLocation == nil)
                                    if currentWristLocation.y <= lastWristLocation!.y {
                                        lowestWristLocation = currentWristLocation
                                    } else {
                                        lowestWristLocation = lastWristLocation
                                    }
                                    poseSegment?.lowestFrameIndex = index
                                    //print("create")
                                } else {
                                    poseSegment!.start = index
                                    assert(lowestWristLocation != nil)
                                    if currentWristLocation.y < lowestWristLocation!.y {
                                        lowestWristLocation = currentWristLocation
                                        poseSegment?.lowestFrameIndex = index
                                    }
                                    if index == 0 {
                                        result.append(poseSegment!)
                                        //print("add")
                                    }
                                    //print("append")
                                }
                            } else {
                                //print("failed")
                                if let poseSegment = poseSegment{
                                    //print("keep in: \(poseSegment.end - poseSegment.start), thresholdFrame: \(thresholdFrame)")
                                    if poseSegment.end - poseSegment.start >= thresholdFrame {
                                        result.append(poseSegment)
                                        //print("add")
                                    }
                                }
                                poseSegment = nil
                                lowestWristLocation = nil
                            }
                        }
                    }
                }
                lastWristLocation = currentWristLocation
            } else {
                lastWristLocation = nil
                lowestWristLocation = nil
            }
        }
        return result
    }
    
    private func getValidLowestWristLocation(context: AnalyzedContext, joints: [VNHumanBodyPoseObservation.JointName : VNRecognizedPoint]) -> CGPoint? {
        var leftWrist = joints[.leftWrist]
        var rightWrist = joints[.rightWrist]
        if leftWrist == nil && rightWrist == nil {
            return nil
        }
        if leftWrist == nil {
            leftWrist = rightWrist
        }
        if rightWrist == nil {
            rightWrist = leftWrist
        }
        
        guard let left = leftWrist else {
            fatalError()
        }
        guard let right = rightWrist else {
            fatalError()
        }
        
        let distanceThreshold = 100 * context.scaled
        let d = distanceInPixel(size: context.detectedResult.size, from: left, to: right)
        print("wrist distance: \(d), threshold: \(distanceThreshold)")
        if d < distanceThreshold {
//            let x = getAverage(first: left.location.x, second: right.location.x)
//            let y = getAverage(first: left.location.y, second: right.location.y)
//            return CGPoint(x: x!, y: y!)
            if left.location.y < right.location.y {
                return left.location
            } else {
                return right.location
            }
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
    
    private func distanceInPixel(size: CGSize, from: VNRecognizedPoint, to: VNRecognizedPoint) -> CGFloat {
        let px = (from.location.x - to.location.x) * size.width
        let py = (from.location.y - to.location.y) * size.height
        return CGFloat(sqrt(px * px + py * py))
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
    let aspectRatio: CGFloat
    let locationPerPixel: (CGFloat, CGFloat)
    let scaled: CGFloat
    let detectedResult: DetectedResult
    
    internal init(aspectRatio: CGFloat, locationPerPixel: (CGFloat, CGFloat), scaled: CGFloat, detectedResult: DetectedResult) {
        self.aspectRatio = aspectRatio
        self.locationPerPixel = locationPerPixel
        self.scaled = scaled
        self.detectedResult = detectedResult
    }
}

private enum PoseType {
    case preparing
    case leftUp
    case rightUp
    case leftDown
    case rightDown
}

private class PoseSegment: CustomStringConvertible {
    let poseType: PoseType
    var start: Int
    var end: Int
    // only has value when postType is preparing
    var lowestFrameIndex = -1
    
    internal init(poseType: PoseType, start: Int, end: Int) {
        self.poseType = poseType
        self.start = start
        self.end = end
    }
    
    var description: String {
        return "{poseType=\(poseType), start=\(start), end=\(end), lowestFrameIndex=\(lowestFrameIndex)}"
    }
}
