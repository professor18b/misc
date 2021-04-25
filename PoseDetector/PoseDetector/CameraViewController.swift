//
//  CameraViewController.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/6.
//

import UIKit
import AVFoundation

class CameraViewController: BaseViewController {
    
    static func start(source: BaseViewController) {
        source.performSegue(withIdentifier: "ShowCameraView", sender: source)
    }
    
    // live camera feed management
    private var cameraFeedView: CameraFeedView!
    private var cameraFeedSession: AVCaptureSession?
    private let videoDataOutputQueue = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInitiated,
                                                     attributes: [], autoreleaseFrequency: .workItem)
    
    private let jointSegmentView = JointSegmentView()
    private let detectionManager = PoseDetectionManager.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        do {
            try setupAVSession()
            view.addSubview(jointSegmentView)
        } catch {
            self.navigationController?.popViewController(animated: true)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        cameraFeedSession?.stopRunning()
        super.viewDidDisappear(animated)
    }
    
    private func setupAVSession() throws {
        // create device discovery session for a wide angle camera
        let wideAngleCamera = AVCaptureDevice.DeviceType.builtInWideAngleCamera
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [wideAngleCamera], mediaType: .video, position: .unspecified)
        guard let videoDevice = discoverySession.devices.first else {
            DialogUtil.showAlert(viewController: self, title: nil, message: "wide angle camera not found")
            return
        }
        guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            DialogUtil.showAlert(viewController: self, title: nil, message: "create video device input failed")
            return
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        // we prefer a 1080p video capture but if camera cannot provide it then fall back to highest possible quality
        if videoDevice.supportsSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }
        
        // add a video input
        guard session.canAddInput(deviceInput) else {
            DialogUtil.showAlert(viewController: self, title: nil, message: "add video input session failed")
            return
        }
        session.addInput(deviceInput)
        
        let dataOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            DialogUtil.showAlert(viewController: self, title: nil, message: "add video output session failed")
            return
        }
        
        let captureConnection = dataOutput.connection(with: .video)
        captureConnection?.preferredVideoStabilizationMode = .standard
        // always process the frames
        captureConnection?.isEnabled = true
        session.commitConfiguration()
        cameraFeedSession = session
        
        // get the interface orientaion from window scene to set proper video orientation on capture connection.
        let videoOrientation: AVCaptureVideoOrientation
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeRight:
            videoOrientation = .landscapeRight
        case .landscapeLeft:
            videoOrientation = .landscapeLeft
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        default:
            videoOrientation = .portrait
        }
        // create and setup video feed view
        cameraFeedView = CameraFeedView(frame: view.bounds, session: session, videoOrientation: videoOrientation)
        cameraFeedView.translatesAutoresizingMaskIntoConstraints = false
        cameraFeedView.backgroundColor = UIColor.black
        view.addSubview(cameraFeedView)
        NSLayoutConstraint.activate([
            cameraFeedView.leftAnchor.constraint(equalTo: view.leftAnchor),
            cameraFeedView.rightAnchor.constraint(equalTo: view.rightAnchor),
            cameraFeedView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraFeedView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        cameraFeedSession?.startRunning()
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // not main thread
//        print("captureOutput: \(Thread.current)")
        // body pose request is performed on the same camera queue to ensure the highlighted joints are aligned with the player.
        jointSegmentView.updateJoints(sampleBuffer: sampleBuffer, orientation: convertOrientation(videoOrientation: cameraFeedView.getVideoOrientation()), sourceView: cameraFeedView)
    }
    
    private func convertOrientation(videoOrientation: AVCaptureVideoOrientation?) -> CGImagePropertyOrientation {
        switch videoOrientation {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        default:
            return .right
        }
    }
}
