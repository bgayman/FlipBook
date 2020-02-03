//
//  FlipBookLivePhotoWriter.swift
//  
//
//  Created by Brad Gayman on 1/25/20.
//

import Foundation
import AVFoundation
#if !os(macOS)
import MobileCoreServices
#else
import CoreServices
#endif
import Photos

// MARK: - LivePhotoResources -

/// Struct that represents the resources that comprise a Live Photo
public struct LivePhotoResources: Equatable, Hashable {
    
    /// The url of the still image of a Live Photo
    let imageURL: URL
    
    /// The url of the video of a Live Photo
    let videoURL: URL
}

// MARK: - FlipBookLivePhotoWriter -

/// Class that performs common tasks with Live Photos
public final class FlipBookLivePhotoWriter: NSObject {
    
    // MARK: - Types -
    
    /// Errors that `FlipBookLivePhotoWriter` can throw
    public enum FlipBookLivePhotoWriterError: Error {
        
        /// Unable to write to cache directory
        case couldNotWriteToDirectory
        
        /// Could not find video track
        case couldNotAccessVideoTrack
        
        /// An unknown error occured
        case unknownError
    }
    
    // MARK: - Public Properties -
    
    // MARK: - Private Properties -
    
    /// Queue on which Live Photo writing takes place
    static internal let queue = DispatchQueue(label: "com.FlipBook.live.photo.writer.queue", attributes: .concurrent)
    
    /// `URL` to location in caches directory where files will be written to
    lazy internal var cacheDirectory: URL? = self.makeCacheDirectoryURL()
    
    /// Asset reader for audio track
    internal var audioReader: AVAssetReader?
    
    /// Asset reader for video track
    internal var videoReader: AVAssetReader?
    
    /// Asset writer for Live Photo
    internal var assetWriter: AVAssetWriter?
    
    // MARK: - Init / Deinit -
    
    deinit {
        clearCache()
    }
    
    // MARK: - Public Methods -
    
    /// Makes Live Photo from image url and video url
    /// - Parameters:
    ///   - imageURL: The `URL` of the still image. `imageURL` is `nil` still image is generated from middle of video.
    ///   - videoURL: The `URL`of the video fo the Live Photo
    ///   - progress: Closure that is called when progress is made on creating Live Photo. Called from the main thread.
    ///   - completion: Closure call when the Live Photo has finished being created. Called from the main thread.
    public func makeLivePhoto(from imageURL: URL?,
                              videoURL: URL,
                              progress: ((CGFloat) -> Void)?,
                              completion: @escaping (Result<(PHLivePhoto, LivePhotoResources), Error>) -> Void) {
        Self.queue.async { [weak self] in
            guard let self = self else { return }
            self.make(from: imageURL, videoURL: videoURL, progress: progress, completion: completion)
        }
    }
    
    /// Extracts out the still image and video from a Live Photo
    /// - Parameters:
    ///   - livePhoto: The Live Photo to be decomposed
    ///   - completion: Closure  called with the resources are seporated and saved. Called on the main thread.
    public func extractResources(_ livePhoto: PHLivePhoto,
                                 completion: @escaping (Result<LivePhotoResources, Error>) -> Void) {
        Self.queue.async {
            self.extractResources(from: livePhoto, completion: completion)
        }
    }
    
