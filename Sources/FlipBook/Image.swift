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
    var cgImage: CGImage? {
        return self.cgImage
    }
}

#else
import UIKit
public typealias Image = UIImage
#endif
