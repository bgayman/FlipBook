//
//  Screen.swift
//  
//
//  Created by Brad Gayman on 1/24/20.
//

#if os(OSX)
import AppKit
public typealias Screen = NSScreen

extension Screen {
    static var maxFramesPerSecond: Int {
        return 60
    }
}

#else
import UIKit
public typealias Screen = UIScreen

extension Screen {
    static var maxFramesPerSecond: Int {
        if #available(iOS 10.3, *) {
            return UIScreen.main.maximumFramesPerSecond
        } else {
            return 60
        }
    }
}
#endif
