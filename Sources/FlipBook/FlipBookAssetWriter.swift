//
//  FlipBookAssetWriter.swift
//  
//
//  Created by Brad Gayman on 1/24/20.
//

import AVFoundation
import CoreGraphics
import VideoToolbox
import Photos
#if os(OSX)
import AppKit
#else
import UIKit
#endif

// MARK: - FlipBookAssetWriter -

/// Class that converts a collection of images to an asset
public final class FlipBookAssetWriter: NSObject {
    
    // MARK: - Types -
    
    /// The assets that can be writen
    public enum Asset {
        
        /// video with its associated `URL`
        case video(URL)
        
        /// Live Photo with its associated `PHLivePhoto`
        case livePhoto(PHLivePhoto)
        
        /// Animated gif with its associated `URL`
        case gif(URL)
    }
    
    /// Enum that represents the different types of assets that can be created
    public enum AssetType {
        
        /// `AssetType` that represents a conversion to an `.mov` video
        case video
        
        /// `AssetType` that represents a conversion to a Live Photo with an optional image that represents the still image of the Live Photo if associated type is `nil` the first frame is used
        case livePhoto(Image?)
        
        /// `AssetType` that represents a conversion to an animated `.gif`
        case gif
    }
    
    /// Errors that can `FlipBookAssetWriter` might throw
    public enum FlipBookAssetWriterError: Error {
        
        /// Attempted to create video from 0 images
        case noFrames
        
        /// `FlipBookAssetWriter` was unable to write asset
        case couldNotWriteAsset
        
        /// `FlipBookAssetWriter` failed for an unknown reason
        case unknownError
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
    public lazy var fileOutputURL: URL? = self.makeFileOutputURL()
    
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
    
    /// The writer used for making gifs
    private lazy var gifWriter = FlipBookGIFWriter(fileOutputURL: self.makeFileOutputURL(fileName: "FlipBook.gif"))
    
    /// The writer used for making Live Photos
    private lazy var livePhotoWriter = FlipBookLivePhotoWriter()
    
    // MARK: - Public Methods -
    
    /// Appends image to collection images to be written to video
    /// - Parameter image: image to be written to video
    public func writeFrame(_ image: Image) {
        frames.append(image)
    }
    
    /// Makes asset from array of `Image`s and writes to disk at `fileOutputURL`
    /// - Parameters:
    ///   - images: images that comprise the video
    ///   - assetType: determines what type of asset is created. **Default** is video.
    ///   - progress: closure that is called with a `CGFloat` representing the progress of video generation. `CGFloat` is in the range `(0.0 ... 1.0)`. `progress` will be called from a background thread
    ///   - completion: closure that is called when the video has been created with the `URL` for the created video. `completion` will be called from a background thread
    public func createAsset(from images: [Image], assetType: AssetType = .video,  progress: ((CGFloat) -> Void)?, completion: @escaping (Result<Asset, Error>) -> Void) {
        frames = images
        createVideoFromCapturedFrames(assetType: assetType, progress: progress, completion: completion)
    }
    
