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
import CoreImage
#if os(OSX)
import AppKit
#else
import UIKit
import ReplayKit
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
        case livePhoto(PHLivePhoto, LivePhotoResources)
        
        /// Animated gif with its associated `URL`
        case gif(URL)
        
        /// The url of a video or animated gif. If the asset is a live photo `assetURL` is `nil`
        public var assetURL: URL? {
            switch self {
            case .video(let url): return url
            case .livePhoto: return nil
            case .gif(let url): return url
            }
        }
        
        /// The Live Photo of a live photo asset. If the asset is a gif or video `livePhoto` is `nil`
        public var livePhoto: PHLivePhoto? {
            switch self {
            case .video: return nil
            case .livePhoto(let lp, _): return lp
            case .gif: return nil
            }
        }
        
        /// The live photo resources of a live photo asset. If the asset is a gif or video `livePhotoResources` is `nil`
        public var livePhotoResources: LivePhotoResources? {
            switch self {
            case .video: return nil
            case .livePhoto(_, let resources): return resources
            case .gif: return nil
            }
        }
    }
    
    /// Enum that represents the different types of assets that can be created
    public enum AssetType: Equatable {
        
        /// `AssetType` that represents a conversion to an `.mov` video
        case video
        
        /// `AssetType` that represents a conversion to a Live Photo with an optional image that represents the still image of the Live Photo if associated type is `nil` the first frame is used
        case livePhoto(Image?)
        
        /// `AssetType` that represents a conversion to an animated `.gif`
        case gif
        
        public static func == (lhs: AssetType, rhs: AssetType) -> Bool {
            switch (lhs, rhs) {
            case (.video, .video): return true
            case (.gif, .gif): return true
            case let (.livePhoto(imgLHS), .livePhoto(imgRHS)): return imgLHS == imgRHS
            default: return false
            }
        }
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
        let size = NSScreen.main?.frame.size ?? CGSize(width: 400.0, height: 300.0)
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        return CGSize(width: size.width * scale, height: size.height * scale)
        #else
        let size = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        return CGSize(width: size.width * scale, height: size.height * scale)
        #endif
    }()
    
    /// The frame rate of a recording without a `startDate` and `endDate`.
    /// **Note** this value is ignored if both `startDate` and `endDate` are non-null. Also not, full framerate gifs can be memory intensive.
    /// **Default** is 60 frames per second
    public var preferredFramesPerSecond: Int = 60
    
    /// The URL for where the video is written
    /// **Default** is `"FlipBook.mov` in caches directory
    public lazy var fileOutputURL: URL? = self.makeFileOutputURL()
    
    /// The `Date` for when the recording started
    public var startDate: Date?
    
    /// The `Date` for when the recording stopped
    public var endDate: Date?
    
    /// The amount images in animated gifs should be scaled by. Fullsize gif images can be memory intensive. **Default** `0.5`
    public var gifImageScale: Float = 0.5
        
    // MARK: - Internal Properties -
    
    /// The images that compose the frames of the final video
    internal var frames = [Image?]()
    
    /// The queue on which video asset writing is done
    internal let queue = DispatchQueue(label: "com.FlipBook.asset.writer.queue")
    
    /// The video writer input for the asset writer
    internal var videoInput: AVAssetWriterInput?
    
    /// The input pixel buffer adaptor for the asset writer
    internal var adapter: AVAssetWriterInputPixelBufferAdaptor?
    
    /// The writer used for making gifs
    internal lazy var gifWriter = FlipBookGIFWriter(fileOutputURL: self.makeFileOutputURL(fileName: "FlipBook.gif"))
    
    /// The writer used for making Live Photos
    internal lazy var livePhotoWriter = FlipBookLivePhotoWriter()
    
    /// The video editor used for making core animation compositions
    internal lazy var coreAnimationVideoEditor = FlipBookCoreAnimationVideoEditor()
    
    /// The core image context
    internal lazy var ciContext = CIContext()
    
    #if os(iOS)
    internal lazy var rpScreenWriter = RPScreenWriter()
    #endif
    
    // MARK: - Public Methods -
    
    /// Appends image to collection images to be written to video
    /// - Parameter image: image to be written to video
    public func writeFrame(_ image: Image) {
        frames.append(image)
    }
    
    #if os(iOS)
    /// Appends a sample buffer to the specified input
    /// - Parameters:
    ///   - sampleBuffer: The sample buffer to be appended
    ///   - type: The type of the sample buffer to be appended
    public func append(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        rpScreenWriter.writeBuffer(sampleBuffer, rpSampleType: type)
    }
    
    /// Ends live capture driven by `ReplayKit`
    /// - Parameters:
    ///   - assetType: determines what type of asset is created. **Default** is video.
    ///   - compositionAnimation: optional closure for adding `AVVideoCompositionCoreAnimationTool` composition animations. Add `CALayer`s as sublayers to the passed in `CALayer`. Then trigger animations with a `beginTime` of `AVCoreAnimationBeginTimeAtZero`. *Reminder that `CALayer` origin for `AVVideoCompositionCoreAnimationTool` is lower left  for `UIKit` setting `isGeometryFlipped = true is suggested* **Default is `nil`**
    ///   - progress: closure that is called with a `CGFloat` representing the progress of video generation. `CGFloat` is in the range `(0.0 ... 1.0)`. `progress` will be called from a background thread
    ///   - completion: closure that is called when the video has been created with the `URL` for the created video. `completion` will be called from a background thread
    public func endLiveCapture(assetType: AssetType = .video,
                               compositionAnimation: ((CALayer) -> Void)? = nil,
                               progress: ((CGFloat) -> Void)?,
                               completion: @escaping (Result<Asset, Error>) -> Void) {
        endLiveCaptureAndWrite { [weak self] (result) in
            guard let self = self else {
                completion(.failure(FlipBookAssetWriterError.unknownError))
                return
            }
            switch result {
            case .success(let url):
                if let animation = compositionAnimation {
                    self.coreAnimationVideoEditor.preferredFramesPerSecond = self.preferredFramesPerSecond
                    self.coreAnimationVideoEditor.makeVideo(fromVideoAt: url, animation: animation, progress: {prog in progress?(prog * 0.75) }) { [weak self] (result) in
                        guard let self = self else {
                            completion(.failure(FlipBookAssetWriterError.unknownError))
                            return
                        }
                        switch result {
                        case .success(let url):
                            switch assetType {
                            case .video:
                                completion(.success(.video(url)))
                            case .livePhoto(let img):
                                // Make image URL for still aspect of Live Photo
                                let imageURL: URL?
                                if let image = img, let jpgData = image.jpegRep, let url = self.makeFileOutputURL(fileName: "img.jpg") {
                                    try? jpgData.write(to: url, options: [.atomic])
                                    imageURL = url
                                } else {
                                    imageURL = try? self.livePhotoWriter.makeKeyPhoto(from: url, percent: 0.0)
                                }
                                self.livePhotoWriter.make(from: imageURL, videoURL: url, progress: { prog in progress?(prog) }, completion: { result in
                                    switch result {
                                    case .success(let (livePhoto, resources)):
                                        completion(.success(.livePhoto(livePhoto, resources)))
                                    case .failure(let error):
                                        completion(.failure(error))
                                    }
                                })
                            case .gif:
                                self.makeFrames(from: url, progress: { (prog) in
                                    progress?(0.75 + prog * 0.125)
                                }, completion: { [weak self] images in
                                    guard let self = self, let gWriter = self.gifWriter, self.preferredFramesPerSecond > 0 else {
                                        completion(.failure(FlipBookAssetWriterError.unknownError))
                                        return
                                    }
                                    // Make the gif
                                    gWriter.makeGIF(images.map(Image.makeImage),
                                                    delay: CGFloat(1.0) / CGFloat(self.preferredFramesPerSecond),
                                                    sizeRatio: self.gifImageScale,
                                                    progress: { prog in progress?(0.875 + prog * 0.125) },
                                                    completion: { result in
                                                        switch result {
                                                        case .success(let url):
                                                            completion(.success(.gif(url)))
                                                        case .failure(let error):
                                                            completion(.failure(error))
                                                        }
                                    })
                                })
                            }
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                } else {
                    switch assetType {
                    case .video:
                        completion(.success(.video(url)))
                    case .livePhoto(let img):
                        let imageURL: URL?
                        // Make image URL for still aspect of Live Photo
                        if let image = img, let jpgData = image.jpegRep, let url = self.makeFileOutputURL(fileName: "img.jpg") {
                            try? jpgData.write(to: url, options: [.atomic])
                            imageURL = url
                        } else {
                            imageURL = try? self.livePhotoWriter.makeKeyPhoto(from: url, percent: 0.0)
                        }
                        self.livePhotoWriter.make(from: imageURL, videoURL: url, progress: { prog in progress?(prog) }, completion: { result in
                            switch result {
                            case .success(let (livePhoto, resources)):
                                completion(.success(.livePhoto(livePhoto, resources)))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        })
                    case .gif:
                        self.makeFrames(from: url, progress: { (prog) in
                            progress?(prog * 0.5)
                        }, completion: { [weak self] images in
                            guard let self = self, let gWriter = self.gifWriter, self.preferredFramesPerSecond > 0 else {
                                completion(.failure(FlipBookAssetWriterError.unknownError))
                                return
                            }
                            // Make the gif
                            gWriter.makeGIF(images.map(Image.makeImage),
                                            delay: CGFloat(1.0) / CGFloat(self.preferredFramesPerSecond),
                                            sizeRatio: self.gifImageScale,
                                            progress: { prog in progress?(0.5 + prog * 0.5) },
                                            completion: { result in
                                                switch result {
                                                case .success(let url):
                                                    completion(.success(.gif(url)))
                                                case .failure(let error):
                                                    completion(.failure(error))
                                                }
                            })
                        })
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
            
        }
    }
    #endif
    
    /// Makes asset from array of `Image`s and writes to disk at `fileOutputURL`
    /// - Parameters:
    ///   - images: images that comprise the video
    ///   - assetType: determines what type of asset is created. **Default** is video.
    ///   - compositionAnimation: optional closure for adding `AVVideoCompositionCoreAnimationTool` composition animations. Add `CALayer`s as sublayers to the passed in `CALayer`. Then trigger animations with a `beginTime` of `AVCoreAnimationBeginTimeAtZero`. *Reminder that `CALayer` origin for `AVVideoCompositionCoreAnimationTool` is lower left  for `UIKit` setting `isGeometryFlipped = true is suggested* **Default is `nil`**
    ///   - progress: closure that is called with a `CGFloat` representing the progress of video generation. `CGFloat` is in the range `(0.0 ... 1.0)`. `progress` will be called from a background thread
    ///   - completion: closure that is called when the video has been created with the `URL` for the created video. `completion` will be called from a background thread
    public func createAsset(from images: [Image],
                            assetType: AssetType = .video,
                            compositionAnimation: ((CALayer) -> Void)? = nil,
                            progress: ((CGFloat) -> Void)?,
                            completion: @escaping (Result<Asset, Error>) -> Void) {
        frames = images
        createVideoFromCapturedFrames(assetType: assetType, compositionAnimation: compositionAnimation, progress: progress, completion: completion)
    }
    
    /// Makes asset from the images added using `writeFrame(_ image: Image)`
    /// - Parameters:
    ///   - assetType: determines what type of asset is created. **Default** is video.
    ///   - compositionAnimation: optional closure for adding `AVVideoCompositionCoreAnimationTool` composition animations. Add `CALayer`s as sublayers to the passed in `CALayer`. Then trigger animations with a `beginTime` of `AVCoreAnimationBeginTimeAtZero`. *Reminder that `CALayer` origin for `AVVideoCompositionCoreAnimationTool` is lower left  for `UIKit` setting `isGeometryFlipped = true is suggested* **Default is `nil`**
    ///   - progress: closure that is called with a `CGFloat` representing the progress of video generation. `CGFloat` is in the range `(0.0 ... 1.0)`. `progress` will be called from a background thread
    ///   - completion: closure that is called when the video has been created with the `URL` for the created video. `completion` will be called from a background thread
    public func createVideoFromCapturedFrames(assetType: AssetType = .video,
                                              compositionAnimation: ((CALayer) -> Void)? = nil,
                                              progress: ((CGFloat) -> Void)?,
                                              completion: @escaping (Result<Asset, Error>) -> Void) {
        guard frames.isEmpty == false else {
            completion(.failure(FlipBookAssetWriterError.noFrames))
            return
        }
        switch assetType {

        // Handle Video
        case .video:
            
            // Begin by writing the video
            writeVideo(progress: { prog in
                let scale: CGFloat = compositionAnimation == nil ? 1.0 : 0.5
                progress?(prog * scale)
            }, completion: { [weak self] result in
                switch result {
                case .success(let url):
                    
                    // If we have to do a composition do that
                    if let compositionAnimation = compositionAnimation {
                        self?.coreAnimationVideoEditor.preferredFramesPerSecond = self?.preferredFramesPerSecond ?? 60
                        self?.coreAnimationVideoEditor.makeVideo(fromVideoAt: url, animation: compositionAnimation, progress: { (prog) in
                            progress?(0.5 + prog * 0.5)
                        }, completion: { result in
                            // Handle the composition result
                            switch result {
                            case .success(let url):
                                completion(.success(.video(url)))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        })
                    } else {

                        // No composition return the video
                        completion(.success(.video(url)))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            })

        // Handle Live Photo
        case .livePhoto(let img):
            let image: Image? = img ?? frames[0]
            let imageURL: URL?
        
            // Make image URL for still aspect of Live Photo
            if let jpgData = image?.jpegRep, let url = makeFileOutputURL(fileName: "img.jpg") {
                try? jpgData.write(to: url, options: [.atomic])
                imageURL = url
            } else {
                imageURL = nil
            }
            
            // Write the video
            writeVideo(progress: { (prog) in
                let scale: CGFloat = compositionAnimation == nil ? 0.5 : 0.333333
                progress?(prog * scale)
            }, completion: { [weak self] result in
                guard let self = self else {
                    completion(.failure(FlipBookAssetWriterError.unknownError))
                    return
                }
                switch result {
                case .success(let url):
                    
                    // If we have a composition make that
                    if let composition = compositionAnimation {
                        self.coreAnimationVideoEditor.preferredFramesPerSecond = self.preferredFramesPerSecond
                        self.coreAnimationVideoEditor.makeVideo(fromVideoAt: url, animation: composition, progress: { (prog) in
                            progress?(0.333333 + prog * 0.333333)
                        }, completion: { [weak self] result in
                            switch result {
                            case .success(let url):
                                
                                // Composition finished make Live Photo from image and video
                                self?.livePhotoWriter.makeLivePhoto(from: imageURL, videoURL: url, progress: { (prog) in
                                    progress?(0.66666666 + prog * 0.333333)
                                }, completion: { result in
                                    
                                    // Handle Live Photo result
                                    switch result {
                                    case .success(let (livePhoto, resources)):
                                        completion(.success(.livePhoto(livePhoto, resources)))
                                    case .failure(let error):
                                        completion(.failure(error))
                                    }
                                })
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        })
                    } else {
                        
                        // No composition make Live Photo from video and image
                        self.livePhotoWriter.makeLivePhoto(from: imageURL, videoURL: url, progress: { (prog) in
                            progress?(0.5 + prog * 0.5)
                        }, completion: { result in
                            
                            // Handle Live Photo result
                            switch result {
                            case .success(let (livePhoto, resources)):
                                completion(.success(.livePhoto(livePhoto, resources)))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        })
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            })

        // Handle GIF
        case .gif:
            guard let gWriter = self.gifWriter else {
                completion(.failure(FlipBookAssetWriterError.couldNotWriteAsset))
                return
            }
            if let composition = compositionAnimation {
                coreAnimationVideoEditor.preferredFramesPerSecond = preferredFramesPerSecond
                
                // Write video
                writeVideo(progress: { (prog) in
                    progress?(prog * 0.25)
                }, completion: { [weak self] result in
                    guard let self = self else {
                        completion(.failure(FlipBookAssetWriterError.unknownError))
                        return
                    }
                    switch result {
                    case .success(let url):
                        
                        // Add composition
                        self.coreAnimationVideoEditor.makeVideo(fromVideoAt: url, animation: composition, progress: { (prog) in
                            progress?(0.25 + prog * 0.25)
                        }, completion: { [weak self] result in
                            guard let self = self else {
                                completion(.failure(FlipBookAssetWriterError.unknownError))
                                return
                            }
                            switch result {
                            case .success(let url):
                                
                                // Get the frames
                                DispatchQueue.global().async {
                                    self.makeFrames(from: url, progress: { (prog) in
                                        progress?(0.50 + prog * 0.25)
                                    }, completion: { [weak self] images in
                                        guard images.isEmpty == false,
                                              let self = self,
                                              let gWriter = self.gifWriter,
                                              self.preferredFramesPerSecond > 0 else {
                                            completion(.failure(FlipBookAssetWriterError.unknownError))
                                            return
                                        }
                                        
                                        // Make the gif
                                        gWriter.makeGIF(images.map(Image.makeImage),
                                                        delay: CGFloat(1.0) / CGFloat(self.preferredFramesPerSecond),
                                                        sizeRatio: self.gifImageScale,
                                                        progress: { prog in progress?(0.75 + prog * 0.25) },
                                                        completion: { result in
                                                            switch result {
                                                            case .success(let url):
                                                                completion(.success(.gif(url)))
                                                            case .failure(let error):
                                                                completion(.failure(error))
                                                            }
                                        })
                                    })
                                }
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        })
                    case .failure(let error):
                        completion(.failure(error))
                    }
                })
            } else {
                
                // No composition so make GIF directly
                
                // Make sure preferredFramesPerSecond is greater than 0
                guard preferredFramesPerSecond > 0 else {
                    completion(.failure(FlipBookAssetWriterError.couldNotWriteAsset))
                    return
                }
                gWriter.makeGIF(frames.compactMap { $0 },
                                delay: CGFloat(1.0) / CGFloat(preferredFramesPerSecond),
                                sizeRatio: gifImageScale,
                                progress: progress,
                                completion: { (result) in
                                    switch result {
                                    case .success(let url):
                                        completion(.success(.gif(url)))
                                    case .failure(let error):
                                        completion(.failure(error))
                                    }
                })
                frames = []
            }
            
        }
    }
    
    /// Gets frames as `CGImage` from a video asset
    /// - Parameters:
    ///   - videoURL: The `URL` where the video is located
    ///   - progress: A closure that is called when image generator makes progress. Called from a background thread.
    ///   - completion: A closure called when image generation is complete. Called from a background thread.
    public func makeFrames(from videoURL: URL,
                             progress: ((CGFloat) -> Void)?,
                             completion: @escaping ([CGImage]) -> Void) {
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first,
              let videoReader = try? AVAssetReader(asset: asset) else {
            completion([])
            return
        }
        
        let videoReaderSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA as NSNumber
        ]
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
        videoReader.add(videoReaderOutput)
        let duration = videoTrack.timeRange.duration.seconds
        let frameCount = Int(duration * Double(videoTrack.nominalFrameRate) + 0.5)
        var currentFrameCount = 0
        if videoReader.startReading() {
            var sampleBuffers = [CMSampleBuffer]()
            while let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() {
                currentFrameCount += 1
                sampleBuffers.append(sampleBuffer)
                progress?(CGFloat(currentFrameCount) / CGFloat(frameCount))
            }
            let cgImages = sampleBuffers
                .compactMap { CMSampleBufferGetImageBuffer($0) }
                .map { CIImage(cvImageBuffer: $0) }
                .compactMap { ciContext.createCGImage($0, from: $0.extent) }
            completion(cgImages)
        } else {
            completion([])
        }
    }
        
    // MARK: - Internal Methods -
    
    /// Function that returns the default file url for the generated video
    internal func makeFileOutputURL(fileName: String = "FlipBook.mov") -> URL? {
        do {
            var cachesDirectory: URL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            cachesDirectory.appendPathComponent(fileName)
            if FileManager.default.fileExists(atPath: cachesDirectory.path) {
                try FileManager.default.removeItem(atPath: cachesDirectory.path)
            }
            return cachesDirectory
        } catch {
            print(error)
            return nil
        }
    }
    
    /// Function that returns a configured `AVAssetWriter`
    internal func makeWriter() throws -> AVAssetWriter {
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
        
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height
        ]
        
        if let inp = self.videoInput {
            adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: attributes)
            writer.add(inp)
        }
        videoInput?.expectsMediaDataInRealTime = true
        
        return writer
    }
    
    /// Writes `frames` to video
    /// - Parameters:
    ///   - progress: Closure called when progress is made writing video. Called from background thread.
    ///   - completion: Closure called when video is done writing. Called from background thread.
    internal func writeVideo(progress: ((CGFloat) -> Void)?, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let fileURL = self.fileOutputURL else {
            completion(.failure(FlipBookAssetWriterError.couldNotWriteAsset))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(atPath: fileURL.path)
            }
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
                        while self.videoInput?.isReadyForMoreMediaData == false {
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
                
                self.videoInput?.markAsFinished()
                writer.finishWriting {
                    self.frames = []
                    completion(.success(fileURL))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    /// Ends the realtime writing of sample buffers and writes to `fileOutputPath`
    /// - Parameter completion: Closure called when writing is finished
    internal func endLiveCaptureAndWrite(completion: @escaping (Result<URL, Error>) -> Void) {
        rpScreenWriter.finishWriting { (url, error) in
            if let url = url {
                completion(.success(url))
            } else if let error = error{
                completion(.failure(error))
            } else {
                completion(.failure(FlipBookAssetWriterError.unknownError))
            }
        }
    }
    
    /// Helper function that calculates the frame rate if `startDate` and `endDate` are set. Otherwise it returns `preferredFramesPerSecond`
    internal func makeFrameRate() -> Int {
        let startTimeDiff = startDate?.timeIntervalSinceNow ?? 0
        let endTimeDiff = endDate?.timeIntervalSinceNow ?? 0
        let diff = endTimeDiff - startTimeDiff
        let frameRate: Int
        if diff != 0 {
            frameRate = Int(Double(frames.count) / diff + 0.5)
        } else {
            frameRate = preferredFramesPerSecond
        }
        return frameRate
    }
}

// MARK: - CGImage + CVPixelBuffer -

/// Adds helper functions for converting from `CGImage` to `CVPixelBuffer`
internal extension CGImage {
  
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
    
    func makeCMSampleBuffer(_ frameIdx: Int) -> CMSampleBuffer? {
        guard let pixelBuffer = makePixelBuffer() else { return nil }
        var newSampleBuffer: CMSampleBuffer? = nil
        let time = CMTime(value: CMTimeValue(frameIdx), timescale: 100)
        var timimgInfo: CMSampleTimingInfo = CMSampleTimingInfo(duration: time,
                                                                presentationTimeStamp: time,
                                                                decodeTimeStamp: time)
        var videoInfo: CMVideoFormatDescription? = nil
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &videoInfo)
        guard let videoI = videoInfo else { return nil }
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                           imageBuffer: pixelBuffer,
                                           dataReady: true,
                                           makeDataReadyCallback: nil,
                                           refcon: nil,
                                           formatDescription: videoI,
                                           sampleTiming: &timimgInfo,
                                           sampleBufferOut: &newSampleBuffer)
        return newSampleBuffer
    }
}
