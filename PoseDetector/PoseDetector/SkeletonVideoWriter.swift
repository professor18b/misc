//
//  SkeletonVideoWriter.swift
//  PoseDetector
//
//  Created by WuLei on 2021/5/31.
//

import AVFoundation

class DebugContext {
    fileprivate(set) var writingFrameIndex = 0
    fileprivate(set) var writedFrameJoints = [[String: DetectedPoint]]()
}

class SkeletonVideoWriter {
    let exportUrl: URL
    
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let skelentonRender: SkeletonRender?

    private var startFrameIndex = 0
    private var writedFrameCount = 0
    
    private var debugContext: DebugContext?
    
    init(exportUrl: URL, videoSize: CGSize, dataRate: Float, frameRate: Float, transform: CGAffineTransform, orientation: CGImagePropertyOrientation, noSkeleton: Bool = false) {
        self.exportUrl = exportUrl
        if noSkeleton {
            skelentonRender = nil
        } else {
            skelentonRender = SkeletonRender(videoSize: videoSize, orientation: orientation)
        }
        
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
    
    func startWriting(atSourceFrameIndex: Int, atSourceTime: CMTime = CMTime.zero, debug: Bool = false) {
        startFrameIndex = atSourceFrameIndex
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
        
        debugContext?.writingFrameIndex = startFrameIndex + writedFrameCount
        if let render = skelentonRender {
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
            render.render(in: cgContext, joints: joints, debugContext: debugContext)
        }
        debugContext?.writedFrameJoints.append(joints)
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        } else {
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
        writedFrameCount += 1
    }
}