    /// Makes asset from the images added using `writeFrame(_ image: Image)`
    /// - Parameters:
    ///   - progress: closure that is called with a `CGFloat` representing the progress of video generation. `CGFloat` is in the range `(0.0 ... 1.0)`. `progress` will be called from a background thread
    ///   - completion: closure that is called when the video has been created with the `URL` for the created video. `completion` will be called from a background thread
    public func createVideoFromCapturedFrames(assetType: AssetType = .video, progress: ((CGFloat) -> Void)?, completion: @escaping (Result<Asset, Error>) -> Void) {
        guard frames.isEmpty == false else {
            completion(.failure(FlipBookAssetWriterError.noFrames))
            return
        }
        switch assetType {

        case .video:
            writeVideo(progress: progress, completion: { result in
                switch result {
                case .success(let url):
                    completion(.success(.video(url)))
                case .failure(let error):
                    completion(.failure(error))
                }
            })

        case .livePhoto(let img):
            let image: Image? = img ?? frames[0]
            let imageURL: URL?
            if let jpgData = image?.jpegRep, let url = makeFileOutputURL(fileName: "img.jpg") {
                try? jpgData.write(to: url, options: [.atomic])
                imageURL = url
            } else {
                imageURL = nil
            }
            writeVideo(progress: { (prog) in
                progress?(prog * 0.5)
            }, completion: { [weak self] result in
                guard let self = self else {
                    completion(.failure(FlipBookAssetWriterError.unknownError))
                    return
                }
                switch result {
                case .success(let url):
                    self.livePhotoWriter.makeLivePhoto(from: imageURL, videoURL: url, progress: { (prog) in
                        progress?(0.5 + prog * 0.5)
                    }, completion: { result in
                        switch result {
                        case .success(let livePhoto, _):
                            completion(.success(.livePhoto(livePhoto)))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    })
                case .failure(let error):
                    completion(.failure(error))
                }
            })

        case .gif:
            gifWriter?.makeGIF(frames.compactMap { $0 },
                               progress: progress,
                               completion: { (result) in
                                switch result {
                                case .success(let url):
                                    completion(.success(.gif(url)))
                                case .failure(let error):
                                    completion(.failure(error))
                                }
            })
        }
    }
        
    // MARK: - Private Methods -
    
    /// Function that returns the default file url for the generated video
    private func makeFileOutputURL(fileName: String = "FlipBook.mov") -> URL? {
        do {
            var cachesDirectory: URL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            cachesDirectory.appendPathComponent(fileName)
            if FileManager.default.fileExists(atPath: cachesDirectory.absoluteString) {
                try FileManager.default.removeItem(atPath: cachesDirectory.absoluteString)
            }
            return cachesDirectory
        } catch {
            print(error)
            return nil
        }
    }
    
    /// Function that returns a configured `AVAssetWriter`
    private func makeWriter() throws -> AVAssetWriter {
        guard let fileURL = self.fileOutputURL else {
            throw FlipBookAssetWriterError.couldNotWriteAsset
        }
        let writer = try AVAssetWriter(url: fileURL, fileType: .mov)
        #if !os(macOS)
        let settings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        #else
        let settings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        #endif
        
        
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
    
    private func writeVideo(progress: ((CGFloat) -> Void)?, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let fileURL = self.fileOutputURL else {
            completion(.failure(FlipBookAssetWriterError.couldNotWriteAsset))
            return
        }
        do {
            let writer = try makeWriter()
            guard writer.startWriting() else {
                completion(.failure(writer.error ?? FlipBookAssetWriterError.couldNotWriteAsset))
                return
            }
            writer.startSession(atSourceTime: .zero)
            let frameRate = makeFrameRate()
            
            queue.async {
                var i = 0
                for index in self.frames.indices {
                    autoreleasepool {
                        while self.input?.isReadyForMoreMediaData == false {
                            print("Not ready for more data")
                        }
                        let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(frameRate))
                        if let buffer = self.frames[index]?.cgI?.makePixelBuffer() {
                            guard self.adapter?.append(buffer, withPresentationTime: time) == true else {
                                let error = writer.error ?? FlipBookAssetWriterError.couldNotWriteAsset
                                completion(.failure(error))
                                return
                            }
                        }
                        self.frames[index] = nil
                        progress?(CGFloat(index + 1) / CGFloat(self.frames.count))
                        i += 1
                    }
                }
                
                self.input?.markAsFinished()
                writer.finishWriting {
                    self.frames = []
                    completion(.success(fileURL))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    /// Helper function that calculates the frame rate if `startDate` and `endDate` are set. Otherwise it returns `preferredFramesPerSecond`
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

/// Adds helper functions for converting from `CGImage` to `CVPixelBuffer`
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
