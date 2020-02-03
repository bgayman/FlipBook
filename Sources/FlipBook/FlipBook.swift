//
//  FlipBook.swift
//
//
//  Created by Brad Gayman on 1/24/20.
//

#if os(OSX)
import AppKit
#else
import UIKit
import ReplayKit
#endif

// MARK: - FlipBook -

/// Class that records a view
public final class FlipBook: NSObject {
    
    // MARK: - Types -
    
    /// Enum that represents the errors that `FlipBook` can throw
    public enum FlipBookError: String, Error {
        
        /// Recording is already in progress. Stop current recording before beginning another.
        case recordingInProgress
        
        /// Recording is not availible using `ReplayKit` with `assetType == .gif`
        case recordingNotAvailible
    }

    // MARK: - Public Properties
    
    /// The number of frames per second targetted
    /// **Default** 60 frames per second on macOS and to the `maxFramesPerSecond` of the main screen of the device on iOS
    /// - Will be ignored if `shouldUseReplayKit` is set to true
    public var preferredFramesPerSecond: Int = Screen.maxFramesPerSecond
    
    /// The amount images in animated gifs should be scaled by. Fullsize gif images can be memory intensive. **Default** `0.5`
    public var gifImageScale: Float = 0.5
    
    /// The asset type to be created
    /// **Default** `.video`
    public var assetType: FlipBookAssetWriter.AssetType = .video
    
    /// Boolean that when set to `true` will cause the entire screen to be captured using `ReplayKit` on iOS 11.0+ only and will otherwise be ignored
    public var shouldUseReplayKit: Bool = false
    
    #if os(iOS)
    
    /// The replay kit screen recorder used when `shouldUseReplayKit` is set to `true`
    public lazy var screenRecorder: RPScreenRecorder = {
        let recorder = RPScreenRecorder.shared()
        recorder.isCameraEnabled = false
        recorder.isMicrophoneEnabled = false
        return recorder
    }()
    #endif
    
    // MARK: - Internal Properties -

    /// Asset writer used to convert screenshots into video
    internal let writer = FlipBookAssetWriter()
    
    /// Closure to be called when the asset writing has progressed
    internal var onProgress: ((CGFloat) -> Void)?
    
    /// Closure to be called when compositing video with `CAAnimation`s
    internal var compositionAnimation: ((CALayer) -> Void)?
    
    /// Closure to be called when the video asset stops writing
    internal var onCompletion: ((Result<FlipBookAssetWriter.Asset, Error>) -> Void)?
    
    /// View that is currently being recorded
    internal var sourceView: View?
    
    #if os(OSX)
    
    /// Queue for capturing snapshots for view
    internal var queue: DispatchQueue?
    
    /// Source for capturing snapshots for view
    internal var source: DispatchSourceTimer?
    #else

    /// Display link that drives view snapshotting
    internal var displayLink: CADisplayLink?
    #endif
    
    // MARK: - Public Methods -
    
