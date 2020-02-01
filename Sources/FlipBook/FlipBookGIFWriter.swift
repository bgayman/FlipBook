//
//  FlipBookGIFWriter.swift
//  
//
//  Created by Brad Gayman on 1/25/20.
//

import AVFoundation
import ImageIO
#if !os(macOS)
import MobileCoreServices
#else
import CoreServices
#endif

// MARK: - FlipBookGIFWriter -

/// Class that converts an array of images to animated gif
public final class FlipBookGIFWriter: NSObject {
    
    // MARK: - Types -
    
    /// Errors that `FlipBookGIFWriter` can throw
    public enum FlipBookGIFWriterError: Error {
        
        /// Could not create gif destination for supplied file `URL`
        case couldNotCreateDestination
        
        /// Failed to finalize writing for gif
        case failedToFinalizeDestination
    }
    
    // MARK: - Public Properties -

    /// The file `URL` that the gif is written to
    public let fileOutputURL: URL
    
    // MARK: - Internal Properties -
    
    /// Queue on which gif writing takes place
    internal static let queue = DispatchQueue(label: "com.FlipBook.gif.writer.queue", attributes: .concurrent)
    
    // MARK: - Init / Deinit -
    
    /// Creates an instance of `FlipBookGIFWriter`
    /// - Parameter fileOutputURL: The file `URL` that the gif is written to
    public init?(fileOutputURL: URL?) {
        guard let fileOutputURL = fileOutputURL else {
            return nil
        }
        self.fileOutputURL = fileOutputURL
    }
    
    // MARK: - Public Methods -
    
    /// Function that takes an array of images and composes an animated gif with them
    /// - Parameters:
    ///   - images: images that comprise the gif
    ///   - delay: time in seconds gif should wait before moving to next frame. **Default** 0.02
    ///   - loop: number of times gif should animate. Value of 0 will cause gif to repeat indefinately **Default** 0
    ///   - sizeRatio: scale that image should be resized to when making gif **Default** 1.0
    ///   - progress: closure called when progress is made while creating gif. Called from background thread.
    ///   - completion: closure called after gif has been composed. Called from background thread.
    public func makeGIF(_ images: [Image], delay: CGFloat = 0.02, loop: Int = 0, sizeRatio: Float = 1.0, progress: ((CGFloat) -> Void)?, completion: @escaping (Result<URL, Error>) -> Void) {
        var images: [Image?] = images
        let count = images.count
        Self.queue.async { [weak self] in
            autoreleasepool {
                guard let self = self else { return }
                let gifSettings = [
                    kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: loop,
                                                              kCGImagePropertyGIFHasGlobalColorMap as String: false]
                ]
                let imageSettings = [
                    kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: delay]
                ]
                guard let destination = CGImageDestinationCreateWithURL(self.fileOutputURL as CFURL, kUTTypeGIF, count, nil) else {
                    completion(.failure(FlipBookGIFWriterError.couldNotCreateDestination))
                    return
                }
                
                CGImageDestinationSetProperties(destination, gifSettings as CFDictionary)
                for index in images.indices {
                    autoreleasepool {
                        let image = images[index]
                        if let cgImage = image?.cgI?.resize(with: sizeRatio) {
                            CGImageDestinationAddImage(destination, cgImage, imageSettings as CFDictionary)
                        }
                        images[index] = nil
                        progress?(CGFloat(index + 1) / CGFloat(count))
                    }
                }
                
                if CGImageDestinationFinalize(destination) == false {
                    completion(.failure(FlipBookGIFWriterError.couldNotCreateDestination))
                } else {
                    completion(.success(self.fileOutputURL))
                }
            }
        }
    }
    
    /// Determines the frame rate of a gif by looking at the `delay` of the first image
    /// - Parameter gifURL: The file `URL` where the gif is located.
    /// - Returns: The frame rate as an `Int` or `nil` if data at url was invalid
    public func makeFrameRate(_ gifURL: URL) -> Int? {
        guard let gifData = try? Data(contentsOf: gifURL),
              let source =  CGImageSourceCreateWithData(gifData as CFData, nil) else { return nil }
        let delay = getDelayForImageAtIndex(0, source: source)
        return Int((1.0 / delay) + 0.5)
    }
    
    /// Creates an array of `Image`s that represent the frames of a gif
    /// - Parameter gifURL: The file `URL` where the gif is located.
    /// - Returns: The frames rate as an `Int` or `nil` if data at url was invalid
    public func makeImages(_ gifURL: URL) -> [Image]? {
        guard let gifData = try? Data(contentsOf: gifURL),
              let source =  CGImageSourceCreateWithData(gifData as CFData, nil) else { return nil }
        var images = [Image]()
        let imageCount = CGImageSourceGetCount(source)
        for i in 0 ..< imageCount {
            if let image = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(Image.makeImage(cgImage: image))
            }
        }
        return images
    }
    
    /// Determines the delay of the frame of a gif at a given index
    /// - Parameters:
    ///   - index: The index to determine the delay for
    ///   - source: The `CGImageSource` of the gif
    internal func getDelayForImageAtIndex(_ index: Int, source: CGImageSource) -> Double {
        var delay = 0.1

        // Get dictionaries
        let cfProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
        let gifPropertiesPointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 0)
        defer {
            gifPropertiesPointer.deallocate()
        }
        let unsafePointer = Unmanaged.passUnretained(kCGImagePropertyGIFDictionary).toOpaque()
        if CFDictionaryGetValueIfPresent(cfProperties, unsafePointer, gifPropertiesPointer) == false {
            return delay
        }

        let gifProperties: CFDictionary = unsafeBitCast(gifPropertiesPointer.pointee, to: CFDictionary.self)

        // Get delay time
        var delayObject: AnyObject = unsafeBitCast(
            CFDictionaryGetValue(gifProperties,
                Unmanaged.passUnretained(kCGImagePropertyGIFUnclampedDelayTime).toOpaque()),
            to: AnyObject.self)
        if delayObject.doubleValue == 0 {
            delayObject = unsafeBitCast(CFDictionaryGetValue(gifProperties,
                Unmanaged.passUnretained(kCGImagePropertyGIFDelayTime).toOpaque()), to: AnyObject.self)
        }

        if let delayObject = delayObject as? Double, delayObject > 0 {
            delay = delayObject
        } else {
            delay = 0.1
        }

        return delay
    }
}

// MARK: - CGImage + Resize -
/// Add resizing helper function
internal extension CGImage {
    
    /// Resizes image based on ration to natural size
    /// - Parameter ratio: Ration that represents the size of the image relative to its natural size
    func resize(with ratio: Float) -> CGImage? {
        let imageWidth: Int = Int(Float(self.width) * ratio)
        let imageHeight: Int = Int(Float(self.height) * ratio)
        
        guard let colorSpace = self.colorSpace else { return nil }
        guard let context = CGContext(data: nil, width: imageWidth, height: imageHeight, bitsPerComponent: self.bitsPerComponent, bytesPerRow: self.bytesPerRow, space: colorSpace, bitmapInfo: self.alphaInfo.rawValue) else { return nil }
        
        context.interpolationQuality = .low
        context.draw(self, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        
        return context.makeImage()
    }
}
