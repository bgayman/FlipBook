//
//  FlipBookAssetWriter.swift
//  
//
//  Created by Brad Gayman on 1/24/20.
//

import AVFoundation
import CoreGraphics
import VideoToolbox
#if os(OSX)
import AppKit
#else
import UIKit
#endif

// MARK: - FlipBookAssetWriter -

/// Wrapper to AVAssetWriter that converts a collection of images to a video
public final class FlipBookAssetWriter: NSObject {
    
    // MARK: - Types -
    
    /// Errors that can `FlipBookAssetWriter` might throw
    enum FlipBookAssetWriterError: Error {
        
        /// Attempted to create video from 0 images
        case noFrames
        
        /// `FlipBookAssetWriter` was unable to write asset
        case couldNotWriteAsset
    }
    
    // MARK: - Public Properties -

    /// The size of the recording area.
    /// **Default** is the size of the `keyWindow` of the application
    public var size: CGSize = {
        #if os(OSX)
        let size = NSApplication.shared.keyWindow?.frame.size ?? .zero
        let scale = NSApplication.shared.keyWindow?.backingScaleFactor ?? 1.0
        return CGSize(width: size.width * scale, height: size.height * scale)
        #else
        let size = UIApplication.shared.keyWindow?.frame.size
        let scale = UIApplication.shared.keyWindow?.screen.scale ?? 1.0
        return CGSize(width: (size?.width ?? 0) * scale, height: (size?.height ?? 0) * scale)
        #endif
    }()
    
    /// The frame rate of a recording without a `startDate` and `endDate`.
    /// **Note** this value is ignored if both `startDate` and `endDate` are non-null.
    /// **Default** is 60 frames per second
    public var preferredFramesPerSecond: Int = 60
    
    /// The URL for where the video is written
    /// **Default** is `"FlipBook.mov` in caches directory
    public lazy var fileOutputURL: URL = self.makeFileOutputURL()
    
    /// The `Date` for when the recording started
    public var startDate: Date?
    
    /// The `Date` for when the recording stopped
    public var endDate: Date?
    
    // MARK: - Private Properties -
    
    /// The images that compose the frames of the final video
    private var frames = [Image?]()
    
    /// The queue on which video asset writing is done
    private let queue = DispatchQueue(label: "com.FlipBook.asset.writer.queue")
    
    /// The writer input for the asset writer
    private var input: AVAssetWriterInput?
    
    /// The input pixel buffer adaptor for the asset writer
    private var adapter: AVAssetWriterInputPixelBufferAdaptor?
    
    // MARK: - Public Methods -
    
    /// Appends image to collection images to be written to video
    /// - Parameter image: image to be written to video
    public func writeFrame(_ image: Image) {
        frames.append(image)
    }
    
    /// Makes video from array of `Image`s and writes to disk at `fileOutputURL`
    /// - Parameters:
    ///   - images: images that comprise the video
    ///   - progress: closure that is called with a `CGFloat` representing the progress of video generation. `CGFloat` is in the range `(0.0 ... 1.0)`. `progress` will be called from a background thread
    ///   - completion: closure that is called when the video has been created with the `URL` for the created video. `completion` will be called from a background thread
    public func createVideo(from images: [Image], progress: @escaping (CGFloat) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        frames = images
        createVideoFromCapturedFrames(progress: progress, completion: completion)
    }
    
