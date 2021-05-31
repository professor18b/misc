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
        let poseSegments: [PoseSegment]
        if context.scaled > 0 {
            poseSegments = analyzePoses(context: context)
        } else {
            poseSegments = [PoseSegment]()
        }
        return AnalyzedResult(scaled: context.scaled, detectedResult: detectedResult, poseSegments: poseSegments)
    }
    
    private func createAnalyzeContext(detectedResult: DetectedResult) -> AnalyzedContext {
        let aspectRatio = detectedResult.size.height / detectedResult.size.width
        let locationPerPixel = (1 / detectedResult.size.width, 1 / detectedResult.size.height)
        let verticalDistance = getVerticalDistance(detectedResult: detectedResult)
        let horizontalDistance = verticalDistance * (detectedResult.size.width / detectedResult.size.height)
        print("verticalDistance: \(verticalDistance), horizontalDistance:\(horizontalDistance)")
        let scaled: CGFloat
        if verticalDistance > 0 {
            // we consider 0.41 is a standard vertical distance to draw skeleton line
            scaled = verticalDistance / 0.41
        } else {
            scaled = 0
        }
        print("detectedSize: \(detectedResult.size), scaled: \(scaled)")
        return AnalyzedContext(aspectRatio: aspectRatio, locationPerPixel: locationPerPixel, scaled: scaled, detectedResult: detectedResult)
    }
    
    private func getVerticalDistance(detectedResult: DetectedResult) -> CGFloat {
        var totalMaxEyeInY: CGFloat = 0
        var validFrames: CGFloat = 0
        var totalMinAnkleInY: CGFloat = 0
        for joints in detectedResult.joints {
            let leftEyeY = joints[VNHumanBodyPoseObservation.JointName.leftEye.keyName]?.location.y ?? 0
            let rightEyeY = joints[VNHumanBodyPoseObservation.JointName.rightEye.keyName]?.location.y ?? 0
            let maxEyeY = fmax(leftEyeY, rightEyeY)
            
            let leftAnkleY = joints[VNHumanBodyPoseObservation.JointName.leftAnkle.keyName]?.location.y ?? 1
            let rightAnkleY = joints[VNHumanBodyPoseObservation.JointName.rightAnkle.keyName]?.location.y ?? 1
            let minAnKleY = fmin(leftAnkleY, rightAnkleY)
            
            if maxEyeY > 0 && minAnKleY < 1 {
                totalMaxEyeInY += maxEyeY
                totalMinAnkleInY += minAnKleY
                validFrames += 1
            }
        }
        
        if validFrames > 0 {
            let maxEyeInY = totalMaxEyeInY / validFrames
            let minAnkleInY = totalMinAnkleInY / validFrames
    //        print("maxEyeInY: \(maxEyeInY), maxEyeInYInPixel: \(maxEyeInY * detectedResult.size.height)")
    //        print("minAnkleInY: \(minAnkleInY), minAnkleInYInPixel: \(minAnkleInY * detectedResult.size.height)")
            return maxEyeInY - minAnkleInY
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
        return result.reversed()
    }
    
    private func printEndDebugInfo(_ message: Any) {
//        print(message)
    }
    
    private func printHitDebugInfo(_ message: Any) {
//        print(message)
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
        let maxEndFrameCount = Int(context.detectedResult.frameRate * 0.6)
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
                        if currentWristLocation.y - lastLocation.y < 0 && isHighestLocationInFuture(context: context, index: index, toCompared: currentWristLocation) {
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
                                printEndDebugInfo("end create, start: \(poseSegment!.start), end: \(poseSegment!.end)")
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
                                    poseSegment!.endHighestIndex = index
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
                } else {
                    printEndDebugInfo("end append failed: minFrameCount: \(minFrameCount), maxFrameCount: \(maxFrameCount)")
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
        let maxFrameCount = Int(context.detectedResult.frameRate * 1.2)
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
                } else {
                    printHitDebugInfo("hit append failed, frameCount: \(frameCount), min: \(minFrameCount), max: \(maxFrameCount)")
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
        var lastWristHorizontalDirection: Int?
        var poseSegment: PoseSegment?
        let maxStartFrameCount = Int(context.detectedResult.frameRate * 0.5)
        let minFrameCount = Int(context.detectedResult.frameRate * 0.3)
        let maxFrameCount = Int(context.detectedResult.frameRate * 2.5)
        let maxDistanceYForOverShoulder = 0.003 * context.scaled
        let maxDistanceYForBelowRoot = 0.106 * context.scaled
        for preparingSegment in preparingSegments {
            let minY = preparingSegment.preparingLowestLocation!.y - 0.015
            lastWristLocation = nil
            lastWristHorizontalDirection = nil
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
                        } else if currentWristLocation.y - lastLocation.y < 0 && isHighestLocationInFuture(context: context, index: index, toCompared: currentWristLocation) {
                            let overShoulder = currentWristLocation.y > getLowestShoulderY(context: context, joints: context.detectedResult.joints[index])
                            let belowRoot = currentWristLocation.y < getRootY(context: context, joints: context.detectedResult.joints[index])
                            if !overShoulder && !belowRoot {
                                break
                            }
                            
                            if belowRoot && index > preparingSegment.end + maxStartFrameCount {
                                printUpDebugInfo("up start too slow then break: maxStartFrameCount: \(maxStartFrameCount)")
                                break
                            }
                            
                            let distanceInLocationY: CGFloat
                            let maxDistanceInY: CGFloat
                            if belowRoot {
                                distanceInLocationY = abs(lastLocation.y - currentWristLocation.y)
                                maxDistanceInY = maxDistanceYForBelowRoot
                            } else if poseSegment != nil {
                                distanceInLocationY = abs(poseSegment!.upHighestLocation!.y - currentWristLocation.y)
                                maxDistanceInY = maxDistanceYForOverShoulder
                            } else {
                                printUpDebugInfo("up move down then break")
                                break
                            }
                                
                            if distanceInLocationY > maxDistanceInY {
                                printUpDebugInfo("up move down then break, belowRoot: \(belowRoot), overShoulder: \(overShoulder), distanceInLocationY: \(distanceInLocationY), maxDistanceInY:\(maxDistanceInY)")
                                break
                            }
                            
                            if overShoulder {
                                if lastWristHorizontalDirection == nil {
                                    break
                                }
                                let currentDirection = getHorizontalDirection(lastLocation: lastLocation, currentLocation: currentWristLocation)
                                if isPositiveDirection(left: currentDirection, right: lastWristHorizontalDirection!) {
                                    printUpDebugInfo("up over shoulder direction changed then break: lastDirection: \(lastWristHorizontalDirection!), currentDirection: \(currentDirection)")
                                    break
                                }
                            }
                            poseSegment?.end = index
                        } else {
                            if poseSegment == nil {
                                poseSegment = PoseSegment(poseType: PoseType.up, standType: preparingSegment.standType, start: preparingSegment.end + 1, end: index)
                                printUpDebugInfo("up create, start: \(poseSegment!.start), end: \(poseSegment!.end)")
                            } else {
                                poseSegment?.end = index
                            }
                        }
                        if poseSegment != nil {
                            if poseSegment!.upHighestLocation == nil || currentWristLocation.y > poseSegment!.upHighestLocation!.y {
                                poseSegment!.upHighestLocation = currentWristLocation
                                poseSegment!.upHighestIndex = index
                            }
                        }
                    }
                    if lastWristLocation != nil {
                        lastWristHorizontalDirection = getHorizontalDirection(lastLocation: lastWristLocation!, currentLocation: currentWristLocation)
                    }
                    lastWristLocation = currentWristLocation
                }
            }
            if poseSegment != nil {
                let frameCount = poseSegment!.end - poseSegment!.start
                if frameCount > minFrameCount && frameCount < maxFrameCount
                    && poseSegment!.upHighestLocation!.y > getLowestShoulderY(context: context, joints: context.detectedResult.joints[poseSegment!.end]) {
                    preparingSegment.next = poseSegment
                    result.append(preparingSegment)
                    printUpDebugInfo("up append")
                } else {
                    printUpDebugInfo("up append failed, frameCount: \(frameCount), min: \(minFrameCount), max: \(maxFrameCount)")
                }
                poseSegment = nil
            }
        }
        return result
    }
    
    private func isHighestLocationInFuture(context: AnalyzedContext, index: Int, toCompared: CGPoint) -> Bool {
        return isHighestOrLowestLocationInFuture(context: context, index: index, toCompared: toCompared)
    }
    
    private func isLowestLocationInFuture(context: AnalyzedContext, index: Int, toCompared: CGPoint) -> Bool {
        return isHighestOrLowestLocationInFuture(context: context, index: index, toCompared: toCompared, checkLowest: true)
    }
    
    private func isHighestOrLowestLocationInFuture(context: AnalyzedContext, index: Int, toCompared: CGPoint, checkLowest: Bool = false) -> Bool {
        var result = true
        if index < context.detectedResult.joints.count - 1 {
            // check next frame to avoid unstability of detection
            let nextFrameCount = Int(context.detectedResult.frameRate * 0.11)
            let start = index + 1
            var end = start + nextFrameCount
            if end >= context.detectedResult.joints.count - 1 {
                end = context.detectedResult.joints.count - 1
            }
            for i in start ... end {
                if let wristLocation = getValidLowestWristLocation(context: context, joints: context.detectedResult.joints[i]) {
                    if checkLowest {
                        if wristLocation.y < toCompared.y {
                            result = false
                            break
                        }
                    } else {
                        if wristLocation.y > toCompared.y {
                            result = false
                            break
                        }
                    }
                    
                }
            }
        }
        return result
    }
    
    private func isPositiveDirection(left: Int, right: Int) -> Bool {
        return (left == 1 && right == -1) || (left == -1 && right == 1)
    }
    
    private func getHorizontalDirection(lastLocation: CGPoint, currentLocation: CGPoint) -> Int {
        if currentLocation.x > lastLocation.x {
            return 1
        } else if currentLocation.x < lastLocation.x {
            return  -1
        } else {
            return 0
        }
    }
    private func getRootY(context: AnalyzedContext, joints: [String: DetectedPoint]) -> CGFloat {
        let root = joints[VNHumanBodyPoseObservation.JointName.root.keyName]
        if root == nil {
            return 0
        }
        return root!.location.y
    }
    
    private func analyzePreparing(context: AnalyzedContext) ->  [PoseSegment] {
        var result = [PoseSegment]()
        var lastWristLocation: CGPoint?
        var poseSegment: PoseSegment?
        let maxDistanceInX = 0.0018 * context.scaled
        let maxDistanceInY = maxDistanceInX * context.aspectRatio
        let minFrameCount = Int(context.detectedResult.frameRate * 0.15)
        let maxFrameCount = Int(context.detectedResult.frameRate * 1)
        let minFrameIntervel = Int(context.detectedResult.frameRate * 1)
        for index in (0 ... context.detectedResult.joints.count - 1).reversed() {
            let joints = context.detectedResult.joints[index]
            printPreparingDebugInfo("frame: \(index)")
            if let currentWristLocation = getValidLowestWristLocation(context: context, joints: joints) {
                if let currentRoot = joints[VNHumanBodyPoseObservation.JointName.root.keyName] {
                    // some one wrist higher than root when preparing
                    if currentWristLocation.y < currentRoot.location.y + maxDistanceInY {
                        var lastLocation = poseSegment?.preparingLowestLocation
                        if lastLocation == nil {
                            lastLocation = lastWristLocation
                        }
//                        printPreparingDebugInfo("currentWristLocation: \(currentWristLocation), lastLocation: \(String(describing: lastLocation))")
                        if let lastLocation = lastLocation {
                            var isInPosition = false
                            let distanceInLocationX = abs(lastLocation.x - currentWristLocation.x)
                            let distanceInLocationY = abs(lastLocation.y - currentWristLocation.y)
                            if distanceInLocationX < maxDistanceInX && distanceInLocationY < maxDistanceInY {
                                var overIntervel = result.isEmpty
                                if !result.isEmpty {
                                    let lastPoseSegment = result[result.count - 1]
                                    if lastPoseSegment.start - index > minFrameIntervel {
                                        overIntervel = true
                                    } else {
                                        printPreparingDebugInfo("too close to preparing, lastPoseSegment: \(lastPoseSegment.start)")
                                    }
                                }
                                
                                isInPosition = overIntervel
                            } else {
                                printPreparingDebugInfo("currentWristLocation: \(currentWristLocation), lastLocation: \(lastLocation)")
                                printPreparingDebugInfo("dx: \(distanceInLocationX), thresholdX: \(maxDistanceInX), dy: \(distanceInLocationY), thresholdY: \(maxDistanceInY)")
                            }
                            
                            if isInPosition {
                                if poseSegment == nil {
                                    let standType = getStandType(context: context, joints: joints)
                                    let start = index
                                    let end: Int
                                    if index < context.detectedResult.frames - 1 {
                                        end = index + 1
                                    } else {
                                        end = index
                                    }
                                    poseSegment = PoseSegment(poseType: .preparing, standType: standType, start: start, end: end)
                                    printPreparingDebugInfo("preparing create")
                                }
                            }
                            
                            if let segment = poseSegment {
                                if segment.preparingLowestLocation == nil || segment.preparingLowestLocation!.y > currentWristLocation.y {
                                    segment.preparingLowestLocation = currentWristLocation
                                    segment.preparingLowestIndex = index
                                }
                                segment.start = index
                                
                                if index == 0 || (!isInPosition && segment.end - segment.start > minFrameCount) || segment.end - segment.start > maxFrameCount {
                                    result.append(segment)
                                    printPreparingDebugInfo("preparing append")
                                    poseSegment = nil
                                }
                                
                                if !isInPosition && poseSegment != nil {
                                    poseSegment = nil
                                    printPreparingDebugInfo("preparing failed")
                                }
                            }
                        }
                    } else {
                        if let segment = poseSegment {
                            if segment.end - segment.start > minFrameCount {
                                result.append(segment)
                                printPreparingDebugInfo("preparing append")
                            } else {
                                printPreparingDebugInfo("preparing failed, segment: \(segment), minFrameCount: \(minFrameCount)")
                            }
                            poseSegment = nil
                        }
                    }
                }
                lastWristLocation = currentWristLocation
            } else {
                lastWristLocation = nil
                poseSegment = nil
            }
        }
        return result
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
//            print("wrist distance: \(d), threshold: \(distanceThreshold)")
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
    let poseSegments: [PoseSegment]
    
    internal init(scaled: CGFloat, detectedResult: DetectedResult, poseSegments: [PoseSegment]) {
        self.scaled = scaled
        self.detectedResult = detectedResult
        self.poseSegments = poseSegments
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
    // only has value when postType is preparing
    var preparingLowestIndex: Int?
    // only has value when postType is up
    var upHighestLocation: CGPoint?
    // only has value when postType is up
    var upHighestIndex: Int?
    // only has value when postType is hit
    var hitLowestLocation: CGPoint?
    // only has value when postType is hit
    var hitHighestLocation: CGPoint?
    // only has value when postType is end
    var endHighestLocation: CGPoint?
    // only has value when postType is end
    var endHighestIndex: Int?
    var next: PoseSegment?
    
    internal init(poseType: PoseType, standType: StandType, start: Int, end: Int) {
        self.poseType = poseType
        self.standType = standType
        self.start = start
        self.end = end
    }
    
    var description: String {
        var desc = "{poseType=\(poseType), standType=\(standType), start=\(start), end=\(end)"
        if preparingLowestIndex != nil {
            desc.append(", preparingLowestIndex=\(preparingLowestIndex!)")
        }
        if upHighestIndex != nil {
            desc.append(", upHighestIndex=\(upHighestIndex!)")
        }
        if endHighestIndex != nil {
            desc.append(", endHighestIndex=\(endHighestIndex!)")
        }
        if next != nil {
            desc.append(", next=\(next!)")
        }
        desc.append("}")
        return desc
    }
    
    func getEnd() -> PoseSegment? {
        var nextSegment = next
        while nextSegment != nil {
            if nextSegment!.poseType == .end {
                return nextSegment
            }
            nextSegment = nextSegment!.next
        }
        return nil
    }
}
