//
//  RootViewController.swift
//  PoseDetector
//
//  Created by WuLei on 2021/3/31.
//

import UIKit
import AVFoundation

class HomeViewController: BaseViewController {
    
    private let sourceManager = SourceManager.shared
    private var pickerIdentifier: String?
    
    @IBAction func pickVideoSource(_ sender: UIView) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.mediaTypes = ["public.movie"]
        picker.videoMaximumDuration = 10
        picker.sourceType = UIImagePickerController.SourceType.savedPhotosAlbum
        picker.videoExportPreset = AVAssetExportPresetPassthrough
        pickerIdentifier = sender.accessibilityIdentifier
        present(picker, animated: true)
    }
    
    @IBAction func downloadSource(_ sender: UIView) {
        let alert = UIAlertController(title: nil, message: "input videoId", preferredStyle: .alert)
        alert.addTextField(configurationHandler: nil)
        let savedId = UserDefaults.standard.string(forKey: "savedId")
        alert.textFields?[0].text = savedId
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            guard let videoId = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            UserDefaults.standard.setValue(videoId, forKey: "savedId")
            if videoId.count == 36 {
                self.sourceManager.downloadVideo(videoId: videoId) { videoId, videoUrl, errorMessage in
                    if let url = videoUrl {
                        DispatchQueue.main.async {
                            if sender.accessibilityIdentifier == "detect" {
                                VideoPlayerViewController.start(source: self, videoUrl: url)
                            } else {
                                AnalysisViewController.start(source: self, videoUrl: url)
                            }
                        }
                    } else {
                        DialogUtil.showAlert(viewController: self, title: nil, message: errorMessage)
                    }
                }
            } else {
                DialogUtil.showAlert(viewController: self, title: nil, message: "invalid id")
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(alert, animated: true)
    }
    
    @IBAction func pickImageSource(_ sender: Any) {
        let picker = UIImagePickerController()
        picker.delegate = self
//        picker.allowsEditing = true
        picker.mediaTypes = ["public.image"]
        picker.sourceType = UIImagePickerController.SourceType.savedPhotosAlbum
        present(picker, animated: true)
    }
}

extension HomeViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        if picker.mediaTypes.contains("public.image") {
            let key: UIImagePickerController.InfoKey
            if picker.allowsEditing {
                key = UIImagePickerController.InfoKey.editedImage
            } else {
                key = UIImagePickerController.InfoKey.originalImage
            }
            guard let image = info[key] as? UIImage else {
                return
            }
            ImageViewController.start(source: self, imageSource: image)
        } else {
            guard let url = info[UIImagePickerController.InfoKey.mediaURL] as? NSURL else {
                return
            }
            switch pickerIdentifier {
            case "analyze":
                do {
                    let videoUrl = try sourceManager.copyVideoToDocument(sourceUrl: url.absoluteURL!, targetName: "analyze.mp4")
                    AnalysisViewController.start(source: self, videoUrl: videoUrl)
                } catch {
                    DialogUtil.showAlert(viewController: self, title: nil, message: error.localizedDescription)
                }
                break
            default:
                VideoPlayerViewController.start(source: self, videoUrl: url.absoluteURL!)
                break
            }
            pickerIdentifier = nil
        }
    }
}
