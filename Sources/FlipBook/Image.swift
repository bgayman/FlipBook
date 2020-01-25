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
    
    var jpegRep: Data? {
        guard let bits = self.representations.first as? NSBitmapImageRep else { return nil }
        return bits.representation(using: .jpeg, properties: [:])
    }
}

#else
import UIKit
public typealias Image = UIImage
extension Image {
    var cgI: CGImage? {
        return cgImage
    }
    
    var jpegRep: Data? {
        jpegData(compressionQuality: 1.0)
    }
}

#endif
