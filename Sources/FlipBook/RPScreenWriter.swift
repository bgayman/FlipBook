//
//  RPScreenWriter.swift
//  
//
//  Created by Brad Gayman on 2/2/20.
//
//  Taken from https://gist.github.com/mspvirajpatel/f7e1e258f3c1fff96917d82fa9c4c137

#if os(iOS)
import Foundation
import AVFoundation
import ReplayKit

internal final class RPScreenWriter: NSObject {
    // Write video
    var videoOutputURL: URL
    var videoWriter: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    // Write audio
    var audioOutputURL: URL
    var audioWriter: AVAssetWriter?
    var micAudioInput:AVAssetWriterInput?
    var appAudioInput:AVAssetWriterInput?
    
    var isVideoWritingFinished = false
    var isAudioWritingFinished = false
    
    var isPaused: Bool = false
    
    var sessionStartTime: CMTime = .zero
    
    var currentTime: CMTime = .zero {
        didSet {
            didUpdateSeconds?(currentTime.seconds)
        }
    }
    
    var didUpdateSeconds: ((Double) -> ())?
    
    override init() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0] as NSString
        self.videoOutputURL = URL(fileURLWithPath: documentsPath.appendingPathComponent("FlipBookVideo.mp4"))
        self.audioOutputURL = URL(fileURLWithPath: documentsPath.appendingPathComponent("FlipBookAudio.mp4"))
        super.init()
        self.removeURLsIfNeeded()
    }
    
    func removeURLsIfNeeded() {
        do {
            try FileManager.default.removeItem(at: self.videoOutputURL)
            try FileManager.default.removeItem(at: self.audioOutputURL)
        } catch {}
    }
    
    func setUpWriter() {
        do {
            try videoWriter = AVAssetWriter(outputURL: self.videoOutputURL, fileType: .mp4)
        } catch let writerError as NSError {
            print("Error opening video file \(writerError)")
        }
        let videoSettings: [String: Any]
        if #available(iOS 11.0, *) {
            videoSettings = [
                AVVideoCodecKey : AVVideoCodecType.h264,
                AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill,
                AVVideoWidthKey  : UIScreen.main.bounds.width * UIScreen.main.scale,
                AVVideoHeightKey : UIScreen.main.bounds.height * UIScreen.main.scale
                ] as [String : Any]
        } else {
            videoSettings = [
                AVVideoCodecKey : AVVideoCodecH264,
                AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill,
                AVVideoWidthKey  : UIScreen.main.bounds.width * UIScreen.main.scale,
                AVVideoHeightKey : UIScreen.main.bounds.height * UIScreen.main.scale
            ] as [String : Any]
        }
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        if let videoInput = self.videoInput,
            let canAddInput = videoWriter?.canAdd(videoInput),
            canAddInput {
            videoWriter?.add(videoInput)
        } else {
            print("couldn't add video input")
        }
        
        do {
            try audioWriter = AVAssetWriter(outputURL: self.audioOutputURL, fileType: .mp4)
        } catch let writerError as NSError {
            print("Error opening video file \(writerError)")
        }
        
        let audioOutputSettings = [
            AVNumberOfChannelsKey : 2,
            AVFormatIDKey : kAudioFormatMPEG4AAC_HE,
            AVSampleRateKey : 44100
            ] as [String : Any]
        
        appAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
        if let appAudioInput = self.appAudioInput,
            let canAddInput = audioWriter?.canAdd(appAudioInput),
            canAddInput {
            audioWriter?.add(appAudioInput)
        } else {
            print("couldn't add app audio input")
        }
        micAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
        if let micAudioInput = self.micAudioInput,
            let canAddInput = audioWriter?.canAdd(micAudioInput),
            canAddInput {
            audioWriter?.add(micAudioInput)
        } else {
            print("couldn't add mic audio input")
        }
    }
    
    func writeBuffer(_ cmSampleBuffer: CMSampleBuffer, rpSampleType: RPSampleBufferType) {
        if self.videoWriter == nil {
            self.setUpWriter()
        }
        guard let videoWriter = self.videoWriter,
            let audioWriter = self.audioWriter,
            !isPaused else {
                return
        }
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(cmSampleBuffer)
        switch rpSampleType {
        case .video:
            if videoWriter.status == .unknown {
                if videoWriter.startWriting() {
                    print("video writing started")
                    self.sessionStartTime = presentationTimeStamp
                    videoWriter.startSession(atSourceTime: presentationTimeStamp)
                }
            } else if videoWriter.status == .writing {
                if let isReadyForMoreMediaData = videoInput?.isReadyForMoreMediaData,
                    isReadyForMoreMediaData {
                    self.currentTime = CMTimeSubtract(presentationTimeStamp, self.sessionStartTime)
                    if let appendInput = videoInput?.append(cmSampleBuffer),
                        !appendInput {
                        print("couldn't write video buffer")
                    }
                }
            }
        case .audioApp:
            if audioWriter.status == .unknown {
                if audioWriter.startWriting() {
                    print("audio writing started")
                    audioWriter.startSession(atSourceTime: presentationTimeStamp)
                }
            } else if audioWriter.status == .writing {
                if let isReadyForMoreMediaData = appAudioInput?.isReadyForMoreMediaData,
                    isReadyForMoreMediaData {
                    if let appendInput = appAudioInput?.append(cmSampleBuffer),
                        !appendInput {
                        print("couldn't write app audio buffer")
                    }
                }
            }
        case .audioMic:
            if audioWriter.status == .unknown {
                if audioWriter.startWriting() {
                    print("audio writing started")
                    audioWriter.startSession(atSourceTime: presentationTimeStamp)
                }
            } else if audioWriter.status == .writing {
                if let isReadyForMoreMediaData = micAudioInput?.isReadyForMoreMediaData,
                    isReadyForMoreMediaData {
                    if let appendInput = micAudioInput?.append(cmSampleBuffer),
                        !appendInput {
                        print("couldn't write mic audio buffer")
                    }
                }
            }
        @unknown default:
            break
        }
    }
    
    func finishWriting(completionHandler handler: @escaping (URL?, Error?) -> Void) {
        self.videoInput?.markAsFinished()
        self.videoWriter?.finishWriting {
            self.isVideoWritingFinished = true
            completion()
        }

        if audioWriter?.status.rawValue != 0 {
            self.appAudioInput?.markAsFinished()
            self.micAudioInput?.markAsFinished()
            self.audioWriter?.finishWriting {
                self.isAudioWritingFinished = true
                completion()
            }
        } else {
            self.isAudioWritingFinished = true
        }
        
        func completion() {
            if self.isVideoWritingFinished && self.isAudioWritingFinished {
                self.isVideoWritingFinished = false
                self.isAudioWritingFinished = false
                self.isPaused = false
                self.videoInput = nil
                self.videoWriter = nil
                self.appAudioInput = nil
                self.micAudioInput = nil
                self.audioWriter = nil
                merge()
            }
        }
        
        func merge() {
            let mergeComposition = AVMutableComposition()
            
            let videoAsset = AVAsset(url: self.videoOutputURL)
            let videoTracks = videoAsset.tracks(withMediaType: .video)
            print(videoAsset.duration.seconds)
            let videoCompositionTrack = mergeComposition.addMutableTrack(withMediaType: .video,
                                                                         preferredTrackID: kCMPersistentTrackID_Invalid)
            do {
                try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, end: videoAsset.duration),
                                                           of: videoTracks.first!,
                                                           at: .zero)
            } catch let error {
                removeURLsIfNeeded()
                handler(nil, error)
            }
            videoCompositionTrack?.preferredTransform = videoTracks.first!.preferredTransform
            
            let audioAsset = AVAsset(url: self.audioOutputURL)
            let audioTracks = audioAsset.tracks(withMediaType: .audio)
            for audioTrack in audioTracks {
                let audioCompositionTrack = mergeComposition.addMutableTrack(withMediaType: .audio,
                                                                             preferredTrackID: kCMPersistentTrackID_Invalid)
                do {
                    try audioCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, end: audioAsset.duration),
                                                               of: audioTrack,
                                                               at: .zero)
                } catch let error {
                    print(error)
                }
            }
            let documentsPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0] as NSString
            let outputURL = URL(fileURLWithPath: documentsPath.appendingPathComponent("FlipBookMergedVideo.mp4"))
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {}

            let exportSession = AVAssetExportSession(asset: mergeComposition,
                                                     presetName: AVAssetExportPresetHighestQuality)
            exportSession?.outputFileType = .mp4
            exportSession?.shouldOptimizeForNetworkUse = true
            exportSession?.outputURL = outputURL
            exportSession?.exportAsynchronously {
                if let error = exportSession?.error {
                    self.removeURLsIfNeeded()
                    handler(nil, error)
                } else {
                    self.removeURLsIfNeeded()
                    handler(exportSession?.outputURL, nil)
                }
            }
        }
    }
}
#endif
