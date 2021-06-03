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
        print(message)
    }
    
    private func analyzeEnd(context: AnalyzedContext, hitSegments: [PoseSegment]) ->  [PoseSegment] {
        var result = [PoseSegment]()
        var lastWristLocation: CGPoint?
        var poseSegment: PoseSegment?
        let maxEndFrameCount = Int(context.detectedResult.frameRate * 0.6)
        let minFrameCount = Int(context.detectedResult.frameRate * 0.15)
        let maxFrameCount = Int(context.detectedResult.frameRate * 1.5)
        let maxDistanceInY = 0.07 * context.getDistanceScaled()
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
            return 0.008 * context.getDistanceScaled()
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
        let maxDistanceYForOverShoulder = 0.003 * context.getDistanceScaled()
        let maxDistanceYForBelowRoot = 0.106 * context.getDistanceScaled()
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
        var poseSegment: PoseSegment?
        // left shoulder, right shoulder
        var lastShoulderNeckDistance: (CGPoint?, CGPoint?)?
        var lastWristNeckDistance: (CGPoint?, CGPoint?)?
        
        let maxDistanceInX = 0.0022 * context.getDistanceScaled()
        let maxDistanceInY = maxDistanceInX * context.aspectRatio
        
        let minFrameCount = Int(context.detectedResult.frameRate * 0.15)
        let maxFrameCount = Int(context.detectedResult.frameRate * 1)
        let minFrameIntervel = Int(context.detectedResult.frameRate * 1)
        for index in (0 ... context.detectedResult.joints.count - 1).reversed() {
            let joints = context.detectedResult.joints[index]
            printPreparingDebugInfo("frame: \(index)")
            if let currentWristLocation = getValidLowestWristLocation(context: context, joints: joints) {
                if let neckLocation = joints[VNHumanBodyPoseObservation.JointName.neck.keyName]?.location {
                    if let rootLocation = joints[VNHumanBodyPoseObservation.JointName.root.keyName]?.location {
                        let leftShoulderLocation = joints[VNHumanBodyPoseObservation.JointName.leftShoulder.keyName]?.location
                        let rightShoulderLocation = joints[VNHumanBodyPoseObservation.JointName.rightShoulder.keyName]?.location
                        let currentShoulderNeckDistance = (getDistance(left: leftShoulderLocation, right: neckLocation), getDistance(left: rightShoulderLocation, right: neckLocation))
                        
                        let leftWristLocation = joints[VNHumanBodyPoseObservation.JointName.leftWrist.keyName]?.location
                        let rightWristLocation = joints[VNHumanBodyPoseObservation.JointName.rightWrist.keyName]?.location
                        let currentWristNeckDistance = (getDistance(left: leftWristLocation, right: neckLocation), getDistance(left: rightWristLocation, right: neckLocation))
                        
                        var isPreparing = (lastWristNeckDistance?.0 != nil && lastWristNeckDistance?.1 != nil && lastShoulderNeckDistance?.0 != nil && lastShoulderNeckDistance?.1 != nil) || poseSegment != nil
                        
                        if isPreparing {
                            // check interval
                            if !result.isEmpty {
                                let lastPoseSegment = result[result.count - 1]
                                if lastPoseSegment.start - index < minFrameIntervel {
                                    isPreparing = false
                                    printPreparingDebugInfo("too close to preparing, lastPoseSegment: \(lastPoseSegment.start)")
                                }
                            }
                        }
                        
                        if isPreparing {
                            // someone's wrist higher than root when preparing
                            if currentWristLocation.y > rootLocation.y + maxDistanceInY {
                                isPreparing = false
                                printPreparingDebugInfo("wrist too high, currentWristLocation: \(currentWristLocation), thresholdY: \(rootLocation.y + maxDistanceInY)")
                            } else {
                                // check wrist
                                if let currentLeftWristNeckDistance = currentWristNeckDistance.0 {
                                    if let lastLeftWristDistance = lastWristNeckDistance?.0 {
                                        let distanceInLocationX = abs(lastLeftWristDistance.x - currentLeftWristNeckDistance.x)
                                        let distanceInLocationY = abs(lastLeftWristDistance.y - currentLeftWristNeckDistance.y)
                                        if distanceInLocationX > maxDistanceInX || distanceInLocationY > maxDistanceInY {
                                            isPreparing = false
                                            printPreparingDebugInfo("currentLeftWristNeckDistance: \(currentLeftWristNeckDistance), lastLeftWristDistance: \(lastLeftWristDistance)")
                                            printPreparingDebugInfo("dx: \(distanceInLocationX), thresholdX: \(maxDistanceInX), dy: \(distanceInLocationY), thresholdY: \(maxDistanceInY)")
                                        }
                                        printPreparingDebugInfo("currentLeftWristNeckDistance: \(currentLeftWristNeckDistance), lastLeftWristDistance: \(lastLeftWristDistance)")
                                        printPreparingDebugInfo("dx: \(distanceInLocationX), thresholdX: \(maxDistanceInX), dy: \(distanceInLocationY), thresholdY: \(maxDistanceInY)")
                                    }
                                }
                                if let currentRightWristNeckDistance = currentWristNeckDistance.1 {
                                    if let lastRightWristDistance = lastWristNeckDistance?.1 {
                                        let distanceInLocationX = abs(lastRightWristDistance.x - currentRightWristNeckDistance.x)
                                        let distanceInLocationY = abs(lastRightWristDistance.y - currentRightWristNeckDistance.y)
                                        if distanceInLocationX > maxDistanceInX || distanceInLocationY > maxDistanceInY {
                                            isPreparing = false
                                            printPreparingDebugInfo("currentRightWristNeckDistance: \(currentRightWristNeckDistance), lastRightWristDistance: \(lastRightWristDistance)")
                                            printPreparingDebugInfo("dx: \(distanceInLocationX), thresholdX: \(maxDistanceInX), dy: \(distanceInLocationY), thresholdY: \(maxDistanceInY)")
                                        }
                                        printPreparingDebugInfo("currentRightWristNeckDistance: \(currentRightWristNeckDistance), lastRightWristDistance: \(lastRightWristDistance)")
                                        printPreparingDebugInfo("dx: \(distanceInLocationX), thresholdX: \(maxDistanceInX), dy: \(distanceInLocationY), thresholdY: \(maxDistanceInY)")
                                    }
                                }
                            }
                        }
                        
                        if isPreparing {
                            // check shoulder
                            if let currentLeftShoulderNeckDistance = currentShoulderNeckDistance.0 {
                                if let lastLeftShoulderDistance = lastShoulderNeckDistance?.0 {
                                    let distanceInLocationX = abs(lastLeftShoulderDistance.x - currentLeftShoulderNeckDistance.x)
                                    let distanceInLocationY = abs(lastLeftShoulderDistance.y - currentLeftShoulderNeckDistance.y)
                                    if distanceInLocationX > maxDistanceInX || distanceInLocationY > maxDistanceInY {
                                        isPreparing = false
                                        printPreparingDebugInfo("currentLeftShoulderNeckDistance: \(currentLeftShoulderNeckDistance), lastLeftShoulderDistance: \(lastLeftShoulderDistance)")
                                        printPreparingDebugInfo("dx: \(distanceInLocationX), thresholdX: \(maxDistanceInX), dy: \(distanceInLocationY), thresholdY: \(maxDistanceInY)")
                                    }
                                    printPreparingDebugInfo("currentLeftShoulderNeckDistance: \(currentLeftShoulderNeckDistance), lastLeftShoulderDistance: \(lastLeftShoulderDistance)")
                                    printPreparingDebugInfo("dx: \(distanceInLocationX), thresholdX: \(maxDistanceInX), dy: \(distanceInLocationY), thresholdY: \(maxDistanceInY)")
                                }
                            }
                            if let currentRightShoulderNeckDistance = currentShoulderNeckDistance.1 {
                                if let lastRightShoulderDistance = lastShoulderNeckDistance?.1 {
                                    let distanceInLocationX = abs(lastRightShoulderDistance.x - currentRightShoulderNeckDistance.x)
                                    let distanceInLocationY = abs(lastRightShoulderDistance.y - currentRightShoulderNeckDistance.y)
                                    if distanceInLocationX > maxDistanceInX || distanceInLocationY > maxDistanceInY {
                                        isPreparing = false
                                        printPreparingDebugInfo("currentRightShoulderNeckDistance: \(currentRightShoulderNeckDistance), lastRightShoulderDistance: \(lastRightShoulderDistance)")
                                        printPreparingDebugInfo("dx: \(distanceInLocationX), thresholdX: \(maxDistanceInX), dy: \(distanceInLocationY), thresholdY: \(maxDistanceInY)")
                                    }
                                    printPreparingDebugInfo("currentRightShoulderNeckDistance: \(currentRightShoulderNeckDistance), lastRightShoulderDistance: \(lastRightShoulderDistance)")
                                    printPreparingDebugInfo("dx: \(distanceInLocationX), thresholdX: \(maxDistanceInX), dy: \(distanceInLocationY), thresholdY: \(maxDistanceInY)")
                                }
                            }
                        }
                        
                        if isPreparing {
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
                            
                            if index == 0 || (!isPreparing && segment.end - segment.start > minFrameCount) || segment.end - segment.start > maxFrameCount {
                                result.append(segment)
                                printPreparingDebugInfo("preparing append")
                                poseSegment = nil
                            }
                            
                            if !isPreparing && poseSegment != nil {
                                poseSegment = nil
                                printPreparingDebugInfo("preparing failed")
                            }
                        }
                            
                        lastWristNeckDistance = currentWristNeckDistance
                        lastShoulderNeckDistance = currentShoulderNeckDistance
                    }
                }
            } else {
                lastWristNeckDistance = nil
                lastShoulderNeckDistance = nil
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
                if eyeDistance < 0.03 * context.getDistanceScaled() {
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
    
    private func getDistance(left: CGPoint?, right: CGPoint?) -> CGPoint? {
        if left != nil && right != nil {
            return CGPoint(x: right!.x - left!.x, y: right!.y - left!.y)
        }
        return nil
    }
    
    private func isShoulderStable(current: (CGPoint?, CGPoint?)?, last: (CGPoint?, CGPoint?)?, maxX: CGFloat, maxY: CGFloat) -> Bool {
        let shoulderMovement = getMaxShoulderMovement(current: current, last: last)
        return shoulderMovement.x <= maxX && shoulderMovement.y <= maxY
    }
    
    private func getMaxShoulderMovement(current: (CGPoint?, CGPoint?)?, last: (CGPoint?, CGPoint?)?) -> CGPoint {
        var maxX = CGFloat(0)
        // 0 is left shoulder, 1 is right shoulder
        maxX = getMaxDistance(left: current?.0?.x, right: last?.0?.x, max: maxX)
        maxX = getMaxDistance(left: current?.1?.x, right: last?.1?.x, max: maxX)
        
        var maxY = CGFloat(0)
        maxY = getMaxDistance(left: current?.0?.y, right: last?.0?.y, max: maxY)
        maxY = getMaxDistance(left: current?.1?.y, right: last?.1?.y, max: maxY)
        
        return CGPoint(x: maxX, y: maxY)
    }
    
    private func getMaxDistance(left: CGFloat?, right: CGFloat?, max: CGFloat) -> CGFloat {
        if left != nil && right != nil {
            let distance = abs(left! - right!)
            if distance > max {
                return distance
            }
        }
        return max
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
        
        let distanceThreshold = 110 * context.getDistanceScaled()
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
    
    func getDistanceScaled() -> CGFloat {
        if scaled < 0.8 {
            return 0.8
        } else {
            return scaled
        }
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
    
    func getEndSegment() -> PoseSegment? {
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
