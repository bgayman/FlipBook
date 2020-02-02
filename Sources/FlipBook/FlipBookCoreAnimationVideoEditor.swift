//
//  FlipBookCoreAnimationVideoEditor.swift
//  
//
//  Created by Brad Gayman on 1/30/20.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import AVFoundation

// MARK: - FlipBookCoreAnimationVideoEditor -

public final class FlipBookCoreAnimationVideoEditor: NSObject {
    
    // MARK: - Types -
    
    /// Errors that can `FlipBookCoreAnimationVideoEditor` might throw
    enum FlipBookCoreAnimationVideoEditorError: String, Error {
        
        /// Compositing was cancelled
        case cancelled
        
        /// The composition could not be created
        case couldNotCreateComposition
        
        /// The export session could not be created
        case couldNotCreateExportSession
        
        /// The output URL could not be created
        case couldNotCreateOutputURL
        
        /// An unknown error occured
        case unknown
    }
    
    // MARK: - Public Properties -
    
    /// The number of frames per second targetted
    /// **Default** 60 frames per second
    public var preferredFramesPerSecond: Int = 60
    
    // MARK: - Internal Properties -
    
    /// Source for capturing progress of export
    internal var source: DispatchSourceTimer?
    
    // MARK: - Public Methods -
    
    /// Makes a new video composition from a video and core animation animation
    /// - Parameters:
    ///   - videoURL: The `URL` of the video that the core animation animation should be composited with
    ///   - animation: Closure for adding `AVVideoCompositionCoreAnimationTool` composition animations. Add `CALayer`s as sublayers to the passed in `CALayer`. Then trigger animations with a `beginTime` of `AVCoreAnimationBeginTimeAtZero`. *Reminder that `CALayer` origin for `AVVideoCompositionCoreAnimationTool` is lower left  for `UIKit` setting `isGeometryFlipped = true is suggested* **Default is `nil`**
    ///   - progress: Optional closure that is called with a `CGFloat` representing the progress of composit generation. `CGFloat` is in the range `(0.0 ... 1.0)`. `progress` will be called from a main thread
    ///   - completion: Closure that is called when the video composit has been created with the `URL` for the created video. `completion` will be called from a main thread
    public func makeVideo(fromVideoAt videoURL: URL,
                          animation: @escaping (CALayer) -> Void,
                          progress: ((CGFloat) -> Void)?,
                          completion: @escaping (Result<URL, Error>) -> Void) {
        
        let asset = AVURLAsset(url: videoURL)
        let composition = AVMutableComposition()
        
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video,
                                                                 preferredTrackID: kCMPersistentTrackID_Invalid),
            let assetTrack = asset.tracks(withMediaType: .video).first else {
                DispatchQueue.main.async { completion(.failure(FlipBookCoreAnimationVideoEditorError.couldNotCreateComposition))}
                return
        }
        
        do {
            let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: .zero)
            
            if  let audioAssetTrack = asset.tracks(withMediaType: .audio).first,
                let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                                        preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compositionAudioTrack.insertTimeRange(timeRange, of: audioAssetTrack, at: .zero)
            }
            
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        
        compositionTrack.preferredTransform = assetTrack.preferredTransform
        let videoInfo = orientation(from: assetTrack.preferredTransform)
        let videoSize: CGSize

        if videoInfo.isPortrait {
            videoSize = CGSize(width: assetTrack.naturalSize.height, height: assetTrack.naturalSize.width)
        } else {
            videoSize = assetTrack.naturalSize
        }
          
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: videoSize)

        let outputLayer = CALayer()
        outputLayer.frame = CGRect(origin: .zero, size: videoSize)
        outputLayer.addSublayer(videoLayer)
        outputLayer.addSublayer(overlayLayer)
        
        animation(overlayLayer)
          
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(preferredFramesPerSecond))
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer,
                                                                             in: outputLayer)
          
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero,
                                            duration: composition.duration)
        
        videoComposition.instructions = [instruction]
        let layerInstruction = compositionLayerInstruction(for: compositionTrack,
                                                           assetTrack: assetTrack)
        instruction.layerInstructions = [layerInstruction]
          
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(.failure(FlipBookCoreAnimationVideoEditorError.couldNotCreateExportSession)) }
            return
        }
          
        guard let exportURL = FlipBookAssetWriter().makeFileOutputURL(fileName: "FlipBookVideoComposition.mov") else {
            DispatchQueue.main.async { completion(.failure(FlipBookCoreAnimationVideoEditorError.couldNotCreateOutputURL)) }
            return
        }
          
        export.videoComposition = videoComposition
        export.outputFileType = .mov
        export.outputURL = exportURL
        
        if let progress = progress {
            source = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            source?.schedule(deadline: .now(), repeating: 1.0 / Double(self.preferredFramesPerSecond))
            source?.setEventHandler { [weak self] in
                progress(CGFloat(export.progress))
                if export.progress == 1.0 {
                    self?.source?.cancel()
                    self?.source = nil
                }
            }
            source?.resume()
        }
          
        export.exportAsynchronously {
            DispatchQueue.main.async {
                switch export.status {
                case .completed:
                    completion(.success(exportURL))
                case .unknown, .exporting, .waiting:
                    completion(.failure(FlipBookCoreAnimationVideoEditorError.unknown))
                case .failed:
                    completion(.failure(export.error ?? FlipBookCoreAnimationVideoEditorError.unknown))
                case .cancelled:
                    completion(.failure(FlipBookCoreAnimationVideoEditorError.cancelled))
                @unknown default:
                    completion(.failure(FlipBookCoreAnimationVideoEditorError.unknown))
                }
            }
        }
    }
    
    //MARK: - Internal Methods -
    
    /// Function that determines the orientation and whether a rectangle is in "Portrait" from a transform
    /// - Parameter transform: The transform of the rectangle
    internal func orientation(from transform: CGAffineTransform) -> (orientation: CGImagePropertyOrientation, isPortrait: Bool) {
        var assetOrientation = CGImagePropertyOrientation.up
        var isPortrait = false
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            assetOrientation = .right
            isPortrait = true
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            assetOrientation = .left
            isPortrait = true
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            assetOrientation = .up
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            assetOrientation = .down
        }

        return (assetOrientation, isPortrait)
    }
    
    /// Function that makes the composition instruction for a given composition track from a given asset track
    /// - Parameters:
    ///   - track: The track of the composition
    ///   - assetTrack: The track of the asset
    internal func compositionLayerInstruction(for track: AVCompositionTrack, assetTrack: AVAssetTrack) -> AVMutableVideoCompositionLayerInstruction {
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let transform = assetTrack.preferredTransform

        instruction.setTransform(transform, at: .zero)

        return instruction
    }
}
