//
//  PoseDetectionManager.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/14.
//

import Vision
import AVFoundation

struct DetectedResult {
    let size: CGSize
    let frames: Int
    let joints: Array<[VNHumanBodyPoseObservation.JointName : VNRecognizedPoint]>
}

class PoseDetectionManager {
    
    static let shared = PoseDetectionManager()
    
    private let detectPoseRequest = VNDetectHumanBodyPoseRequest()
    private let bodyPoseDetectionMinConfidence: VNConfidence = 0.6
    
    static let outputSettings = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
    
    func detect(cgImage: CGImage, orientation: CGImagePropertyOrientation)  -> [VNHumanBodyPoseObservation.JointName : VNRecognizedPoint] {
        let visionHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        return doDetectRequest(visionHandler: visionHandler)
    }
    
    func detect(sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> [VNHumanBodyPoseObservation.JointName : VNRecognizedPoint] {
        let visionHandler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])
        return doDetectRequest(visionHandler: visionHandler)
    }
    
    private func doDetectRequest(visionHandler: VNImageRequestHandler) -> [VNHumanBodyPoseObservation.JointName : VNRecognizedPoint] {
//        print("doDetectRequest: \(Thread.current)")
        var joints = [VNHumanBodyPoseObservation.JointName : VNRecognizedPoint]()
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
                    joints[key] = point
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
    
    func detectVideo(asset: AVAsset) -> DetectedResult? {
        guard let track = asset.tracks(withMediaType: .video).first else {
            return nil
        }
        guard let reader = try? AVAssetReader(asset: asset) else {
            return nil
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: PoseDetectionManager.outputSettings)
        reader.add(output)
        track.accessibilityElementCount()
        var size = CGSize(width: 0, height: 0)
        var frames = 0
        var frameJoints = Array<[VNHumanBodyPoseObservation.JointName : VNRecognizedPoint]>()
        if reader.startReading() {
            let natrualSize = track.naturalSize.applying(track.preferredTransform)
            size = CGSize(width: abs(natrualSize.width), height: abs(natrualSize.height))
            let orientation = PoseDetectionManager.getTrackOrientation(track: track)
            while let sampleBuffer = output.copyNextSampleBuffer() {
                let joints = detect(sampleBuffer: sampleBuffer, orientation: orientation)
                frameJoints.append(joints)
                frames += 1
            }
        }
        return DetectedResult(size: size, frames: frames, joints: frameJoints)
    }
}
