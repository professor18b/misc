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
    
    func detectVideo(asset: AVURLAsset, exportSkeleton: Bool = false) -> DetectedResult? {
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
            print("start detect, duration:\(CMTimeGetSeconds(asset.duration)), dataRate: \(dataRate/(1024*1024)) Mbits/s, frameRate: \(frameRate), orientation: \(orientation.rawValue),")
            let processInfo = ProcessInfo()
            let startUpTime = processInfo.systemUptime
            var writer: SkeletonVideoWriter? = nil
            
            if exportSkeleton {
                let targetName = "skeleton_\(asset.url.lastPathComponent)"
                if var exportUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    exportUrl.appendPathComponent(targetName, isDirectory: false)
                    souceManager.delete(sourceUrl: exportUrl)
                    writer = SkeletonVideoWriter(exportUrl: exportUrl, videoSize: natrualSize, dataRate: dataRate, frameRate: frameRate, transform: track.preferredTransform,  orientation: orientation)
                }
            }
            writer?.startSessionWriting(debug: debug)
            while let sampleBuffer = output.copyNextSampleBuffer() {
                print(".", terminator: "")
                let joints = detect(sampleBuffer: sampleBuffer, orientation: orientation)
                frameJoints.append(joints)
                if hasJoint(joints: joints) {
                    jointFrames += 1
                }
                writer?.append(sampleBuffer: sampleBuffer, joints: joints)
            }
            print("")
            writer?.finishWriting {
                print("finish writing")
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer!.exportUrl)
                }, completionHandler:{ success, error in
                    print("saved to photo library, success: \(success), error: \(error ?? "")")
                    self.souceManager.delete(sourceUrl: writer!.exportUrl)
                })
            }
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

class DebugContext {
    fileprivate(set) var writingFrame = -1
    fileprivate(set) var writedFrameJoints = [[String: DetectedPoint]]()
}

class SkeletonVideoWriter {
    let exportUrl: URL
    let videoSize: (Int, Int)
    let orientation: CGImagePropertyOrientation
    
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let skelentonRender: SkeletonRender

    private var debugContext: DebugContext?
    
    init(exportUrl: URL, videoSize: CGSize, dataRate: Float, frameRate: Float, transform: CGAffineTransform, orientation: CGImagePropertyOrientation) {
        self.exportUrl = exportUrl
        self.videoSize = (Int(videoSize.width), Int(videoSize.height))
        self.orientation = orientation
        skelentonRender = SkeletonRender(videoSize: videoSize, orientation: orientation)
        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: SkeletonVideoWriter.getCompressBitRate(videoSize: videoSize, dataRate: dataRate),
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
        ]
        
        let outputSettings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.transform = transform
        writer = try! AVAssetWriter(outputURL: exportUrl, fileType: .mp4)
        writer.add(input)
    }
    
    private static func getCompressBitRate(videoSize: CGSize, dataRate: Float) -> Float {
        let kbps: Float
        if videoSize.width >= 1920 {
            kbps = 4992
        } else if videoSize.width >= 1280 {
            kbps = 2496
        } else if videoSize.width >= 1024 {
            kbps = 1856
        } else {
            kbps = 1216
        }
        let compress: Float = kbps * 1024
        if dataRate < compress {
            return dataRate
        }
        return compress
    }
    
    private func getAudioBitRate(videoSize: CGSize) -> Int {
        return 64 * 1024
    }
    
    func startSessionWriting(atSourceTime: CMTime = CMTime.zero, debug: Bool = false) {
        writer.startWriting()
        writer.startSession(atSourceTime: atSourceTime)
        if debug {
            debugContext = DebugContext()
        }
    }
    
    func finishWriting(completionHandler: @escaping () -> Void) {
        input.markAsFinished()
        writer.finishWriting(completionHandler: completionHandler)
        debugContext = nil
    }
    
    func append(sampleBuffer: CMSampleBuffer, joints: [String : DetectedPoint]) {
        guard let cvImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            fatalError("create cvImageBuffer error")
        }
        CVPixelBufferLockBaseAddress(cvImageBuffer, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(cvImageBuffer)
        // width: 540, height: 960, bytesPerRow: 2176; width: 1080, height: 1920, bytesPerRow: 4352; width: 1920, height: 1080, bytesPerRow: 7680
        let width = CVPixelBufferGetWidth(cvImageBuffer)
        let height = CVPixelBufferGetHeight(cvImageBuffer)
        let bitsPerComponent = 8
        let bytesPerRow = CVPixelBufferGetBytesPerRow(cvImageBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
    
        guard let cgContext = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
            fatalError("create cgContext error")
        }
        CVPixelBufferUnlockBaseAddress(cvImageBuffer, .readOnly)
        debugContext?.writingFrame += 1
        skelentonRender.render(in: cgContext, joints: joints, debugContext: debugContext)
        debugContext?.writedFrameJoints.append(joints)
        var count = 0
        while(true) {
            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
                break
            }
            count += 1
            if count == 10 {
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
