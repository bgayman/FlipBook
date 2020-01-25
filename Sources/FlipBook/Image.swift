//
//  Image.swift
//  
//
//  Created by Brad Gayman on 1/24/20.
//

#if os(OSX)
import AppKit
public typealias Image = NSImage

extension Image {
    var cgI: CGImage? {
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }
}

#else
import UIKit
public typealias Image = UIImage

var cgI: CGImage? {
    return self.cgImage
}
#endif