    /// Starts recording a view
    /// - Parameters:
    ///   - view: view to be recorded. This value is ignored if `shouldUseReplayKit` is set to `true`
    ///   - compositionAnimation: optional closure for adding `AVVideoCompositionCoreAnimationTool` composition animations. Add `CALayer`s as sublayers to the passed in `CALayer`. Then trigger animations with a `beginTime` of `AVCoreAnimationBeginTimeAtZero`. *Reminder that `CALayer` origin for `AVVideoCompositionCoreAnimationTool` is lower left  for `UIKit` setting `isGeometryFlipped = true is suggested* **Default is `nil`**
    ///   - progress: optional closure that is called with a `CGFloat` representing the progress of video generation. `CGFloat` is in the range `(0.0 ... 1.0)`. `progress` is called from the main thread. **Default is `nil`**
    ///   - completion: closure that is called when the video has been created with the `URL` for the created video. `completion` will be called from the main thread
    public func startRecording(_ view: View,
                               compositionAnimation: ((CALayer) -> Void)? = nil,
                               progress: ((CGFloat) -> Void)? = nil,
                               completion: @escaping (Result<FlipBookAssetWriter.Asset, Error>) -> Void) {
        if shouldUseReplayKit {
            #if os(macOS)
            shouldUseReplayKit = false
            startRecording(view, compositionAnimation: compositionAnimation, progress: progress, completion: completion)
            #else
            guard assetType != .gif else {
                completion(.failure(FlipBookError.recordingNotAvailible))
                return
            }
            onProgress = progress
            onCompletion = completion
            writer.gifImageScale = gifImageScale
            writer.preferredFramesPerSecond = preferredFramesPerSecond
            self.compositionAnimation = compositionAnimation
            if #available(iOS 11.0, *) {
                screenRecorder.startCapture(handler: { [weak self] (buffer, type, error) in
                    if let error = error {
                        print(error)
                    }
                    self?.writer.append(buffer, type: type)
                }, completionHandler: { error in
                    guard let error = error else {
                        return
                    }
                    print(error)
                })
            } else {
                shouldUseReplayKit = false
                startRecording(view, compositionAnimation: compositionAnimation, progress: progress, completion: completion)
            }
            #endif
        } else {
            #if os(OSX)
            guard queue == nil else {
                completion(.failure(FlipBookError.recordingInProgress))
                return
            }
            #else
            guard displayLink == nil else {
                completion(.failure(FlipBookError.recordingInProgress))
                return
            }
            #endif
            sourceView = view
            onProgress = progress
            onCompletion = completion
            self.compositionAnimation = compositionAnimation
            writer.size = CGSize(width: view.bounds.size.width * view.scale, height: view.bounds.size.height * view.scale)
            writer.startDate = Date()
            writer.gifImageScale = gifImageScale
            writer.preferredFramesPerSecond = preferredFramesPerSecond
            
            #if os(OSX)
            queue = DispatchQueue.global()
            source = DispatchSource.makeTimerSource(queue: queue)
            source?.schedule(deadline: .now(), repeating: 1.0 / Double(self.preferredFramesPerSecond))
            source?.setEventHandler { [weak self] in
                guard let self = self else {
                    return
                }
                DispatchQueue.main.async {
                    self.tick()
                }
            }
            source?.resume()
            #else
            displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
            if #available(iOS 10.0, *) {
                displayLink?.preferredFramesPerSecond = preferredFramesPerSecond
            }
            displayLink?.add(to: RunLoop.main, forMode: .common)
            #endif
        }
    }
    
    /// Stops recording of view and begins writing frames to video
    public func stop() {
        if shouldUseReplayKit {
            #if os(macOS)
            shouldUseReplayKit = false
            stop()
            #else
            if #available(iOS 11.0, *) {
                screenRecorder.stopCapture { [weak self] (error) in
                    guard let self = self else {
                        return
                    }
                    if let error = error {
                        self.onProgress = nil
                        self.compositionAnimation = nil
                        self.onCompletion?(.failure(error))
                        self.onCompletion = nil
                    } else {
                        let composition: ((CALayer) ->  Void)?
                        if self.compositionAnimation != nil  {
                            composition = { [weak self] layer in  self?.compositionAnimation?(layer) }
                        } else {
                            composition = nil
                        }
                        self.writer.endLiveCapture(assetType: self.assetType,
                                                   compositionAnimation: composition,
                                                   progress: { [weak self] prog in DispatchQueue.main.async { self?.onProgress?(prog) }
                            }, completion: { [weak self] result in
                                guard let self = self else {
                                    return
                                }
                                DispatchQueue.main.async {
                                    self.writer.startDate = nil
                                    self.writer.endDate = nil
                                    self.onProgress = nil
                                    self.compositionAnimation = nil
                                    self.onCompletion?(result)
                                    self.onCompletion = nil
                                }
                        })
                    }
                }
            } else {
                shouldUseReplayKit = false
                stop()
            }
            #endif
        } else {
            #if os(OSX)
            source?.cancel()
            queue = nil
            #else
            guard let displayLink = self.displayLink else {
                return
            }
            displayLink.invalidate()
            self.displayLink = nil
            #endif

            writer.endDate = Date()
            sourceView = nil
            
            writer.createVideoFromCapturedFrames(assetType: assetType,
                                                 compositionAnimation: compositionAnimation,
            progress: { [weak self] (prog) in
                guard let self = self else {
                    return
                }
                DispatchQueue.main.async {
                    self.onProgress?(prog)
                }
            }, completion: { [weak self] result in
                guard let self = self else {
                    return
                }
                DispatchQueue.main.async {
                    self.writer.startDate = nil
                    self.writer.endDate = nil
                    self.onProgress = nil
                    self.compositionAnimation = nil
                    self.onCompletion?(result)
                    self.onCompletion = nil
                }
            })
        }
    }
    
    /// Makes an asset of type `assetType` from a an array of images with a framerate equal to `preferredFramesPerSecond`. The asset will have a size equal to the first image's size.
    /// - Parameters:
    ///   - images: The array of images
    ///   - compositionAnimation: optional closure for adding `AVVideoCompositionCoreAnimationTool` composition animations. Add `CALayer`s as sublayers to the passed in `CALayer`. Then trigger animations with a `beginTime` of `AVCoreAnimationBeginTimeAtZero`. *Reminder that `CALayer` origin for `AVVideoCompositionCoreAnimationTool` is lower left  for `UIKit` setting `isGeometryFlipped = true is suggested* **Default is `nil`**
    ///   - progress: Closure called when progress is made. Called on the main thread. **Default is `nil`**
    ///   - completion: Closure called when the asset has finished being created. Called on the main thread.
    public func makeAsset(from images: [Image],
                          compositionAnimation: ((CALayer) -> Void)? = nil,
                          progress: ((CGFloat) -> Void)? = nil,
                          completion: @escaping (Result<FlipBookAssetWriter.Asset, Error>) -> Void) {
        writer.frames = images
        writer.preferredFramesPerSecond = preferredFramesPerSecond
        let firstCGImage = images.first?.cgI
        writer.size = CGSize(width: firstCGImage?.width ?? 0, height: firstCGImage?.height ?? 0)
        writer.createVideoFromCapturedFrames(assetType: assetType,
                                             compositionAnimation: compositionAnimation,
                                             progress: { (prog) in
                                                DispatchQueue.main.async { progress?(prog) }
        }, completion: { result in
            DispatchQueue.main.async { completion(result) }
        })
    }
    
    /// Saves a `LivePhotoResources` to photo library as a Live Photo. **You must request permission to modify photo library before attempting to save as well as add "Privacy - Photo Library Usage Description" key to your app's info.plist**
    /// - Parameters:
    ///   - resources: The resources of the Live Photo to be saved
    ///   - completion: Closure called after the resources have been saved. Called on the main thread.
    public func saveToLibrary(_ resources: LivePhotoResources, completion: @escaping (Result<Bool, Error>) -> Void) {
        writer.livePhotoWriter.saveToLibrary(resources, completion: completion)
    }
    
    /// Determines the frame rate of a gif by looking at the `delay` of the first image
    /// - Parameter gifURL: The file `URL` where the gif is located.
    /// - Returns: The frame rate as an `Int` or `nil` if data at url was invalid
    public func makeFrameRate(_ gifURL: URL) -> Int? {
        return writer.gifWriter?.makeFrameRate(gifURL)
    }
    
    /// Creates an array of `Image`s that represent the frames of a gif
    /// - Parameter gifURL: The file `URL` where the gif is located.
    /// - Returns: The frames rate as an `Int` or `nil` if data at url was invalid
    public func makeImages(_ gifURL: URL) -> [Image]? {
        return writer.gifWriter?.makeImages(gifURL)
    }
    
    // MARK: - Internal Methods -
    
    #if os(OSX)
    internal func tick() {
        guard let viewImage = sourceView?.fb_makeViewSnapshot() else {
            return
        }
        writer.writeFrame(viewImage)
    }
    
    #else

    @objc internal func tick(_ displayLink: CADisplayLink) {
        guard let viewImage = sourceView?.fb_makeViewSnapshot() else {
            return
        }
        writer.writeFrame(viewImage)
    }
    #endif
}
