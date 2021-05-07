//
//  AuxiliaryLineView.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/30.
//

import UIKit

class AuxiliaryLineView: UIView {
    
    private let lineLayer = CAShapeLayer()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    private func setupLayer() {
        lineLayer.lineCap = .round
        lineLayer.lineWidth = 1.0
        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.strokeColor = UIColor.gray.cgColor
        layer.addSublayer(lineLayer)
    }
}
