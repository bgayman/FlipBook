//
//  FlipBookGIFWriter.swift
//  
//
//  Created by Brad Gayman on 1/25/20.
//

import AVFoundation
import ImageIO
import MobileCoreServices

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
    
    // MARK: - Private Properties -
    
    /// Queue on which gif writing takes place
    private static let queue = DispatchQueue(label: "com.FlipBook.gif.writer.queue", attributes: .concurrent)
    
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
    ///   - delay: time in seconds gif should wait before animating
    ///   - loop: number of times gif should animate. Value of 0 will cause gif to repeat indefinately **Default** 0
    ///   - progress: closure called when progress is made while creating gif. Called from background thread.
    ///   - completion: closure called after gif has been composed. Called from background thread.
    public func makeGIF(_ images: [Image], delay: CGFloat = 0.0, loop: Int = 0, progress: ((CGFloat) -> Void)?, completion: @escaping (Result<URL, Error>) -> Void) {
        var images: [Image?] = images
        let count = images.count
        Self.queue.async { [weak self] in
            guard let self = self else { return }
            let gifSettings = [
                kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: loop]
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
                    if let cgImage = image?.cgI {
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
