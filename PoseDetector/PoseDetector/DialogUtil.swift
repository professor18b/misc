//
//  DialogUtil.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/6.
//

import UIKit

class DialogUtil {
    static func showAlert(viewController: UIViewController, title: String?, message: String?) {
        if Thread.isMainThread {
            presentAlert(viewController: viewController, title: title, message: message ?? "")
        } else {
            DispatchQueue.main.async {
                presentAlert(viewController: viewController, title: title, message: message ?? "")
            }
        }
    }
    
    private static func presentAlert(viewController: UIViewController, title: String?, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }
}
