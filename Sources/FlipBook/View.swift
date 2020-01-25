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
    
    func fb_makeViewSnapshot() -> Image? {
        let wasHidden = isHidden
        let wantedLayer = wantsLayer
        
        isHidden = false
        wantsLayer = true
        
        let scale = window?.backingScaleFactor ?? 1.0
        
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        let imageRepresentation = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                   pixelsWide: width,
                                                   pixelsHigh: height,
                                                   bitsPerSample: 8,
                                                   samplesPerPixel: 4,
                                                   hasAlpha: true,
                                                   isPlanar: false,
                                                   colorSpaceName: NSDeviceRGBColorSpace,
                                                   bytesPerRow: 0,
                                                   bitsPerPixel: 0)
        imageRepresentation?.size = bounds.size

        guard let imgRep = imageRepresentation, let context = NSGraphicsContext(bitmapImageRep: imgRep) else {
            return nil
        }

        render(in: context.cgContext)

        let image = NSImage(cgImage: imageRepresentation.cgImage!, size: bounds.size)
        
        wantsLayer = wantedLayer
        isHidden = wasHidden
        return image
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
