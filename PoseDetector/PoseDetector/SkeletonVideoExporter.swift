//
//  SkeletonVideoExporter.swift
//  PoseDetector
//
//  Created by WuLei on 2021/5/31.
//

import AVFoundation
import Photos

class SkeletonVideoExporter {
    
    private init() {}
    
    private static let sourceManager = SourceManager.shared
    
    static func export(asset: AVURLAsset, analyzeResult: AnalyzedResult, noSkeleton: Bool = false, exportAllFrames: Bool = false, debug: Bool = false, progressHandler: @escaping (_ current: Int, _ total: Int) -> Void = {_,_ in }) {
        guard let track = asset.tracks(withMediaType: .video).first else {
            fatalError("invalid video")
        }
        guard let reader = try? AVAssetReader(asset: asset) else {
            fatalError("read video failed")
        }
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32ARGB])
        reader.add(output)
        track.accessibilityElementCount()
        if reader.startReading() {
            let natrualSize = track.naturalSize
            let frameRate = track.nominalFrameRate
            let orientation = PoseDetectionManager.getTrackOrientation(track: track)
            let dataRate = track.estimatedDataRate
            print("start export, duration:\(CMTimeGetSeconds(asset.duration)), dataRate: \(dataRate/(1024*1024)) Mbits/s, frameRate: \(frameRate), orientation: \(orientation.rawValue)")
            let processInfo = ProcessInfo()
            let startUpTime = processInfo.systemUptime
            
            var exportSegments: [(Int, Int)]
            if exportAllFrames || analyzeResult.poseSegments.isEmpty {
                exportSegments = [(0, analyzeResult.detectedResult.frames - 1)]
            } else {
                exportSegments = [(Int, Int)]()
                for poseSegment in analyzeResult.poseSegments {
                    exportSegments.append((poseSegment.start, poseSegment.getEndSegment()!.end))
                }
            }
            
            var skeletonWriter: SkeletonVideoWriter?
            var frameIndex = 0
            var segmentIndex = 0
            while let sampleBuffer = output.copyNextSampleBuffer() {
                let currentSegment = exportSegments[segmentIndex]
                if frameIndex == currentSegment.0 {
                    // start export
                    let targetName = "detected_\(segmentIndex + 1)_\(asset.url.lastPathComponent)"
                    if var exportUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        exportUrl.appendPathComponent(targetName, isDirectory: false)
                        sourceManager.delete(sourceUrl: exportUrl)
                        skeletonWriter = SkeletonVideoWriter(exportUrl: exportUrl, videoSize: natrualSize, dataRate: dataRate, frameRate: frameRate, transform: track.preferredTransform,  orientation: orientation, noSkeleton: noSkeleton)
                    }
                    let atTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    skeletonWriter?.startWriting(atSourceFrameIndex: frameIndex, atSourceTime: atTime, debug: debug)
                    print("start writing \(segmentIndex + 1) / \(exportSegments.count)")
                }
                if let writer = skeletonWriter {
                    writer.append(sampleBuffer: sampleBuffer, joints: analyzeResult.detectedResult.joints[frameIndex])
                    if frameIndex == currentSegment.1 {
                        // end export
                        let finishedSegmentIndex = segmentIndex
                        let exportUrl = writer.exportUrl
                        writer.finishWriting {
                            print("finish writing \(finishedSegmentIndex), exportUrl: \(exportUrl)")
                            PHPhotoLibrary.shared().performChanges({
                                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: exportUrl)
                            }, completionHandler:{ success, error in
                                print("saved to photo library, success: \(success), error: \(error ?? "")")
                                self.sourceManager.delete(sourceUrl: exportUrl)
                                progressHandler(finishedSegmentIndex, exportSegments.count)
                            })
                        }
                        skeletonWriter = nil
                        if segmentIndex >= exportSegments.count - 1 {
                            break
                        }
                        segmentIndex += 1
                    }
                }
                frameIndex += 1
            }
            print("finish export, costs: \(processInfo.systemUptime - startUpTime)")
        }
    }
}
