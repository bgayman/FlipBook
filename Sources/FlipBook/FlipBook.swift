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
#endif

// MARK: - FlipBook -

/// Class that records a view
public final class FlipBook: NSObject {

    // MARK: - Public Properties
    
    /// The number of frames per second targetted
    /// **Default** 60 frames per second
    public var preferredFramesPerSecond: Int = 60
    
    /// The amount images in animated gifs should be scaled by. Fullsize gif images can be memory intensive. **Default** `0.5`
    public var gifImageScale: Float = 0.5
    
    /// The asset type to be created
    /// **Default** `.video`
    public var assetType: FlipBookAssetWriter.AssetType = .video
    
    // MARK: - Internal Properties -

    /// Asset writer used to convert screenshots into video
    internal let writer = FlipBookAssetWriter()
    
    /// Closure to be called when the asset writing has progressed
    internal var onProgress: ((CGFloat) -> Void)?
    
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
    ///   - view: view to be recorded
    ///   - progress: optional closure that is called with a `CGFloat` representing the progress of video generation. `CGFloat` is in the range `(0.0 ... 1.0)`. `progress` is called from the main thread
    ///   - completion: closure that is called when the video has been created with the `URL` for the created video. `completion` will be called from the main thread
    public func startRecording(_ view: View, progress: ((CGFloat) -> Void)?, completion: @escaping (Result<FlipBookAssetWriter.Asset, Error>) -> Void) {
        sourceView = view
        onProgress = progress
        onCompletion = completion
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
    
    /// Stops recording of view and begins writing frames to video
    public func stop() {
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
        
        writer.createVideoFromCapturedFrames(assetType: assetType, progress: { [weak self] (prog) in
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
                self.onCompletion?(result)
                self.onProgress = nil
                self.onCompletion = nil
            }
        })
    }
    
    /// Makes an asset of type `assetType` from a an array of images with a framerate equal to `preferredFramesPerSecond`. The asset will have a size equal to the first image's size.
    /// - Parameters:
    ///   - images: The array of images
    ///   - progress: Closure called when progress is made. Called on the main thread.
    ///   - completion: Closure called when the asset has finished being created. Called on the main thread.
    public func makeAsset(from images: [Image], progress: ((CGFloat) -> Void)?, completion: @escaping (Result<FlipBookAssetWriter.Asset, Error>) -> Void) {
        writer.frames = images
        writer.preferredFramesPerSecond = preferredFramesPerSecond
        let firstCGImage = images.first?.cgI
        writer.size = CGSize(width: firstCGImage?.width ?? 0, height: firstCGImage?.height ?? 0)
        writer.createVideoFromCapturedFrames(assetType: assetType, progress: { (prog) in
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
