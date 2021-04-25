//
//  NotificationName.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/15.
//

import Foundation

enum NotificationName: String {
    case settingUpdated
    
    func nsName() -> NSNotification.Name {
        return NSNotification.Name(rawValue)
    }
}