    /// Saves a `LivePhotoResources` to photo library as a Live Photo. **You must request permission to modify photo library before attempting to save as well as add "Privacy - Photo Library Usage Description" key to your app's info.plist**
    /// - Parameters:
    ///   - resources: The resources of the Live Photo to be saved
    ///   - completion: Closure called after the resources have been saved. Called on the main thread
    public func saveToLibrary(_ resources: LivePhotoResources, completion: @escaping (Result<Bool, Error>) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let creationRequest = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            creationRequest.addResource(with: .pairedVideo, fileURL: resources.videoURL, options: options)
            creationRequest.addResource(with: .photo, fileURL: resources.imageURL, options: options)
        }, completionHandler: { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(success))
                }
            }
        })
    }
    
    // MARK: - Private Methods -
    
    /// Makes Live Photo from image url and video url
    /// - Parameters:
    ///   - imageURL: The `URL` of the still image. `imageURL` is `nil` still image is generated from middle of video.
    ///   - videoURL: The `URL`of the video fo the Live Photo
    ///   - progress: Closure that is called when progress is made on creating Live Photo. Called from the main thread.
    ///   - completion: Closure call when the Live Photo has finished being created. Called from the main thread.
    internal func make(from imageURL: URL?,
                       videoURL: URL,
                       progress: ((CGFloat) -> Void)?,
                       completion: @escaping (Result<(PHLivePhoto, LivePhotoResources), Error>) -> Void) {
        guard let cacheDirectory = self.cacheDirectory else {
            DispatchQueue.main.async { completion(.failure(FlipBookLivePhotoWriterError.couldNotWriteToDirectory)) }
            return
        }
        let assetIdentifier = UUID().uuidString
        do {
            var kPhotoURL = imageURL
            if kPhotoURL == nil {
                kPhotoURL = try makeKeyPhoto(from: videoURL)
            }
            guard let keyPhotoURL = kPhotoURL, let pairImageURL = add(assetIdentifier, toImage: keyPhotoURL, saveTo: cacheDirectory.appendingPathComponent(assetIdentifier).appendingPathExtension("jpg")) else {
                DispatchQueue.main.async { completion(.failure(FlipBookLivePhotoWriterError.unknownError)) }
                return
            }
            add(assetIdentifier, to: videoURL, saveTo: cacheDirectory.appendingPathComponent(assetIdentifier).appendingPathExtension("mov"), progress: progress) { (result) in
                switch result {
                case .success(let url):
                    _ = PHLivePhoto.request(withResourceFileURLs: [pairImageURL, url], placeholderImage: nil, targetSize: .zero, contentMode: .aspectFit) { (livePhoto, info) in
                        guard let livePhoto = livePhoto, (info[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false) == false  else {
                            return
                        }
                        DispatchQueue.main.async { completion(.success((livePhoto, LivePhotoResources(imageURL: pairImageURL, videoURL: url)))) }
                    }
                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
    
    /// Adds asset id to video and saves to destination
    /// - Parameters:
    ///   - assetIdentifier: The asset identifier to be added
    ///   - videoURL: The `URL` of the video
    ///   - destination: Where the asset with the added identifier should be written
    ///   - progress: Closure that calls back with progress of writing. Called from background thread.
    ///   - completion: Closure called when video with asset identifier has been written. Called from background thread.
    internal func add(_ assetIdentifier: String,
                     to videoURL: URL,
                     saveTo destination: URL,
                     progress: ((CGFloat) -> Void)?,
                     completion: @escaping (Result<URL, Error>) -> Void) {
        
        var audioWriterInput: AVAssetWriterInput?
        var audioReaderOutput: AVAssetReaderOutput?
        let videoAsset = AVURLAsset(url: videoURL)
        let frameCount = videoAsset.frameCount(exact: false)
        
        guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
            completion(.failure(FlipBookLivePhotoWriterError.couldNotAccessVideoTrack))
            return
        }
        do {
            
            // Create the Asset Writer
            assetWriter = try AVAssetWriter(outputURL: destination, fileType: .mov)
            
            // Create Video Reader Output
            videoReader = try AVAssetReader(asset: videoAsset)
            let videoReaderSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA as NSNumber
            ]
            let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
            videoReader?.add(videoReaderOutput)
            
            // Create Video Writer Input
            #if !os(macOS)
            let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecH264,
                AVVideoWidthKey: videoTrack.naturalSize.width,
                AVVideoHeightKey: videoTrack.naturalSize.height
            ])
            #else
            let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoTrack.naturalSize.width,
                AVVideoHeightKey: videoTrack.naturalSize.height
            ])
            #endif
            videoWriterInput.transform = videoTrack.preferredTransform
            videoWriterInput.expectsMediaDataInRealTime = true
            assetWriter?.add(videoWriterInput)
            
            // Create Audio Reader Output & Writer Input
            if let audioTrack = videoAsset.tracks(withMediaType: .audio).first {
                do {
                    let aReader = try AVAssetReader(asset: videoAsset)
                    let aReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
                    aReader.add(aReaderOutput)
                    audioReader = aReader
                    audioReaderOutput = aReaderOutput
                    let aWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
                    aWriterInput.expectsMediaDataInRealTime = false
                    assetWriter?.add(aWriterInput)
                    audioWriterInput = aWriterInput
                } catch {
                    print(error)
                }
            }
            
            // Create necessary indentifier metadata and still image time metadata
            let assetIdentifierMetadata = makeMetadata(for: assetIdentifier)
            let stillImageTimeMetadataAdapter = makeMetadataAdaptorForStillImageTime()
            assetWriter?.metadata = [assetIdentifierMetadata]
            assetWriter?.add(stillImageTimeMetadataAdapter.assetWriterInput)
            
            // Start the Asset Writer
            assetWriter?.startWriting()
            assetWriter?.startSession(atSourceTime: .zero)
            
            // Add still image metadata
            let sIPercent: Float = 0.5
            stillImageTimeMetadataAdapter.append(AVTimedMetadataGroup(items: [makeMetadataItemForStillImageTime()],
                                                                      timeRange: videoAsset.makeStillImageTimeRange(percent: sIPercent, in: frameCount)))
            
            // For end of writing / progress
            var writingVideoFinished = false
            var writingAudioFinished = false
            var currentFrameCount = 0
            
            // Create onCompletion function
            func didCompleteWriting() {
                guard writingAudioFinished && writingVideoFinished else {
                    return
                }
                assetWriter?.finishWriting { [weak self] in
                    guard let self = self else {
                        completion(.failure(FlipBookLivePhotoWriterError.unknownError))
                        return
                    }
                    if self.assetWriter?.status == .completed {
                        completion(.success(destination))
                    } else if let error = self.assetWriter?.error {
                        completion(.failure(error))
                    } else {
                        completion(.failure(FlipBookLivePhotoWriterError.unknownError))
                    }
                }
            }
            
            // Start writing video
            if videoReader?.startReading() ?? false {
                videoWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "videoWriterInputQueue")) {
                    while videoWriterInput.isReadyForMoreMediaData {
                        if let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() {
                            currentFrameCount += 1
                            let percent = CGFloat(currentFrameCount) / CGFloat(frameCount)
                            DispatchQueue.main.async { progress?(percent) }
                            if videoWriterInput.append(sampleBuffer) == false {
                                self.videoReader?.cancelReading()
                                completion(.failure(self.assetWriter?.error ?? FlipBookLivePhotoWriterError.unknownError))
                            }
                        } else {
                            videoWriterInput.markAsFinished()
                            writingVideoFinished = true
                            didCompleteWriting()
                        }
                    }
                }
            } else {
                writingVideoFinished = true
                didCompleteWriting()
            }
            
            // Start writing audio
            if audioReader?.startReading() ?? false {
                audioWriterInput?.requestMediaDataWhenReady(on: DispatchQueue(label: "audioWriterInputQueue")) {
                    while audioWriterInput?.isReadyForMoreMediaData ?? false {
                        guard let sampleBuffer = audioReaderOutput?.copyNextSampleBuffer() else {
                            audioWriterInput?.markAsFinished()
                            writingAudioFinished = true
                            didCompleteWriting()
                            return
                        }
                        audioWriterInput?.append(sampleBuffer)
                    }
                }
            } else {
                writingAudioFinished = true
                didCompleteWriting()
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    /// Extracts out the still image and video from a Live Photo
    /// - Parameters:
    ///   - livePhoto: The Live Photo to be decomposed
    ///   - completion: Closure  called with the resources are seporated and saved
    internal func extractResources(from livePhoto: PHLivePhoto, completion: @escaping (Result<LivePhotoResources, Error>) -> Void) {
        guard let url = cacheDirectory else {
            DispatchQueue.main.async {
                completion(.failure(FlipBookLivePhotoWriterError.couldNotWriteToDirectory))
            }
            return
        }
        extractResources(from: livePhoto, to: url, completion: completion)
    }
    
    /// Seporates still image and video from a Live Photo
    /// - Parameters:
    ///   - livePhoto: The Live Photo to be decomposed
    ///   - directoryURL: The `URL` of the directory to save the seporated resources
    ///   - completion: Closure  called with the resources are seporated and saved
    internal func extractResources(from livePhoto: PHLivePhoto, to directoryURL: URL, completion: @escaping (Result<LivePhotoResources, Error>) -> Void) {
        let assetResources = PHAssetResource.assetResources(for: livePhoto)
        let group = DispatchGroup()
        var keyPhotoURL: URL?
        var videoURL: URL?
        var result: Result<LivePhotoResources, Error>?
        for resource in assetResources {
            var buffer = Data()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            group.enter()
            PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { (data) in
                buffer.append(data)
            }, completionHandler: { err in
                if let error = err {
                    result = .failure(error)
                } else if resource.type == .pairedVideo {
                    do {
                        videoURL = try self.save(resource, to: directoryURL, resourceData: buffer)
                    } catch {
                        result = .failure(error)
                    }
                } else {
                    do {
                        keyPhotoURL = try self.save(resource, to: directoryURL, resourceData: buffer)
                    } catch {
                        result = .failure(error)
                    }
                }
                group.leave()
            })
        }
        group.notify(queue: .main) {
            if let result = result {
                completion(result)
            } else if let pairedPhotoURL = keyPhotoURL, let pairedVideoURL = videoURL {
                completion(.success(LivePhotoResources(imageURL: pairedPhotoURL, videoURL: pairedVideoURL)))
            } else {
                completion(.failure(FlipBookLivePhotoWriterError.unknownError))
            }
        }
    }
    
    /// Saves a resource in a given directory
    /// - Parameters:
    ///   - resource: The resource to be saved
    ///   - directory: The directory in which the resource should be saved
    ///   - resourceData: The data that the resource is composed of
    internal func save(_ resource: PHAssetResource, to directory: URL, resourceData: Data) throws -> URL? {
        let fileExtension = UTTypeCopyPreferredTagWithClass(resource.uniformTypeIdentifier as CFString,
                                                            kUTTagClassFilenameExtension)?.takeRetainedValue()
        
        guard let ext = fileExtension else {
            return nil
        }
        
        var fileURL = directory.appendingPathComponent(UUID().uuidString)
        fileURL = fileURL.appendingPathExtension(ext as String)
        
        try resourceData.write(to: fileURL, options: [.atomic])
        return fileURL
    }
    
    /// Adds asset identifier to metadata of image
    /// - Parameters:
    ///   - assetIdentifier: The asset identifier to be added
    ///   - imageURL: The `URL` where the image is currently
    ///   - saveTo: The `URL` where the image should be written to
    internal func add(_ assetIdentifier: String, toImage imageURL: URL, saveTo destinationURL: URL) -> URL? {
        guard let imageDestination = CGImageDestinationCreateWithURL(destinationURL as CFURL, kUTTypeJPEG, 1, nil),
              let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              var imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [AnyHashable: Any] else {
                return nil
        }
        let assetIdentifierKey = "17"
        let assetIdentifierInfo = [assetIdentifierKey: assetIdentifier]
        imageProperties[kCGImagePropertyMakerAppleDictionary] = assetIdentifierInfo
        CGImageDestinationAddImageFromSource(imageDestination, imageSource, 0, imageProperties as CFDictionary)
        CGImageDestinationFinalize(imageDestination)
        return destinationURL
    }
    
    /// Makes an `AVMetadataItem` for a given asset identifier
    /// - Parameter assetIdentifier: the asset identifier to be enclosed in the metadata item
    internal func makeMetadata(for assetIdentifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        let keyContentIdentifier =  "com.apple.quicktime.content.identifier"
        let keySpaceQuickTimeMetadata = "mdta"
        item.key = keyContentIdentifier as NSString
        item.keySpace = AVMetadataKeySpace(keySpaceQuickTimeMetadata)
        item.value = assetIdentifier as NSString
        item.dataType = "com.apple.metadata.datatype.UTF-8"
        return item
    }
    
    /// Makes an `AVAssetWriterInputMetadataAdaptor` for the still image time
    internal func makeMetadataAdaptorForStillImageTime() -> AVAssetWriterInputMetadataAdaptor {
        let keyStillImageTime = "com.apple.quicktime.still-image-time"
        let keySpaceQuickTimeMetadata = "mdta"
        let spec: NSDictionary = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as NSString: "\(keySpaceQuickTimeMetadata)/\(keyStillImageTime)",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as NSString: "com.apple.metadata.datatype.int8"
        ]
        var desc: CMFormatDescription? = nil
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault,
                                                                    metadataType: kCMMetadataFormatType_Boxed,
                                                                    metadataSpecifications: [spec] as CFArray,
                                                                    formatDescriptionOut: &desc)
        let input = AVAssetWriterInput(mediaType: .metadata,
                                       outputSettings: nil,
                                       sourceFormatHint: desc)
        return AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
    }
    
    /// Makes an `AVMetadataItem` for a still image time
    internal func makeMetadataItemForStillImageTime() -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        let keyStillImageTime = "com.apple.quicktime.still-image-time"
        let keySpaceQuickTimeMetadata = "mdta"
        item.key = keyStillImageTime as NSString
        item.keySpace = AVMetadataKeySpace(keySpaceQuickTimeMetadata)
        item.value = 0 as NSNumber
        item.dataType = "com.apple.metadata.datatype.int8"
        return item
    }
    
    /// Makes a still image at the % mark of a video
    /// - Parameters:
    /// - videoURL: The `URL` of the video to make the still image from
    /// - percent: How far into the video the key photo should come from **Default** is 50%
    internal func makeKeyPhoto(from videoURL: URL, percent: Float = 0.5) throws -> URL? {
        var percent: Float = percent
        let videoAsset = AVURLAsset(url: videoURL)
        if let stillImageTime = videoAsset.getStillImageTime() {
            percent = Float(stillImageTime.value) / Float(videoAsset.duration.value)
        }
        guard let imageFrame = videoAsset.makeImageFromFrame(at: percent),
              let jpegData = imageFrame.jpegRep,
              let url = cacheDirectory?.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg") else {
                return nil
        }
        try jpegData.write(to: url)
        return url
    }
    
    /// Makes `URL` "FlipBook-LivePhoto" to directory in caches directory
    internal func makeCacheDirectoryURL() -> URL? {
        do {
            let cacheDirectoryURL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let fullDirectory = cacheDirectoryURL.appendingPathComponent("FlipBook-LivePhoto", isDirectory: true)
            if !FileManager.default.fileExists(atPath: fullDirectory.absoluteString) {
                try FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true, attributes: nil)
            }
            return fullDirectory
        } catch {
            print(error)
            return nil
        }
    }
    
    /// Removes "FlipBook-LivePhoto" from caches directory
    internal func clearCache() {
        guard let url = cacheDirectory else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - AVAsset + Live Photo -

/// Collection of helper functions for getting asset frames and stills
internal extension AVAsset {
    
    /// Returns the number a frames for the first video track
    /// - Parameter exact: if `true` counts every frame. If `false` uses the `nominalFrameRate` of the video track to determine the number of frames
    func frameCount(exact: Bool) -> Int {
        guard let videoReader = try? AVAssetReader(asset: self),
              let videoTrack = tracks(withMediaType: .video).first else {
                return 0
        }
        
        var frameCount = Int(CMTimeGetSeconds(duration) * Float64(videoTrack.nominalFrameRate))
        
        if exact {
            frameCount = 0
            let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            videoReader.add(videoReaderOutput)
            videoReader.startReading()
            while videoReaderOutput.copyNextSampleBuffer() != nil {
                frameCount += 1
            }
            videoReader.cancelReading()
        }
        return frameCount
    }
    
    /// Looks through asset metadata and determines `CMTime` for the still image of a Live Photo
    func getStillImageTime() -> CMTime? {
        guard let videoReader = try? AVAssetReader(asset: self),
              let metadataTrack = tracks(withMediaType: .metadata).first else {
            return nil
        }
        var stillTime: CMTime? = nil

        let videoReaderOutput = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)
        videoReader.add(videoReaderOutput)
        videoReader.startReading()
    
        let keyStillImageTime = "com.apple.quicktime.still-image-time"
        let keySpaceQuickTimeMetadata = "mdta"
        
        while let sampleBuffer = videoReaderOutput.copyNextSampleBuffer(), stillTime == nil {
            if CMSampleBufferGetNumSamples(sampleBuffer) != 0 {
                let group = AVTimedMetadataGroup(sampleBuffer: sampleBuffer)
                for item in group?.items ?? [] {
                    if item.key as? String == keyStillImageTime && item.keySpace?.rawValue == keySpaceQuickTimeMetadata {
                        stillTime = group?.timeRange.start
                        break
                    }
                }
            }
        }
        
        videoReader.cancelReading()
        
        return stillTime
    }
    
    /// Makes a `CMTimeRange` representing the range of the asset after the supplied percent
    /// - Parameters:
    ///   - percent: How much of the beging of the track to be excluded. Values should be in `(0.0 ... 1.0)`
    ///   - frameCount: The number of frames in the asset. **Default** 0. If `0` is passed in the number of frames will be determined exactly
    func makeStillImageTimeRange(percent: Float, in frameCount: Int = 0) -> CMTimeRange {
        var time = duration
        let frameCount = frameCount == 0 ? self.frameCount(exact: true) : frameCount
        
        let frameDuration = Int64(Float(time.value) / Float(frameCount))
        
        time.value = Int64(Float(time.value) * percent)
        
        return CMTimeRangeMake(start: time, duration: CMTimeMake(value: frameDuration, timescale: time.timescale))
    }
    
    /// Makes a still image from the frame of an asset at location determined by its percentage into the asset
    /// - Parameter percent: What percent of the way through an asset should the image come from
    func makeImageFromFrame(at percent: Float) -> Image? {
        let imageGenerator = AVAssetImageGenerator(asset: self)
        imageGenerator.appliesPreferredTrackTransform = true
        
        imageGenerator.requestedTimeToleranceAfter = CMTimeMake(value: 1, timescale: 100)
        imageGenerator.requestedTimeToleranceBefore = CMTimeMake(value: 1, timescale: 100)
        
        var time = duration
        time.value = Int64(Float(time.value) * percent)
        
        do {
            var actualTime = CMTime.zero
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: &actualTime)
            
            #if os(OSX)
            return Image(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            #else
            return Image(cgImage: cgImage)
            #endif
        } catch {
            print(error)
            return nil
        }
    }
}
