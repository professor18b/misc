//
//  ImageViewController.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/25.
//

import UIKit
import AVFoundation

class ImageViewController: BaseViewController {
    
    static func start(source: BaseViewController, imageSource: UIImage) {
        source.performSegueWithArguments(withIdentifier: "ShowImageView", arguments: ["imageSource" : imageSource])
    }
    
    private let jointSegmentView = JointSegmentView()
    private var imageSource: UIImage!
    
    override func processSegueArguments(arguments: [String : Any]) {
        imageSource = arguments["imageSource"] as? UIImage
    }
    
    override func viewDidLoad() {
        let imageView = UIImageView(frame: view.bounds)
        imageView.image = imageSource
        imageView.contentMode = UIView.ContentMode.scaleAspectFit
        view.addSubview(imageView)
        
        view.addSubview(jointSegmentView)
        jointSegmentView.updateJoints(cgImage: imageSource.cgImage!, orientation: convertOrientation(imageOrientation: imageSource.imageOrientation), sourceView: imageView)
    }
    
    private func convertOrientation(imageOrientation: UIImage.Orientation?) -> CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        default:
            fatalError("not implement orientation: \(String(describing: imageOrientation))")
        }
    }
}

extension UIImageView: NormalizedGeometryConverting {
    
    func viewRectConverted(fromNormalizedContentsRect normalizedRect: CGRect) -> CGRect {
        let rect = getImageRect()
        let origin = CGPoint(x: rect.origin.x + normalizedRect.origin.x * rect.width,
                             y: rect.origin.y + normalizedRect.origin.y * rect.height)
        let size = CGSize(width: normalizedRect.width * rect.width,
                          height: normalizedRect.height * rect.height)
        let convertedRect = CGRect(origin: origin, size: size)
        print("view bounds: \(bounds)")
        print("image rect: \(rect)")
        print("convertedRect: \(convertedRect)")
        return convertedRect
    }
    
    func viewPointConverted(fromNormalizedContentsPoint normalizedPoint: CGPoint) -> CGPoint {
        let rect = getImageRect()
        let convertedPoint = CGPoint(x: rect.origin.x + normalizedPoint.x * rect.width,
                                     y: rect.origin.y + normalizedPoint.y * rect.height)
        return convertedPoint
    }
    
    private func getImageRect() -> CGRect {
        guard let image = image else {
            return bounds
        }
        guard contentMode == .scaleAspectFit else { return bounds }
        
        guard image.size.width > 0 && image.size.height > 0 else { return bounds }
        
        let scaleWidth = bounds.width / image.size.width
        let scaleHeight = bounds.height / image.size.height
        let aspect = fmin(scaleWidth, scaleHeight)

        let size = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
        let x = (bounds.width - size.width) / 2.0
        let y = (bounds.height - size.height) / 2.0

        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
