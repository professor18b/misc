//
//  PoseDetectionManager.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/14.
//

import Vision
import AVFoundation
import CryptoKit
import Photos

class DetectedResult {
    let size: CGSize
    let frameRate: Float
    let joints: Array<[VNHumanBodyPoseObservation.JointName : VNRecognizedPoint]>
    let jointFrames: Int
    var frames: Int {
        get {
            return joints.count
        }
    }
    
    internal init(size: CGSize, frameRate: Float, joints: Array<[VNHumanBodyPoseObservation.JointName : VNRecognizedPoint]>, jointFrames: Int) {
        self.size = size
        self.frameRate = frameRate
        self.joints = joints
        self.jointFrames = jointFrames
    }
}

class PoseDetectionManager {
    
    static let shared = PoseDetectionManager()
    private let souceManager = SourceManager.shared
    
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
    
    func detectVideo(asset: AVURLAsset, debug: Bool = false) -> DetectedResult? {
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
        var frameJoints = Array<[VNHumanBodyPoseObservation.JointName : VNRecognizedPoint]>()
        var frameRate: Float = 0
        var jointFrames = 0
        if reader.startReading() {
            let natrualSize = track.naturalSize.applying(track.preferredTransform)
            size.width = abs(natrualSize.width)
            size.height = abs(natrualSize.height)
            frameRate = track.nominalFrameRate
            let orientation = PoseDetectionManager.getTrackOrientation(track: track)
            
            var writer: AVAssetWriter? = nil
            var input: AVAssetWriterInput? = nil
            if debug {
                let targetName = "skeleton_\(asset.url.lastPathComponent)"
                if var documentUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    documentUrl.appendPathComponent(targetName, isDirectory: false)
                    souceManager.delete(sourceUrl: documentUrl)
                    writer = try! AVAssetWriter(outputURL: documentUrl, fileType: .mp4)
                    let compressionProperties: [String: Any] = [
                        AVVideoExpectedSourceFrameRateKey: frameRate,
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                    ]
                    let outputSettings: [String : Any] = [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoWidthKey: size.width,
                        AVVideoHeightKey: size.height,
                        AVVideoCompressionPropertiesKey: compressionProperties
                    ]
                    print("outputSettings: \(outputSettings)")
                    input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
                    writer?.add(input!)
                    writer?.startWriting()
                    writer?.startSession(atSourceTime: CMTime.zero)
                }
            }
            
            while let sampleBuffer = output.copyNextSampleBuffer() {
                let joints = detect(sampleBuffer: sampleBuffer, orientation: orientation)
                frameJoints.append(joints)
                if hasJoint(joints: joints) {
                    jointFrames += 1
                }
                input?.append(sampleBuffer)
            }
            input?.markAsFinished()
            writer?.finishWriting {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer!.outputURL)
                }, completionHandler:{ success, error in
                    print("save photo library finished. success: \(success), error: \(error ?? "")")
                    self.souceManager.delete(sourceUrl: writer!.outputURL)
                })
            }
        }
        return DetectedResult(size: size, frameRate: frameRate, joints: frameJoints, jointFrames: jointFrames)
    }
    
    private func hasJoint(joints: [VNHumanBodyPoseObservation.JointName : VNRecognizedPoint]) -> Bool {
        for entry in joints {
            if entry.key.rawValue.rawValue.count > 0 {
                return true
            }
        }
        return false
    }
}
