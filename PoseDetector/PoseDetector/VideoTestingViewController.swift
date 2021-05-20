//
//  VideoTestingViewController.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/15.
//

import UIKit
import AVFoundation
import Vision

private let lastResultOutput = ""

class VideoTestingViewController: UIViewController {
    
    @IBOutlet weak var settingsLabel: UILabel!
    @IBOutlet weak var countLabel: UILabel!
    @IBOutlet weak var detectedLabel: UILabel!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var detailText: UITextView!
    
    private let detectionManager = PoseDetectionManager.shared
    private let sourceManager = SourceManager.shared
    private let apiRequestManager = ApiRequestManager.shared
    
    private let detectQueue = OperationQueue()
    
    private var serverUrl: String = ""
    private var token: String = ""
    
    private var count = 0
    private var detected = 0
    private var failed = 0
    private var skipped = 0
    private var detail = ""
    private var message = ""
    
    private var running = false
    
    private var lastResults = [Substring]()
        
    override func viewDidLoad() {
        NotificationCenter.default.addObserver(self, selector: #selector(notificationReceive), name: nil, object: nil)
        detectQueue.maxConcurrentOperationCount = 1
        loadSettings()
        loadLastResults()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self)
        super.viewDidDisappear(animated)
    }
    
    private func loadLastResults() {
        lastResults = lastResultOutput.split(separator: "\n")
        print("lastResults.count: \(lastResults.count)")
    }
    
    private func loadSettings() {
        serverUrl = UserDefaults.standard.string(forKey: SettingKey.serverUrl.rawValue)!
        token = UserDefaults.standard.string(forKey: SettingKey.token.rawValue)!
        
        var settingsValue = "[server url]: \n"
        settingsValue.append(serverUrl)
        settingsValue.append("\n[user token]: \n")
        settingsValue.append(token)
        settingsLabel.text = settingsValue
    }
    
    @objc func notificationReceive(notification: Notification) {
        if notification.name.rawValue == NotificationName.settingUpdated.rawValue {
            loadSettings()
        }
    }
    
    @IBAction func startTesting(_ sender: Any) {
        if running { return }
        running = true
        var data = [String: Any]()
        data["sortType"] = "BY_CREATE_TIMESTAMP_DESCEND"
        data["startTimestamp"] = Date.parse(dateString: "2020-04-30")?.getTimestamp()
        data["endTimestamp"] = Date.parse(dateString: "2021-06-01")?.getTimestamp()
        data["page"] = 0
        data["pageSize"] = 2000
        
        resetSummary(status: "start request...")
        let apiRequest = ApiRequest(path: "practice2/getSuccessSwingAnalyze", data: data)
        ApiRequestManager.shared.startApiRequest(apiRequest: apiRequest) {_, apiResponse in
            if apiResponse.isSuccess() {
                if let entities = apiResponse.data["successAnalyzes"] as? [[String: Any]] {
                    self.startDetect(entities: entities)
                } else {
                    self.message = "no data"
                    self.updateSummary()
                    self.running = false
                }
            } else {
                DialogUtil.showAlert(viewController: self, title: nil, message: "\(apiResponse.getReasonCode() ?? "")\n \(apiResponse.getReason()  ?? "")")
                self.running = false
                self.resetSummary()
            }
        }
    }
    
