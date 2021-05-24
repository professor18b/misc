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
            // we consider 0.53 is a standard vertical distance to draw skeleton line
            scaled = verticalDistance / 0.53
        } else {
            scaled = 0
        }
        print("detectedSize: \(detectedResult.size), scaled: \(scaled)")
        return AnalyzedContext(aspectRatio: aspectRatio, locationPerPixel: locationPerPixel, scaled: scaled, detectedResult: detectedResult)
    }
    
    private func getStandType(context: AnalyzedContext, joints: [String : DetectedPoint]) -> StandType {
        var faceOn = 0
        var downTheLine = 0
        // eye
        let leftEye = joints[VNHumanBodyPoseObservation.JointName.leftEye.keyName]
        let rightEye = joints[VNHumanBodyPoseObservation.JointName.rightEye.keyName]
        if leftEye != nil || rightEye != nil {
            if leftEye == nil || rightEye == nil {
                downTheLine += 1
                printUpDebugInfo("downTheLine += 1")
            } else {
                assert(leftEye != nil && rightEye != nil)
                let eyeDistance = abs(leftEye!.location.x - rightEye!.location.x)
                printUpDebugInfo("eyeDistance: \(eyeDistance)")
                if eyeDistance < 0.03 * context.scaled {
                    downTheLine += 1
                } else {
                    faceOn += 1
                }
            }
        }
        // shoulder
        let leftShoulder = joints[VNHumanBodyPoseObservation.JointName.leftShoulder.keyName]
        let rightShoulder = joints[VNHumanBodyPoseObservation.JointName.rightShoulder.keyName]
        let root = joints[VNHumanBodyPoseObservation.JointName.root.keyName]
        let neck = joints[VNHumanBodyPoseObservation.JointName.neck.keyName]
        if leftShoulder != nil && rightShoulder != nil && root != nil && neck != nil {
            let shoulderDistance = distanceInPixel(size: context.detectedResult.size, from: leftShoulder!, to: rightShoulder!)
            let bodyDistance = distanceInPixel(size: context.detectedResult.size, from: root!, to: neck!)
            let rate = bodyDistance / shoulderDistance
            printUpDebugInfo("body shoulderDistance: \(shoulderDistance), bodyDistance: \(bodyDistance), rate: \(rate)")
            if rate > 3 {
                downTheLine += 1
            } else {
                faceOn += 1
            }
        }
        if downTheLine > faceOn {
            return StandType.downTheLine
        }
        return StandType.faceOn
    }
    
    private func getVerticalDistance(detectedResult: DetectedResult) -> CGFloat {
        var lastMaxEyeInY: CGFloat = 0
        var lastMinAnkleInY: CGFloat = 1
        for joints in detectedResult.joints {
            let leftEyeY = joints[VNHumanBodyPoseObservation.JointName.leftEye.keyName]?.location.y ?? 0
            let rightEyeY = joints[VNHumanBodyPoseObservation.JointName.rightEye.keyName]?.location.y ?? 0
            let max = fmax(leftEyeY, rightEyeY)
            if max > lastMaxEyeInY {
                lastMaxEyeInY = max
            }
//            print("leftEye: \(leftEyeY)), rightEye: \(rightEyeY)")
//            print("leftEye: \(leftEyeY*detectedResult.size.height), rightEye: \(rightEyeY*detectedResult.size.height)")
            
            let leftAnkleY = joints[VNHumanBodyPoseObservation.JointName.leftAnkle.keyName]?.location.y ?? 1
            let rightAnkleY = joints[VNHumanBodyPoseObservation.JointName.rightAnkle.keyName]?.location.y ?? 1
            let min = fmin(leftAnkleY, rightAnkleY)
            if min < lastMinAnkleInY {
                lastMinAnkleInY = min
            }
//            print("lefAnkle: \(leftAnkleY)), rightAnkle: \(rightAnkleY)")
//            print("lefAnkle: \(leftAnkleY*detectedResult.size.height), rightAnkle: \(rightAnkleY*detectedResult.size.height)")
        }
//        print("maxEyeInY: \(lastMaxEyeInY), maxEyeInYInPixel: \(lastMaxEyeInY * detectedResult.size.height)")
//        print("minAnkleInY: \(lastMinAnkleInY), minAnkleInY: \(lastMinAnkleInY * detectedResult.size.height)")
        if( lastMaxEyeInY < 1 && lastMinAnkleInY > 0) {
            return lastMaxEyeInY - lastMinAnkleInY
        }
        return 0
    }
    
    private func analyzePoses(context: AnalyzedContext) -> [PoseSegment] {
        var result = analyzePreparing(context: context)
        print("preparing result:")
        for segment in result {
            print(segment)
        }
        result = analyzeUp(context: context, preparingSegments: result)
        print("up result:")
        for segment in result {
            print(segment)
        }
        result = analyzeHit(context: context, upSegments: result)
        print("hit result:")
        for segment in result {
            print(segment)
        }
        result = analyzeEnd(context: context, hitSegments: result)
        print("end result:")
        for segment in result {
            print(segment)
        }
        return result
    }
    private func printEndDebugInfo(_ message: Any) {
//        print(message)
    }
    
    private func printHitDebugInfo(_ message: Any) {
        print(message)
    }
    
    private func printUpDebugInfo(_ message: Any) {
//        print(message)
    }
    
    private func printPreparingDebugInfo(_ message: Any) {
//        print(message)
    }
    
    private func analyzeEnd(context: AnalyzedContext, hitSegments: [PoseSegment]) ->  [PoseSegment] {
        var result = [PoseSegment]()
        var lastWristLocation: CGPoint?
        var poseSegment: PoseSegment?
        let maxEndFrameCount = Int(context.detectedResult.frameRate * 1)
        let minFrameCount = Int(context.detectedResult.frameRate * 0.15)
        let maxFrameCount = Int(context.detectedResult.frameRate * 1.5)
        let maxDistanceInY = 0.07 * context.scaled
        for preparingSegment in hitSegments {
            let hitSegment = preparingSegment.next!.next!
            printEndDebugInfo("hitSegment: \(hitSegment)")
            var endFrameCount = -1
            lastWristLocation = nil
            for index in hitSegment.end ... context.detectedResult.joints.count - 1 {
                let joints = context.detectedResult.joints[index]
                printEndDebugInfo("frame: \(index)")
                if let currentWristLocation = getValidLowestWristLocation(context: context, joints: joints) {
                    if let lastLocation = lastWristLocation {
                        if currentWristLocation.y - lastLocation.y < 0 {
                            if poseSegment == nil {
                                break
                            }
                            poseSegment!.end = index
//                            print("currentWristLocation.y: \(currentWristLocation.y), a: \(poseSegment!.endHighestLocation!.y - maxDistanceInY), b: \(getLowestEarY(context: context, joints: joints))")
                            if currentWristLocation.y < poseSegment!.endHighestLocation!.y - maxDistanceInY
                                || currentWristLocation.y < getLowestEarY(context: context, joints: joints) {
                                printEndDebugInfo("end move down then break")
                                break
                            }
                            endFrameCount += 1
                            if endFrameCount >= maxEndFrameCount {
                                printEndDebugInfo("end too long then break: endFrameCount: \(maxEndFrameCount)")
                                break
                            }
                            printEndDebugInfo("endFrameCount: \(endFrameCount), maxEndFrameCount: \(maxEndFrameCount)")
                        } else {
                            if poseSegment == nil {
                                poseSegment = PoseSegment(poseType: PoseType.end, standType: hitSegment.standType, start: hitSegment.end + 1, end: index)
                                printEndDebugInfo("create, start: \(poseSegment!.start), end: \(poseSegment!.end)")
                            } else {
                                if endFrameCount > 0 {
                                    endFrameCount += 1
                                    if endFrameCount >= maxEndFrameCount {
                                        printEndDebugInfo("end too long then break: endFrameCount: \(maxEndFrameCount)")
                                        break
                                    }
                                    printEndDebugInfo("endFrameCount: \(endFrameCount), maxEndFrameCount: \(maxEndFrameCount)")
                                }
                                poseSegment?.end = index
                            }
                            if poseSegment != nil {
                                if poseSegment!.endHighestLocation == nil || currentWristLocation.y > poseSegment!.endHighestLocation!.y{
                                    poseSegment!.endHighestLocation = currentWristLocation
                                }
                            }
                        }
                    }
                    lastWristLocation = currentWristLocation
                }
            }
            
            if poseSegment != nil {
                let frameCount = poseSegment!.end - poseSegment!.start
                if frameCount > minFrameCount && frameCount < maxFrameCount
                    && poseSegment!.endHighestLocation!.y > getLowestShoulderY(context: context, joints: context.detectedResult.joints[poseSegment!.end]) {
                    hitSegment.next = poseSegment
                    result.append(preparingSegment)
                }
                poseSegment = nil
            }
        }
        return result
    }
    
    private func getLowestEarY(context: AnalyzedContext, joints: [String: DetectedPoint]) -> CGFloat {
        let leftEar = joints[VNHumanBodyPoseObservation.JointName.leftEar.keyName]
        let rightEar = joints[VNHumanBodyPoseObservation.JointName.rightEar.keyName]
        if leftEar == nil && rightEar == nil {
            return 0
        }
        if leftEar == nil {
            return rightEar!.location.y
        }
        if rightEar == nil {
            return leftEar!.location.y
        }
        if leftEar!.location.y < rightEar!.location.y {
            return leftEar!.location.y
        }
        return rightEar!.location.y
    }
    
    private func analyzeHit(context: AnalyzedContext, upSegments: [PoseSegment]) ->  [PoseSegment] {
        var result = [PoseSegment]()
        var lastWristLocation: CGPoint?
        var poseSegment: PoseSegment?
        let minFrameCount = Int(context.detectedResult.frameRate * 0.15)
        let maxFrameCount = Int(context.detectedResult.frameRate * 0.8)
        for preparingSegment in upSegments {
            let upSegment = preparingSegment.next!
            printHitDebugInfo("upSegment: \(upSegment)")
            lastWristLocation = nil
            for index in upSegment.end ... context.detectedResult.joints.count - 1 {
                let joints = context.detectedResult.joints[index]
                printHitDebugInfo("frame: \(index)")
                if let currentWristLocation = getValidLowestWristLocation(context: context, joints: joints) {
                    if let lastLocation = lastWristLocation {
                        let moveUpThreshold = getHitMoveUpThreshold(context: context, currentWristY: currentWristLocation.y, joints: joints)
                        if currentWristLocation.y - lastLocation.y > moveUpThreshold {
                            printHitDebugInfo("hit move up then break")
                            poseSegment?.end = index
                            break
                        } else {
                            if poseSegment == nil {
                                poseSegment = PoseSegment(poseType: PoseType.hit, standType: upSegment.standType, start: upSegment.end + 1, end: index)
                                printHitDebugInfo("create, start: \(poseSegment!.start), end: \(poseSegment!.end)")
                            } else {
                                poseSegment?.end = index
                            }
                        }
                        if poseSegment != nil {
                            if poseSegment!.hitHighestLocation == nil || currentWristLocation.y > poseSegment!.hitHighestLocation!.y{
                                poseSegment!.hitHighestLocation = currentWristLocation
                            }
                            if poseSegment!.hitLowestLocation == nil || currentWristLocation.y < poseSegment!.hitLowestLocation!.y{
                                poseSegment!.hitLowestLocation = currentWristLocation
                            }
                        }
                    }
                    lastWristLocation = currentWristLocation
                }
            }
            
            if poseSegment != nil {
                let frameCount = poseSegment!.end - poseSegment!.start
                if frameCount > minFrameCount && frameCount < maxFrameCount
                    && poseSegment!.hitHighestLocation!.y > getLowestShoulderY(context: context, joints: context.detectedResult.joints[poseSegment!.end]) {
                    upSegment.next = poseSegment
                    result.append(preparingSegment)
                }
                poseSegment = nil
            }
        }
        return result
    }
    
    private func getHitMoveUpThreshold(context: AnalyzedContext, currentWristY: CGFloat, joints: [String: DetectedPoint]) -> CGFloat {
        let lowestShoulderY = getLowestShoulderY(context: context, joints: joints)
        if lowestShoulderY > 0 && currentWristY > lowestShoulderY {
            return 0.008 * context.scaled
        }
        return 0
    }
    
    private func getLowestShoulderY(context: AnalyzedContext, joints: [String: DetectedPoint]) -> CGFloat {
        let lefShoulder = joints[VNHumanBodyPoseObservation.JointName.leftShoulder.keyName]
        let rightShoulder = joints[VNHumanBodyPoseObservation.JointName.rightShoulder.keyName]
        if lefShoulder == nil && rightShoulder == nil {
            return 0
        }
        if lefShoulder == nil {
            return rightShoulder!.location.y
        }
        if rightShoulder == nil {
            return lefShoulder!.location.y
        }
        if lefShoulder!.location.y < rightShoulder!.location.y {
            return lefShoulder!.location.y
        }
        return rightShoulder!.location.y
    }
    
    private func analyzeUp(context: AnalyzedContext, preparingSegments: [PoseSegment]) ->  [PoseSegment] {
        var result = [PoseSegment]()
        var lastWristLocation: CGPoint?
        var poseSegment: PoseSegment?
        let maxStartFrameCount = Int(context.detectedResult.frameRate * 0.3)
        let minFrameCount = Int(context.detectedResult.frameRate * 0.3)
        let maxFrameCount = Int(context.detectedResult.frameRate * 1.8)
        for preparingSegment in preparingSegments {
            let maxDistanceInY: CGFloat
            if preparingSegment.standType == .faceOn {
                maxDistanceInY = 0.003 * context.scaled
            } else {
                maxDistanceInY = 0.106 * context.scaled
            }
            var startFrameCount = -1
            let minY = preparingSegment.preparingLowestLocation!.y - 0.015
            lastWristLocation = nil
            printUpDebugInfo("preparingSegment: \(preparingSegment)")
            for index in preparingSegment.end ... context.detectedResult.joints.count - 1 {
                let joints = context.detectedResult.joints[index]
                printUpDebugInfo("frame: \(index)")
                if let currentWristLocation = getValidLowestWristLocation(context: context, joints: joints) {
                    if let lastLocation = lastWristLocation {
//                        printUpDebugInfo("currentWristLocation: \(currentWristLocation), lastLocation: \(String(describing: lastLocation))")
                        if currentWristLocation.y < minY {
                            printUpDebugInfo("up too low then break: \(preparingSegment.preparingLowestLocation!.y - currentWristLocation.y)")
                            break
                        } else if currentWristLocation.y - lastLocation.y < 0 {
                            let distanceInLocationY = abs(lastLocation.y - currentWristLocation.y)
                            if distanceInLocationY > maxDistanceInY {
                                printUpDebugInfo("up move down then break, distanceInLocationY: \(distanceInLocationY), maxDistanceInY:\(maxDistanceInY)")
                                break
                            }
                            startFrameCount += 1
                            if startFrameCount >= maxStartFrameCount {
                                printUpDebugInfo("up start too slow then break: startFrameCount: \(startFrameCount)")
                                break
                            }
                            poseSegment?.end = index
                        } else {
                            if poseSegment == nil {
                                poseSegment = PoseSegment(poseType: PoseType.up, standType: preparingSegment.standType, start: preparingSegment.end + 1, end: index)
                                printUpDebugInfo("create, start: \(poseSegment!.start), end: \(poseSegment!.end)")
                            } else {
                                poseSegment?.end = index
                            }
                        }
                        if poseSegment != nil {
                            if poseSegment!.upHighestLocation == nil || currentWristLocation.y > poseSegment!.upHighestLocation!.y{
                                poseSegment!.upHighestLocation = currentWristLocation
                            }
                        }
                    }
                    lastWristLocation = currentWristLocation
                }
            }
            if poseSegment != nil {
                let frameCount = poseSegment!.end - poseSegment!.start
                if frameCount > minFrameCount && frameCount < maxFrameCount {
                    preparingSegment.next = poseSegment
                    result.append(preparingSegment)
                }
                poseSegment = nil
            }
        }
        return result
    }
    
    private func analyzePreparing(context: AnalyzedContext) ->  [PoseSegment] {
        var result = [PoseSegment]()
        var lowestWristLocation: CGPoint?
        var lastWristLocation: CGPoint?
        var poseSegment: PoseSegment?
        let maxDistanceInX = 0.00096 * context.scaled
        let maxDistanceInY = maxDistanceInX * context.aspectRatio
        let minFrameCount = Int(context.detectedResult.frameRate * 0.15)
        let minFrameIntervel = Int(context.detectedResult.frameRate * 1)
        for index in (0 ... context.detectedResult.joints.count - 1).reversed() {
            let joints = context.detectedResult.joints[index]
            printPreparingDebugInfo("frame: \(index)")
            if let currentWristLocation = getValidLowestWristLocation(context: context, joints: joints) {
                if let currentRoot = joints[VNHumanBodyPoseObservation.JointName.root.keyName] {
                    if currentWristLocation.y < currentRoot.location.y {
                        var lastLocation = lowestWristLocation
                        if lastLocation == nil {
                            lastLocation = lastWristLocation
                        }
//                        printPreparingDebugInfo("currentWristLocation: \(currentWristLocation), lastLocation: \(String(describing: lastLocation))")
                        if let lastLocation = lastLocation {
                            let distanceInLocationX = abs(lastLocation.x - currentWristLocation.x)
                            let distanceInLocationY = abs(lastLocation.y - currentWristLocation.y)
                            printPreparingDebugInfo("dx: \(distanceInLocationX), thresholdX: \(maxDistanceInX), dy: \(distanceInLocationY), thresholdY: \(maxDistanceInY)")
                            if distanceInLocationX < maxDistanceInX && distanceInLocationY < maxDistanceInY {
                                // preparing
                                if poseSegment == nil {
                                    if !result.isEmpty {
                                        let lastPoseSegment = result[result.count - 1]
                                        if lastPoseSegment.start - index < minFrameIntervel {
                                            printPreparingDebugInfo("too close to preparing, lastPoseSegment: \(lastPoseSegment.start)")
                                            continue
                                        }
                                    }
                                    
                                    let standType = getStandType(context: context, joints: joints)
                                    poseSegment = PoseSegment(poseType: .preparing, standType: standType, start: index, end: index + 1)
                                    assert(lowestWristLocation == nil)
                                    if currentWristLocation.y <= lastWristLocation!.y {
                                        lowestWristLocation = currentWristLocation
                                    } else {
                                        lowestWristLocation = lastWristLocation
                                    }
                                    poseSegment?.preparingLowestLocation = lowestWristLocation
                                    printPreparingDebugInfo("create")
                                } else {
                                    poseSegment!.start = index
                                    assert(lowestWristLocation != nil)
                                    if currentWristLocation.y < lowestWristLocation!.y {
                                        lowestWristLocation = currentWristLocation
                                        poseSegment?.preparingLowestLocation = lowestWristLocation
                                    }
                                    if index == 0 {
                                        result.append(poseSegment!)
                                        printPreparingDebugInfo("add")
                                    }
                                    printPreparingDebugInfo("append")
                                }
                            } else {
                                printPreparingDebugInfo("failed")
                                if let poseSegment = poseSegment{
                                    printPreparingDebugInfo("keep in: \(poseSegment.end - poseSegment.start), thresholdFrame: \(minFrameCount)")
                                    if poseSegment.end - poseSegment.start >= minFrameCount {
                                        result.append(poseSegment)
                                        printPreparingDebugInfo("add")
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
    
    private func getValidLowestWristLocation(context: AnalyzedContext, joints: [String: DetectedPoint]) -> CGPoint? {
        var leftWrist = joints[VNHumanBodyPoseObservation.JointName.leftWrist.keyName]
        var rightWrist = joints[VNHumanBodyPoseObservation.JointName.rightWrist.keyName]
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
        
        let distanceThreshold = 110 * context.scaled
        let d = distanceInPixel(size: context.detectedResult.size, from: left, to: right)
        if d < distanceThreshold {
//            let x = getAverage(first: left.location.x, second: right.location.x)
//            let y = getAverage(first: left.location.y, second: right.location.y)
//            return CGPoint(x: x!, y: y!)
            if left.location.y < right.location.y {
                return left.location
            } else {
                return right.location
            }
        } else {
            print("wrist distance: \(d), threshold: \(distanceThreshold)")
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
    
    private func distanceInPixel(size: CGSize, from: DetectedPoint, to: DetectedPoint) -> CGFloat {
        let px = (from.location.x - to.location.x) * size.width
        let py = (from.location.y - to.location.y) * size.height
        return CGFloat(sqrt(px * px + py * py))
    }
}

enum StandType {
    case faceOn
    case downTheLine
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

enum PoseType {
    case preparing
    case up
    case hit
    case end
}

class PoseSegment: CustomStringConvertible {
    let poseType: PoseType
    let standType: StandType
    var start: Int
    var end: Int
    // only has value when postType is preparing
    var preparingLowestLocation: CGPoint?
    // only has value when postType is up
    var upHighestLocation: CGPoint?
    // only has value when postType is hit
    var hitLowestLocation: CGPoint?
    // only has value when postType is hit
    var hitHighestLocation: CGPoint?
    // only has value when postType is end
    var endHighestLocation: CGPoint?
    var next: PoseSegment?
    
    internal init(poseType: PoseType, standType: StandType, start: Int, end: Int) {
        self.poseType = poseType
        self.standType = standType
        self.start = start
        self.end = end
    }
    
    var description: String {
        var desc = "{poseType=\(poseType), standType=\(standType), start=\(start), end=\(end)"
        if preparingLowestLocation != nil {
            desc.append(", preparingLowestLocation=\(preparingLowestLocation!)")
        }
        if upHighestLocation != nil {
            desc.append(", upHighestLocation=\(upHighestLocation!)")
        }
        if next != nil {
            desc.append(", next=\(next!)")
        }
        desc.append("}")
        return desc
    }
}
