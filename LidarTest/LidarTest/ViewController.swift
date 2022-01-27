//
//  ViewController.swift
//  LidarTest
//
//  Created by WuLei on 2021/9/27.
//

import UIKit
import RealityKit

class ViewController: UIViewController {
  
  @IBOutlet var arView: ARView!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    arView.addGestureRecognizer(tapRecognizer)
  }
  
  @objc
  func handleTap(_ sneder: UITapGestureRecognizer) {
    // Load the "Box" scene from the "Experience" Reality File
    let boxAnchor = try! Experience.loadBox()
    // Add the box anchor to the scene
    arView.scene.anchors.append(boxAnchor)
    print("tapped, box appended: \(boxAnchor)")
  }
}