    private func startDetect(entities: [[String: Any]]) {
        count = entities.count
        message = "start detecting..."
        let semaphore = DispatchSemaphore(value: 0)
        for entity in entities {
            if let videoIdObj = entity["sourceVideoId"] as? [String: Any] {
                if let videoId = videoIdObj["id"] as? String {
                    if (alreadyDetected(videoId: videoId)) {
                        self.skipped += 1
                        DispatchQueue.main.async {
                            self.updateSummary()
                        }
                        continue
                    }
                    self.sourceManager.downloadVideo(videoId: videoId) { videoId, videoUrl, errorMessage in
                        if let url = videoUrl {
                            if let result = self.detectionManager.detectVideo(asset: AVURLAsset(url: url)) {
                                print("size: \(result.size), frames: \(result.frames)")
                                print("detect thead: \(Thread.current)")
                                let practiceId = (entity["practice2Id"] as! [String: Any])["id"] as! String
                                var data = [String: Any]()
                                data["practiceId"] = practiceId
                                data["sourceVideoId"] = videoId
                                data["width"] = result.size.width
                                data["height"] = result.size.height
                                data["points"] = self.getPoints(detectedResult: result)
                                let request = ApiRequest(path: "swingAnalyzeTest", data: data)
                                self.apiRequestManager.startTestingRequest(apiRequest: request) { (apiRequest, apiResponse) in
                                    print("callback thead: \(Thread.current)")
                                    self.detected += 1
                                    
                                    if apiResponse.isSuccess() {
                                        self.detail += "\(videoId)\n"
                                    } else {
                                        print("upload failed: \(String(describing: apiResponse.getReasonCode())), \(String(describing: apiResponse.getReason()))")
                                        self.detail += "F - \(videoId)\n"
                                        self.failed += 1
                                    }
                                    
                                    if self.detected == self.count - 1 {
                                        self.message = "finished"
                                        self.running = false
                                    }
                                    semaphore.signal()
                                    DispatchQueue.main.async {
                                        self.updateSummary()
                                    }
                                }
                            } else {
                                print("no result")
                                self.detail += "N - \(videoId)\n"
                                semaphore.signal()
                                DispatchQueue.main.async {
                                    self.updateSummary()
                                }
                            }
                            self.sourceManager.delete(sourceUrl: url)
                        } else {
                            self.detail += "F - \(videoId)\n"
                            self.failed += 1
                        }
                        
                        DispatchQueue.main.async {
                            self.updateSummary()
                        }
                    }
                }
            }
            semaphore.wait()
        }
    }
    
    private func alreadyDetected(videoId: String) -> Bool {
        for lastResult in lastResults {
            if lastResult == videoId {
                return true
            }
        }
        return false
    }
    
    private func resetSummary(status: String? = nil) {
        count = 0
        detected = 0
        failed = 0
        detail = ""
        if status != nil {
            message = status!
        } else {
            message = ""
        }
        
        updateSummary()
    }
    
    private func updateSummary() {
        countLabel.text = "count: \(count)"
        detectedLabel.text = "detected: \(detected), failed: \(failed), skipped: \(skipped)"
        messageLabel.text = message
        detailText.text = detail
    }
    
    private func getPoints(detectedResult: DetectedResult) -> String? {
        if detectedResult.frames == 0 { return nil }
        var isFirst = true
        var result = "["
        for joints in detectedResult.joints {
            if !isFirst {
                result.append(",")
            }
            isFirst = false
            result.append("[")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.nose.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.neck.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.rightShoulder.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.rightElbow.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.rightWrist.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.leftShoulder.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.leftElbow.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.leftWrist.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.root.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.rightHip.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.rightKnee.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.rightAnkle.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.leftHip.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.leftKnee.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.leftAnkle.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.rightEye.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.leftEye.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.rightEar.keyName, joins: joints, size: detectedResult.size))
            result.append(",")
            result.append(getFrameJoint(jointName: VNHumanBodyPoseObservation.JointName.leftEar.keyName, joins: joints, size: detectedResult.size))
            result.append(",0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0")
            result.append("]")
        }
        result.append("]")
        return result
    }
    
    private func getFrameJoint(jointName: String, joins: [String: DetectedPoint], size: CGSize) -> String {
        let flipVertical =  CGAffineTransform.verticalFlip
        let scaledTransform = CGAffineTransform(scaleX: size.width, y: size.height)
        let scaledPoint: CGPoint
        let confidence: Float
        if let point = joins[jointName] {
            scaledPoint = point.location.applying(flipVertical).applying(scaledTransform)
            confidence = point.confidence
        } else {
            scaledPoint = CGPoint(x: 0, y: 0)
            confidence = 0
        }
        var result = ""
        result.append("\(scaledPoint.x),")
        result.append("\(scaledPoint.y),")
        result.append("\(confidence)")
        return result
    }
}
