//
//  AnalysisViewController.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/29.
//

import UIKit
import AVFoundation

class AnalysisViewController: BaseViewController {
    
    private let detectionManager = PoseDetectionManager.shared
    private let analysisManager = SwingAnalysisManager.shared
    
    @IBOutlet weak var descText: UILabel!
    
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
    
    override func viewDidLoad() {
        DispatchQueue.global().async {
            guard let detectedResult = self.detectionManager.detectVideo(asset: self.videoSource, exportSkeleton: true) else {
                DispatchQueue.main.async {
                    self.descText.text = "no result"
                }
                return
            }
           
            let analyzedResult = self.analysisManager.getAnalyzedResult(detectedResult: detectedResult)
            DispatchQueue.main.async {
                self.descText.text = "frames: \(detectedResult.frames), jointFrames: \(detectedResult.jointFrames), frameRate: \(detectedResult.frameRate)\nscaled: \(analyzedResult.scaled)"
            }
        }
    }
}
