import XCTest
import AVFoundation
@testable import FlipBook
#if os(OSX)
import AppKit
#else
import UIKit
#endif

final class FlipBookUnitTests: XCTestCase {

    func testInit() {
        let flipBook = FlipBook()
        
        XCTAssertEqual(flipBook.preferredFramesPerSecond, 60)
        XCTAssertEqual(flipBook.gifImageScale, 0.5)
        XCTAssertEqual(flipBook.assetType, .video)
        XCTAssertEqual(flipBook.onProgress == nil, true)
        XCTAssertEqual(flipBook.onCompletion == nil, true)
        XCTAssertEqual(flipBook.sourceView == nil, true)
        #if os(OSX)
        XCTAssertEqual(flipBook.queue == nil, true)
        XCTAssertEqual(flipBook.source == nil, true)
        #else
        XCTAssertEqual(flipBook.displayLink == nil , true)
        #endif
    }
    
    func testStart() {
        let flipBook = FlipBook()
        flipBook.gifImageScale = 0.75
        flipBook.preferredFramesPerSecond = 12
        let view: View
        #if os(OSX)
        view = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGray.cgColor
        #else
        view = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.backgroundColor = UIColor.systemGray
        #endif
        
        flipBook.startRecording(view, progress: { _ in }, completion: { _ in })
        
        XCTAssertEqual(flipBook.sourceView, view)
        XCTAssertEqual(flipBook.onProgress != nil, true)
        XCTAssertEqual(flipBook.onCompletion != nil, true)
        XCTAssertEqual(flipBook.writer.size, CGSize(width: 100.0 * view.scale, height: 100.0 * view.scale))
        XCTAssertEqual(flipBook.writer.startDate != nil, true)
        XCTAssertEqual(flipBook.writer.gifImageScale, 0.75)
        
        
        #if os(OSX)
        XCTAssertEqual(flipBook.queue != nil, true)
        XCTAssertEqual(flipBook.source != nil, true)
        XCTAssertEqual(flipBook.source?.isCancelled, false)
        #else
        XCTAssertEqual(flipBook.displayLink != nil, true)
        if #available(iOS 10.0, *) {
            XCTAssertEqual(flipBook.displayLink?.preferredFramesPerSecond, 12)
        }
        #endif
        flipBook.stop()
    }
    
    func testStop() {
        let flipBook = FlipBook()
        flipBook.gifImageScale = 0.75
        flipBook.preferredFramesPerSecond = 12
        let view: View
        #if os(OSX)
        view = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGray.cgColor
        #else
        view = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.backgroundColor = UIColor.systemGray
        #endif
        
        let expectation = self.expectation(description: "makeAsset")
        var progress: CGFloat = 0.0
        var animationCallCount = 0
        var videoURL: URL? = nil
        
        flipBook.startRecording(view,
                                compositionAnimation: { _ in animationCallCount += 1 },
                                progress: { prog in progress = prog },
                                completion: { result in
                                    switch result {
                                    case .success(let asset):
                                        videoURL = asset.assetURL
                                        expectation.fulfill()
                                    case .failure(let error):
                                        XCTFail("\(error)")
                                    }
        })
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            flipBook.stop()
            XCTAssertEqual(flipBook.writer.endDate != nil, true)
            #if os(OSX)
            XCTAssertEqual(flipBook.source?.isCancelled, true)
            #else
            XCTAssertEqual(flipBook.displayLink == nil, true)
            #endif
            XCTAssertEqual(flipBook.sourceView == nil, true)
        }
        
        waitForExpectations(timeout: 30) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        XCTAssertEqual(progress != 0.0, true)
        XCTAssertEqual(animationCallCount, 1)
        
        guard let url = videoURL else {
            XCTFail("Failed to get video url")
            return
        }
        let asset = AVURLAsset(url: url)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            XCTFail("No video track")
            return
        }
        XCTAssertEqual(videoTrack.naturalSize.width, view.bounds.width * view.scale)
        XCTAssertEqual(videoTrack.naturalSize.height, view.bounds.height * view.scale)
    }
    
    func testMakeAssetFromImages() {
        let flipBook = FlipBook()
        
        // Make Images
        let image: Image
        let image1: Image
        let image2: Image
        #if os(OSX)
        let view: View = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGray.cgColor
        guard let img = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image = img
        view.layer?.backgroundColor = NSColor.systemBlue.cgColor
        guard let img1 = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image1 = img1
        view.layer?.backgroundColor = NSColor.systemRed.cgColor
        guard let img2 = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image2 = img2
        #else
        let view: View = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.backgroundColor = UIColor.systemGray
        guard let img = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image = img
        view.backgroundColor = UIColor.systemBlue
        guard let img1 = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image1 = img1
        view.backgroundColor = UIColor.systemRed
        guard let img2 = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image2 = img2
        #endif
        
        let expectation = self.expectation(description: "makeAsset")
        var prog: CGFloat = 0.0
        var assetURL: URL?
        var animationCallCount = 0
        
        flipBook.makeAsset(from: [image, image1, image2], compositionAnimation: { _ in
            animationCallCount += 1
        }, progress: { (p) in
            prog = p
            XCTAssertEqual(Thread.isMainThread, true)
        }, completion: { result in
            XCTAssertEqual(Thread.isMainThread, true)
            switch result {
            case .success(let asset):
                switch asset {
                case .video(let url):
                    assetURL = url
                    expectation.fulfill()
                case .livePhoto, .gif:
                    XCTFail("wrong asset type")
                }
            case .failure(let error):
                XCTFail(error.localizedDescription)
            }
        })
        waitForExpectations(timeout: 30) { (error) in
            if let err = error {
                XCTFail(err.localizedDescription)
            }
        }
        
        XCTAssertEqual(prog != 0.0, true)
        XCTAssertEqual(animationCallCount, 1)
        
        guard let url = assetURL else {
            XCTFail("No asset url")
            return
        }
        let asset = AVURLAsset(url: url)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            XCTFail("No video track")
            return
        }
        XCTAssertEqual(videoTrack.naturalSize.width, 100.0 * View().scale)
        XCTAssertEqual(videoTrack.naturalSize.height, 100.0 * View().scale)
    }

    static var allTests = [
        ("testInit", testInit),
        ("testStart", testStart),
        ("testStop", testStop),
        ("testMakeAssetFromImages", testMakeAssetFromImages)
    ]
}