    /// Makes video from the images added using `writeFrame(_ image: Image)`
    /// - Parameters:
    ///   - progress: closure that is called with a `CGFloat` representing the progress of video generation. `CGFloat` is in the range `(0.0 ... 1.0)`. `progress` will be called from a background thread
    ///   - completion: closure that is called when the video has been created with the `URL` for the created video. `completion` will be called from a background thread
    public func createVideoFromCapturedFrames(progress: ((CGFloat) -> Void)?, completion: @escaping (Result<URL, Error>) -> Void) {
        guard frames.isEmpty == false,
              let buffer = frames[0]?.cgImage?.makePixelBuffer() else {
            completion(.failure(FlipBookAssetWriterError.noFrames))
            return
        }
        do {
            let writer = try makeWriter()
            guard writer.startWriting() else {
                completion(.failure(writer.error ?? FlipBookAssetWriterError.couldNotWriteAsset))
                return
            }
            writer.startSession(atSourceTime: .zero)
            guard adapter?.append(buffer, withPresentationTime: .zero) == true else {
                completion(.failure(writer.error ?? FlipBookAssetWriterError.couldNotWriteAsset))
                return
            }
            let frameRate = makeFrameRate()
            
            queue.async {
                var i = 0
                for index in self.frames.indices {
                    autoreleasepool {
                        while self.input?.isReadyForMoreMediaData == false {
                            print("Not ready for more data")
                        }
                        i += 1
                        let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(frameRate))
                        if let buffer = self.frames[index]?.cgImage?.makePixelBuffer() {
                            guard self.adapter?.append(buffer, withPresentationTime: time) == true else {
                                let error = writer.error ?? FlipBookAssetWriterError.couldNotWriteAsset
                                completion(.failure(error))
                                return
                            }
                        }
                        self.frames[index] = nil
                        progress?(CGFloat(index + 1) / CGFloat(self.frames.count))
                    }
                }
                
                self.input?.markAsFinished()
                writer.finishWriting {
                    completion(.success(self.fileOutputURL))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
        
    // MARK: - Internal Methods -
    
    /// Function that returns the default file url for the generated video
    private func makeFileOutputURL() -> URL {
        let cachesDirectory = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
        let fileName = "FlipBook.mov"
        let path  = "\(cachesDirectory)/\(fileName)"
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
        return URL(fileURLWithPath: path)
    }
    
    /// Function that returns a configured `AVAssetWriter`
    private func makeWriter() throws -> AVAssetWriter {
        let writer = try AVAssetWriter(url: fileOutputURL, fileType: .mov)
        let settings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
            ]
        
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.width
        ]
        
        adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input!, sourcePixelBufferAttributes: attributes)
        
        writer.add(input!)
        input?.expectsMediaDataInRealTime = true
        return writer
    }
    
    /// Helper function that calculates the frame rate if `startDate` and `endDate` are set otherwise returns `preferredFramesPerSecond`
    private func makeFrameRate() -> Int {
        let startTimeDiff = startDate?.timeIntervalSinceNow ?? 0
        let endTimeDiff = endDate?.timeIntervalSinceNow ?? 0
        let diff = endTimeDiff - startTimeDiff
        let frameRate: Int
        if diff != 0 {
            frameRate = Int(Double(frames.count) / diff)
        } else {
            frameRate = preferredFramesPerSecond
        }
        return frameRate
    }
}

// MARK: - CGImage + CVPixelBuffer -

/// Adds helper function for converting from `CGImage` to `CVPixelBuffer`
private extension CGImage {
  
    /// Creates  and returns a pixel buffer for the image
    func makePixelBuffer() -> CVPixelBuffer? {
        return pixelBuffer(width: self.width,
                           height: self.height,
                           pixelFormatType: kCVPixelFormatType_32ARGB,
                           colorSpace: CGColorSpaceCreateDeviceRGB(),
                           alphaInfo: .noneSkipFirst)
    }
    
    
    /// Creates  and returns a pixel buffer for the image
    /// - Parameters:
    ///   - width: The desired width of the image represented by the image buffer
    ///   - height: The desired height of the image represented by the image buffer
    ///   - pixelFormatType: The desired pixel format type used by the image buffer
    ///   - colorSpace: The desired color space used by the image buffer
    ///   - alphaInfo: The desired alpha info used by the image buffer
    func pixelBuffer(width: Int, height: Int,
                     pixelFormatType: OSType,
                     colorSpace: CGColorSpace,
                     alphaInfo: CGImageAlphaInfo) -> CVPixelBuffer? {
        var maybePixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         pixelFormatType,
                                         attrs as CFDictionary,
                                         &maybePixelBuffer)

        guard status == kCVReturnSuccess, let pixelBuffer = maybePixelBuffer else {
            return nil
        }

        let flags = CVPixelBufferLockFlags(rawValue: 0)
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(pixelBuffer, flags) else {
            return nil
        }
        
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, flags) }

        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: colorSpace,
                                      bitmapInfo: alphaInfo.rawValue)
        else {
            return nil
        }

        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
