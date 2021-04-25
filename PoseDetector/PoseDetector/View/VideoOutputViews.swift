//
//  VideoOutputView.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/1.
//

import UIKit
import AVFoundation

/// coordinate conversion
protocol NormalizedGeometryConverting {
    // This helper function is used to convert rects returned by Vision to the video content rect coordinates.
    //
    // The video content rect (camera preview or pre-recorded video)
    // is scaled to fit into the view controller's view frame preserving the video's aspect ratio
    // and centered vertically and horizontally inside the view.
    //
    // Vision coordinates have origin at the bottom left corner and are normalized from 0 to 1 for both dimensions.
    //
    func viewRectConverted(fromNormalizedContentsRect normalizedRect: CGRect) -> CGRect
    // This helper function is used to convert points returned by Vision to the video content rect coordinates.
    //
    // The video content rect (camera preview or pre-recorded video)
    // is scaled to fit into the view controller's view frame preserving the video's aspect ratio
    // and centered vertically and horizontally inside the view.
    //
    // Vision coordinates have origin at the bottom left corner and are normalized from 0 to 1 for both dimensions.
    //
    func viewPointConverted(fromNormalizedContentsPoint normalizedPoint: CGPoint) -> CGPoint
}

/// view to display live camera feed
class CameraFeedView :UIView, NormalizedGeometryConverting {
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    init(frame: CGRect, session: AVCaptureSession, videoOrientation: AVCaptureVideoOrientation) {
        super.init(frame: frame)
        previewLayer = layer as? AVCaptureVideoPreviewLayer
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspect
        previewLayer.connection?.videoOrientation = videoOrientation
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    func viewRectConverted(fromNormalizedContentsRect normalizedRect: CGRect) -> CGRect {
        return previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
    }
    
    func viewPointConverted(fromNormalizedContentsPoint normalizedPoint: CGPoint) -> CGPoint {
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
    }
    
    func getVideoOrientation() -> AVCaptureVideoOrientation? {
        return previewLayer.connection?.videoOrientation
    }
}

/// view for rendering video file
class VideoRenderView: UIView, NormalizedGeometryConverting {
    
    var renderLayer: AVPlayerLayer!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        renderLayer = layer as? AVPlayerLayer
        renderLayer.videoGravity = .resizeAspect
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    var player: AVPlayer? {
        get {
            return renderLayer.player
        }
        set {
            renderLayer.player = newValue
        }
    }
    
    func viewRectConverted(fromNormalizedContentsRect normalizedRect: CGRect) -> CGRect {
        let videoRect = renderLayer.videoRect
        let origin = CGPoint(x: videoRect.origin.x + normalizedRect.origin.x * videoRect.width,
                             y: videoRect.origin.y + normalizedRect.origin.y * videoRect.height)
        let size = CGSize(width: normalizedRect.width * videoRect.width,
                          height: normalizedRect.height * videoRect.height)
        let convertedRect = CGRect(origin: origin, size: size)
        return convertedRect.integral
    }
    
    func viewPointConverted(fromNormalizedContentsPoint normalizedPoint: CGPoint) -> CGPoint {
        let videoRect = renderLayer.videoRect
        let convertedPoint = CGPoint(x: videoRect.origin.x + normalizedPoint.x * videoRect.width,
                                     y: videoRect.origin.y + normalizedPoint.y * videoRect.height)
        return convertedPoint
    }
}
