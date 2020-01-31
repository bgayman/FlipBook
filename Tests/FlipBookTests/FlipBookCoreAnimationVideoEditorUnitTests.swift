//
//  FlipBookCoreAnimationVideoEditorUnitTests.swift
//  
//
//  Created by Brad Gayman on 1/31/20.
//

import XCTest
@testable import FlipBook
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import AVFoundation

final class FlipBookCoreAnimationVideoEditorUnitTests: XCTestCase {
    
    func testInit() {
        let coreAnimationVideoEditor = FlipBookCoreAnimationVideoEditor()
        
        XCTAssertEqual(coreAnimationVideoEditor.preferredFramesPerSecond, 60)
        XCTAssertEqual(coreAnimationVideoEditor.source == nil, true)
    }
    
    func testCompositionLayerInstruction() {
        let coreAnimationVideoEditor = FlipBookCoreAnimationVideoEditor()
        let expectation = self.expectation(description: "makeVideo")
        var videoURL: URL?
        makeVideo { (url) in
            guard let url = url else {
                XCTFail("Could not make movie")
                return
            }
            videoURL = url
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        guard let url = videoURL else {
            XCTFail("No video url")
            return
        }
        let composition = AVMutableComposition()
        let asset = AVURLAsset(url: url)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            XCTFail("No video track")
            return
        }
                
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            XCTFail("Could not make composition track")
            return
        }
        
        let instruction = coreAnimationVideoEditor.compositionLayerInstruction(for: compositionTrack,
                                                                               assetTrack: videoTrack)
        var transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        guard instruction.getTransformRamp(for: .zero, start: &transform, end: nil, timeRange: nil) else {
            XCTFail("Could not get transform")
            return
        }
        XCTAssertEqual(transform, videoTrack.preferredTransform)
    }
    
    func testMakeVideo() {
        let coreAnimationVideoEditor = FlipBookCoreAnimationVideoEditor()
        let expectation = self.expectation(description: "makeVideo")
        var videoURL: URL?
        var progress: CGFloat = 0.0
        var animationCallCount = 0
        makeVideo { (url) in
            guard let url = url else {
                XCTFail("Could not make movie")
                return
            }
            coreAnimationVideoEditor.makeVideo(fromVideoAt: url, animation: { (layer) in
                let textLayer = CATextLayer()
                textLayer.string = "Testing!!"
                layer.addSublayer(textLayer)
                animationCallCount += 1
            }, progress: { (prog) in
                progress = prog
            }, completion: { result in
                switch result {
                case .success(let url):
                    videoURL = url
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail("\(error)")
                }
            })
        }
        waitForExpectations(timeout: 30) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        guard let url = videoURL else {
            XCTFail("No video URL")
            return
        }
        let asset = AVURLAsset(url: url)
        XCTAssertEqual(url.absoluteString.contains("Caches"), true)
        XCTAssertEqual(url.absoluteString.contains("FlipBookVideoComposition.mov"), true)
        XCTAssertEqual(animationCallCount, 1)
        XCTAssertEqual(progress > 0.0, true)
        XCTAssertEqual(asset.tracks(withMediaType: .video).first != nil, true)
    }
    
    static var allTests = [
        ("testInit", testInit),
        ("testCompositionLayerInstruction", testCompositionLayerInstruction),
        ("testMakeVideo", testMakeVideo)
    ]
}

// MARK: - FlipBookCoreAnimationVideoEditorUnitTests + MakeVideo -

extension FlipBookCoreAnimationVideoEditorUnitTests {
    
    func makeVideo(completion: @escaping (URL?) -> Void) {
        let flipBookAssetWriter = FlipBookAssetWriter()
        flipBookAssetWriter.size = CGSize(width: 100.0 * View().scale, height: 100.0 * View().scale)
        
        // Make Images
        let image: Image
        let image1: Image
        let image2: Image
        #if os(OSX)
        let view: View = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGray.cgColor
        guard let img = view.fb_makeViewSnapshot() else {
            completion(nil)
            return
        }
        image = img
        view.layer?.backgroundColor = NSColor.systemBlue.cgColor
        guard let img1 = view.fb_makeViewSnapshot() else {
            completion(nil)
            return
        }
        image1 = img1
        view.layer?.backgroundColor = NSColor.systemRed.cgColor
        guard let img2 = view.fb_makeViewSnapshot() else {
            completion(nil)
            return
        }
        image2 = img2
        #else
        let view: View = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.backgroundColor = UIColor.systemGray
        guard let img = view.fb_makeViewSnapshot() else {
            completion(nil)
            return
        }
        image = img
        view.backgroundColor = UIColor.systemBlue
        guard let img1 = view.fb_makeViewSnapshot() else {
            completion(nil)
            return
        }
        image1 = img1
        view.backgroundColor = UIColor.systemRed
        guard let img2 = view.fb_makeViewSnapshot() else {
            completion(nil)
            return
        }
        image2 = img2
        #endif

        flipBookAssetWriter.createAsset(from: [image, image1, image2, image, image1, image2], progress: { (_) in }, completion: { result in
            switch result {
                
            case .success(let asset):
                switch asset {
                case .video(let url):
                    completion(url)
                case .livePhoto, .gif:
                    completion(nil)
                }
            case .failure:
                completion(nil)
            }
        })
    }
}
