//
//  View.swift
//  
//
//  Created by Brad Gayman on 1/24/20.
//

#if os(OSX)
import AppKit
public typealias View = NSView
extension View {
    var scale: CGFloat {
        window?.backingScaleFactor ?? 1.0
    }
}

#else
import UIKit
public typealias View = UIView

extension View {
    
    var scale: CGFloat {
        window?.scale ?? 1.0
    }
    
    func fb_makeViewSnapshot() -> Image? {
        UIGraphicsBeginImageContextWithOptions(frame.size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        layer.presentation()?.render(in: context)
        let rasterizedView = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rasterizedView
    }
}
#endif
