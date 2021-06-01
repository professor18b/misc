//
//  PoseDetectionManager.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/14.
//

import Vision
import AVFoundation
import Photos
import UIKit

struct DetectedPoint {
    let location: CGPoint
    let confidence: Float
}

class DetectedResult {
    let size: CGSize
    let frameRate: Float
    let joints: [[String : DetectedPoint]]
    let jointFrames: Int
    var frames: Int {
        get {
            return joints.count
        }
    }
    
    internal init(size: CGSize, frameRate: Float, joints: [[String : DetectedPoint]], jointFrames: Int) {
        self.size = size
        self.frameRate = frameRate
        self.joints = joints
        self.jointFrames = jointFrames
    }
}

class PoseDetectionManager {
    private let debug = true
    static let shared = PoseDetectionManager()
    private let souceManager = SourceManager.shared
    
    private let detectPoseRequest = VNDetectHumanBodyPoseRequest()
    private let bodyPoseDetectionMinConfidence: VNConfidence = 0.6
    
    static let outputSettings = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
    
    func detect(cgImage: CGImage, orientation: CGImagePropertyOrientation)  -> [String : DetectedPoint] {
        let visionHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        return doDetectRequest(visionHandler: visionHandler)
    }
    
    func detect(sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> [String : DetectedPoint] {
        let visionHandler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])
        return doDetectRequest(visionHandler: visionHandler)
    }
    
    private func doDetectRequest(visionHandler: VNImageRequestHandler) -> [String : DetectedPoint] {
//        print("doDetectRequest: \(Thread.current)")
        var joints = [String : DetectedPoint]()
        do {
            try visionHandler.perform([detectPoseRequest])
            if let observation = detectPoseRequest.results?.first {
                if observation.confidence < bodyPoseDetectionMinConfidence {
                    return joints
                }
                // fetch body joints from the observation and overlay them on the player.
                guard let identifiedPoints = try? observation.recognizedPoints(.all) else {
                    return joints
                }
                
                for (key, point) in identifiedPoints {
                    guard point.confidence > 0.1 else {
                        continue
                    }
                    joints[key.keyName] = DetectedPoint(location: point.location, confidence: point.confidence)
                }
            }
        } catch {
        }
        return joints
    }
    
    static func getTrackOrientation(track: AVAssetTrack) -> CGImagePropertyOrientation {
        let affineTransform = track.preferredTransform.inverted()
        let angleInDegrees = atan2(affineTransform.b, affineTransform.a) * CGFloat(180) / CGFloat.pi
        var orientation: UInt32 = 1
        switch angleInDegrees {
        case 0:
            orientation = 1 // Recording button is on the right
        case 180, -180:
            orientation = 3 // abs(180) degree rotation recording button is on the right
        case 90:
            orientation = 8 // 90 degree CW rotation recording button is on the top
        case -90:
            orientation = 6 // 90 degree CCW rotation recording button is on the bottom
        default:
            orientation = 1
        }
        return CGImagePropertyOrientation(rawValue: orientation)!
    }
    
    func detectVideo(asset: AVURLAsset) -> DetectedResult? {
        guard let track = asset.tracks(withMediaType: .video).first else {
            return nil
        }
        guard let reader = try? AVAssetReader(asset: asset) else {
            return nil
        }
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32ARGB])
        reader.add(output)
        track.accessibilityElementCount()
        var detectSize = CGSize(width: 0, height: 0)
        var frameJoints = [[String : DetectedPoint]]()
        var frameRate: Float = 0
        var jointFrames = 0
        if reader.startReading() {
            let natrualSize = track.naturalSize
            let transformedSize = natrualSize.applying(track.preferredTransform)
            detectSize.width = abs(transformedSize.width)
            detectSize.height = abs(transformedSize.height)
            frameRate = track.nominalFrameRate
            let orientation = PoseDetectionManager.getTrackOrientation(track: track)
            let dataRate = track.estimatedDataRate
            print("start detect, duration:\(CMTimeGetSeconds(asset.duration)), dataRate: \(dataRate/(1024*1024)) Mbits/s, frameRate: \(frameRate), orientation: \(orientation.rawValue)")
            let processInfo = ProcessInfo()
            let startUpTime = processInfo.systemUptime
            while let sampleBuffer = output.copyNextSampleBuffer() {
                print(".", terminator: "")
                let joints = detect(sampleBuffer: sampleBuffer, orientation: orientation)
                frameJoints.append(joints)
                if hasJoint(joints: joints) {
                    jointFrames += 1
                }
            }
            print("")
            print("finish detect, costs: \(processInfo.systemUptime - startUpTime)")
        }
        return DetectedResult(size: detectSize, frameRate: frameRate, joints: frameJoints, jointFrames: jointFrames)
    }
    
    private func hasJoint(joints: [String : DetectedPoint]) -> Bool {
        for entry in joints {
            if entry.key.count > 0 {
                return true
            }
        }
        return false
    }
}
