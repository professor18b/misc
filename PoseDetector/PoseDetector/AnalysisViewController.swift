//
//  AnalysisViewController.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/29.
//

import UIKit
import AVFoundation

class AnalysisViewController: BaseViewController {

    static func start(source: BaseViewController, videoUrl: URL) {
        source.performSegueWithArguments(withIdentifier: "ShowAnalysisView", arguments: ["videoUrl": videoUrl])
    }
    
    private var videoSource: AVURLAsset!
    
    override func processSegueArguments(arguments: [String : Any]) {
        guard let url = arguments["videoUrl"] as? URL else {
            fatalError("video url not found")
        }
        videoSource = AVURLAsset(url: url)
    }
    
    private let detectionManager = PoseDetectionManager.shared
    private let analysisManager = SwingAnalysisManager.shared
    
    private var analyzedResult: AnalyzedResult?
    private var descText: UILabel!
    private var baseText: String!
    
    override func viewDidLoad() {
        let processInfo = ProcessInfo()
        let startUpTime = processInfo.systemUptime
        setupVideoPlayer()
        descText = UILabel(frame: CGRect(x: 10, y: 10, width: view.bounds.width - 20, height: view.bounds.height - 20))
        descText.lineBreakMode = .byWordWrapping
        descText.numberOfLines = 0
        descText.textColor = .systemPink
        descText.text = "analyzing..."
        view.addSubview(descText)
        DispatchQueue.global().async {
            guard let detectedResult = self.detectionManager.detectVideo(asset: self.videoSource) else {
                DispatchQueue.main.async {
                    self.descText.text = "no result"
                }
                return
            }
//            print("--------------------------")
//            var count = 0
//            print("size:\(detectedResult.size)")
//            print("frameRate:\(detectedResult.frameRate)")
//            print("jointFrames:\(detectedResult.jointFrames)")
//            for element in detectedResult.joints {
//                print("{")
//                for entry in element {
//                    print("\(entry.key)|\(entry.value.location)")
//                }
//                print("}")
//                count += 1
//            }
//            print("--------------------------")
            
            self.analyzedResult = self.analysisManager.getAnalyzedResult(detectedResult: detectedResult)
            
//            SkeletonVideoExporter.export(asset: self.videoSource,analyzeResult: self.analyzedResult!, exportAllFrames: true, debug: true)
            
            DispatchQueue.main.async {
                var text = "used time: \(self.getTimeString(processInfo: processInfo, startUpTime: startUpTime))\n"
                text.append("frames: \(detectedResult.frames), frameRate: \(detectedResult.frameRate)\n")
                text.append("scaled: \(self.analyzedResult!.scaled)\n")
                text.append("\(self.analyzedResult?.poseSegments.count ?? 0) segments:\n")
                if let segments = self.analyzedResult?.poseSegments {
                    var count = 0
                    for segment in segments {
                        text.append("\(segment)\n")
                        count += 1
                        if count >= 3 {
                            break
                        }
                    }
                }
                self.descText.text = text
                self.baseText = text
            }
        }
    }
    
    private func getTimeString(processInfo: ProcessInfo, startUpTime: Double) -> String {
        let duration = processInfo.systemUptime - startUpTime
        if duration > 60 {
            return "\(duration / 60)m"
        }
        return "\(duration)s"
    }
    
    private func setupVideoPlayer() {
        let videoRenderView = VideoRenderView(frame: view.bounds)
        videoRenderView.translatesAutoresizingMaskIntoConstraints = false
        videoRenderView.backgroundColor = UIColor.black
        view.addSubview(videoRenderView)
        NSLayoutConstraint.activate([
            videoRenderView.leftAnchor.constraint(equalTo: view.leftAnchor),
            videoRenderView.rightAnchor.constraint(equalTo: view.rightAnchor),
            videoRenderView.topAnchor.constraint(equalTo: view.topAnchor),
            videoRenderView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        guard videoSource.tracks(withMediaType: .video).first != nil else {
            DialogUtil.showAlert(viewController: self, title: nil, message: "load video failed")
            return
        }
        let playerItem = AVPlayerItem(asset: videoSource)
        let player = AVPlayer(playerItem: playerItem)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: PoseDetectionManager.outputSettings)
        playerItem.add(output)
        player.actionAtItemEnd = .pause
        player.play()
        videoRenderView.player = player
    }
    
    @IBAction func export(_ sender: Any) {
        if let result = analyzedResult {
            descText.text = baseText.appending("\nexporting")
            DispatchQueue.global().async {
                SkeletonVideoExporter.export(asset: self.videoSource, analyzeResult: result, noSkeleton: true, debug: true) { current, total in
                    DispatchQueue.main.async {
                        self.descText.text = self.baseText.appending("\nexported: \(current+1)/\(total)")
                    }
                    if current == total - 1 {
                        DialogUtil.showAlert(viewController: self, title: nil, message: "export finished")
                    }
                }
            }
        } else {
            DialogUtil.showAlert(viewController: self, title: nil, message: "no result to export")
        }
    }
}
