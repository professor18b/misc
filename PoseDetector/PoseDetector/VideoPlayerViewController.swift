//
//  VideoPlayerViewController.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/23.
//

import UIKit
import AVFoundation

class VideoPlayerViewController: BaseViewController {
    
    static func start(source: BaseViewController, videoSource: AVURLAsset) {
        source.performSegueWithArguments(withIdentifier: "ShowVideoPlayerView", arguments: ["videoSource": videoSource])
    }
    
    // video file playback management
    private var videoRenderView: VideoRenderView!
    private var playerItemOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private let videoFileReadingQueue = DispatchQueue(label: "VideoFileReading", qos: .userInteractive)
    private var videoFileBufferOrientation = CGImagePropertyOrientation.up
    private var videoFileFrameDuration = CMTime.invalid
    
    private var videoSource: AVURLAsset!
    
    private var jointSegmentView = JointSegmentView()
    private let detectionManager = PoseDetectionManager.shared

    override func processSegueArguments(arguments: [String : Any]) {
        videoSource = arguments["videoSource"] as? AVURLAsset
    }
    
    override func viewDidLoad() {
        startReadingAsset(asset: videoSource)
        view.addSubview(jointSegmentView)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        displayLink?.remove(from: RunLoop.current, forMode: .default)
        videoRenderView.player?.pause()
        SourceManager.shared.delete(sourceUrl: videoSource.url)
        super.viewDidDisappear(animated)
    }
    
    private func startReadingAsset(asset: AVAsset) {
        videoRenderView = VideoRenderView(frame: view.bounds)
        videoRenderView.translatesAutoresizingMaskIntoConstraints = false
        videoRenderView.backgroundColor = UIColor.black
        view.addSubview(videoRenderView)
        NSLayoutConstraint.activate([
            videoRenderView.leftAnchor.constraint(equalTo: view.leftAnchor),
            videoRenderView.rightAnchor.constraint(equalTo: view.rightAnchor),
            videoRenderView.topAnchor.constraint(equalTo: view.topAnchor),
            videoRenderView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        
                
        guard let track = asset.tracks(withMediaType: .video).first else {
            DialogUtil.showAlert(viewController: self, title: nil, message: "load video failed")
            return
        }
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: PoseDetectionManager.outputSettings)
        playerItem.add(output)
        player.actionAtItemEnd = .pause
        player.play()
        player.rate = 0.5

        let displayLink = CADisplayLink(target: self, selector: #selector(handlerDisplayLink(_:)))
        displayLink.preferredFramesPerSecond = 0 // use display's rate
        displayLink.isPaused = true
        displayLink.add(to: RunLoop.current, forMode: .default)
        
        self.displayLink = displayLink
        playerItemOutput = output
        videoRenderView.player = player
        videoFileBufferOrientation = PoseDetectionManager.getTrackOrientation(track: track)
        videoFileFrameDuration = track.minFrameDuration
        displayLink.isPaused = false
    }
    
    @objc
    private func handlerDisplayLink(_ displayLink: CADisplayLink) {
        guard let output = playerItemOutput else {
            return
        }
        if videoRenderView.player?.rate == 0 {
            return
        }
        // main thread
//        print("handlerDisplayLink: \(Thread.current)")
        videoFileReadingQueue.sync {
            let nextTimestamp = displayLink.timestamp + displayLink.duration
            let itemTime = output.itemTime(forHostTime: nextTimestamp)
            guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
                return
            }
            // create sample buffer from pixel buffer
            var sampleBuffer: CMSampleBuffer?
            var formatDescription: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
            let duration = self.videoFileFrameDuration
            var timingInfo = CMSampleTimingInfo(duration: duration, presentationTimeStamp: itemTime, decodeTimeStamp: itemTime)
            CMSampleBufferCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription!, sampleTiming: &timingInfo, sampleBufferOut: &sampleBuffer)
            if let sampleBuffer = sampleBuffer {
                self.jointSegmentView.updateJoints(sampleBuffer: sampleBuffer, orientation: self.videoFileBufferOrientation, sourceView: self.videoRenderView)
            }
        }
    }
}
