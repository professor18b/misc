//
//  BaseViewController.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/23.
//

import UIKit

class BaseViewController: UIViewController {
    
    private var currentSegueArguments: [String: Any]?
    
    func performSegueWithArguments(withIdentifier identifier: String, arguments: [String: Any]) {
        currentSegueArguments = arguments
        self.performSegue(withIdentifier: identifier, sender: self)
    }
    
    func processSegueArguments(arguments: [String: Any]) {
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let arguments = currentSegueArguments {
            guard let destination = segue.destination as? BaseViewController else {
             fatalError("destination not a BaseViewController: \(segue.destination.debugDescription)")
            }
            destination.processSegueArguments(arguments: arguments)
        }
    }
    
    func addSubViewController(viewController: UIViewController) {
        viewController.view.frame = view.bounds
        addChild(viewController)
        viewController.beginAppearanceTransition(true, animated: true)
        view.addSubview(viewController.view)
        viewController.endAppearanceTransition()
        viewController.didMove(toParent: self)
    }
}
