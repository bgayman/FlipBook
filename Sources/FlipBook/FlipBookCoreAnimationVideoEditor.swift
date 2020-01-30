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

public final class FlipBookCoreAnimationVideoEditor {
    
    // MARK: - Types -
    
    enum FlipBookCoreAnimationVideoEditorError: String, Error {
        case cancelled
        case couldNotCreateComposition
        case couldNotCreateExportSession
        case couldNotCreateOutputURL
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
    
    internal func compositionLayerInstruction(for track: AVCompositionTrack, assetTrack: AVAssetTrack) -> AVMutableVideoCompositionLayerInstruction {
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let transform = assetTrack.preferredTransform

        instruction.setTransform(transform, at: .zero)

        return instruction
    }
}
