//
//  RPScreenWriterUnitTests.swift
//  
//
//  Created by Brad Gayman on 2/3/20.
//

#if os(iOS)
import XCTest
import AVFoundation
@testable import FlipBook
import ReplayKit

final class RPScreenWriterUnitTests: XCTestCase {
    
    func testInit() {
        let writer = RPScreenWriter()
        XCTAssertEqual(writer.videoWriter, nil)
        XCTAssertEqual(writer.videoInput, nil)
        XCTAssertEqual(writer.audioWriter, nil)
        XCTAssertEqual(writer.micAudioInput, nil)
        XCTAssertEqual(writer.appAudioInput, nil)
        XCTAssertEqual(writer.isVideoWritingFinished, false)
        XCTAssertEqual(writer.isAudioWritingFinished, false)
        XCTAssertEqual(writer.isPaused, false)
        XCTAssertEqual(writer.sessionStartTime, .zero)
        XCTAssertEqual(writer.currentTime, .zero)
        XCTAssertEqual(writer.didUpdateSeconds == nil, true)
    }
    
    func testSetupWriter() {
        let writer = RPScreenWriter()
        writer.setUpWriter()

        XCTAssertEqual(writer.videoWriter != nil, true)
        XCTAssertEqual(writer.videoInput != nil, true)
        XCTAssertEqual(writer.videoWriter?.inputs.count, 1)
        guard let videoInput = writer.videoInput else {
            XCTFail("No video input")
            return
        }
        XCTAssertEqual(writer.videoInput?.mediaType, .video)
        XCTAssertEqual(writer.videoWriter?.inputs.contains(videoInput), true)
        XCTAssertEqual(videoInput.outputSettings?[AVVideoWidthKey] as? CGFloat, UIScreen.main.bounds.width * UIScreen.main.scale)
        XCTAssertEqual(videoInput.outputSettings?[AVVideoHeightKey] as? CGFloat, UIScreen.main.bounds.height * UIScreen.main.scale)
        
        XCTAssertEqual(writer.audioWriter != nil, true)
        XCTAssertEqual(writer.appAudioInput != nil, true)
        XCTAssertEqual(writer.audioWriter?.inputs.count, 2)
        guard let appAudioInput = writer.appAudioInput else {
            XCTFail("No app audio input")
            return
        }
        XCTAssertEqual(appAudioInput.mediaType, .audio)
        XCTAssertEqual(writer.audioWriter?.inputs.contains(appAudioInput), true)
        
        XCTAssertEqual(writer.micAudioInput != nil, true)
        guard let micAudioInput = writer.micAudioInput else {
            XCTFail("No mic audio input")
            return
        }
        XCTAssertEqual(micAudioInput.mediaType, .audio)
        XCTAssertEqual(writer.audioWriter?.inputs.contains(micAudioInput), true)
    }
    
    func testWriteBuffer() {
        let writer = RPScreenWriter()
        
        let images = makeImages()
        let buffers = images.enumerated().compactMap { $0.element.cgI?.makeCMSampleBuffer($0.offset) }
        buffers.forEach {
            writer.writeBuffer($0, rpSampleType: .video)
        }
        
        XCTAssertEqual(writer.videoWriter != nil, true)
        XCTAssertEqual(writer.videoInput != nil, true)
        XCTAssertEqual(writer.isPaused, false)
        XCTAssertEqual(writer.isAudioWritingFinished, false)
        XCTAssertEqual(writer.isVideoWritingFinished, false)
    }
    
    func testFinishWriting() {
        let writer = RPScreenWriter()
        
        let images = makeImages()
        let buffers = images.enumerated().compactMap { $0.element.cgI?.makeCMSampleBuffer($0.offset) }
        buffers.forEach {
            writer.writeBuffer($0, rpSampleType: .video)
        }
        
        let expectation = self.expectation(description: "makeVideo")
        var videoURL: URL?
        var frames = [Image]()
        let flipBookAssetWriter = FlipBookAssetWriter()
        writer.finishWriting { (url, error) in
            guard error == nil else {
                XCTFail("Error \(error?.localizedDescription ?? "Some error")")
                return
            }
            guard let url = url else {
                XCTFail("No url")
                return
            }
            videoURL = url
            flipBookAssetWriter.makeFrames(from: url, progress: nil) { (imgs) in
                frames = imgs.map { Image(cgImage: $0) }
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 10) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        guard let url = videoURL else {
            XCTFail("No video url")
            return
        }
        let asset = AVURLAsset(url: url)
        XCTAssertEqual(asset.tracks(withMediaType: .video).count, 1)
        XCTAssertEqual(writer.isVideoWritingFinished, false)
        XCTAssertEqual(writer.isAudioWritingFinished, false)
        XCTAssertEqual(writer.isPaused, false)
        XCTAssertEqual(writer.videoInput, nil)
        XCTAssertEqual(writer.videoWriter, nil)
        XCTAssertEqual(writer.audioWriter, nil)
        XCTAssertEqual(writer.appAudioInput, nil)
        XCTAssertEqual(writer.micAudioInput, nil)
        XCTAssertEqual(frames.count, images.count)
    }
    
    static var allTests = [
        ("testInit", testInit),
        ("testSetupWriter", testSetupWriter),
        ("testWriteBuffer", testWriteBuffer)
    ]
}

extension RPScreenWriterUnitTests {

    func makeImages() -> [Image] {
        // Make Images
        let image: Image
        let image1: Image
        let image2: Image
        let view: View = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.backgroundColor = UIColor.systemGray
        guard let img = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return []
        }
        image = img
        view.backgroundColor = UIColor.systemBlue
        guard let img1 = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return []
        }
        image1 = img1
        view.backgroundColor = UIColor.systemRed
        guard let img2 = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return []
        }
        image2 = img2
        return [image, image1, image2]
    }
}

#endif
