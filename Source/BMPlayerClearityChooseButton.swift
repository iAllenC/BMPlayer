//
//  File.swift
//  Pods
//
//  Created by BrikerMan on 16/5/21.
//
//

import UIKit

class BMPlayerClearityChooseButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        initUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initUI()
    }
    
    func initUI() {
        titleLabel?.font   = UIFont.systemFont(ofSize: 12)
        layer.cornerRadius = 2
        layer.borderWidth  = 1
        layer.borderColor  = UIColor(white: 1, alpha: 0.8).cgColor
        setTitleColor(UIColor(white: 1, alpha: 0.9), for: .normal)
    }
}
