//
//  FlipBookAssetWriterUnitTests.swift
//  
//
//  Created by Brad Gayman on 1/25/20.
//

import XCTest
import Photos
@testable import FlipBook
#if os(OSX)
import AppKit
#else
import UIKit
#endif

final class FlipBookAssetWriterUnitTests: XCTestCase {
    
    func testInit() {
        
        let flipBookAssetWriter = FlipBookAssetWriter()
        
        XCTAssertEqual(flipBookAssetWriter.preferredFramesPerSecond, 60)
        XCTAssertEqual(flipBookAssetWriter.fileOutputURL != nil, true)
        XCTAssertEqual(flipBookAssetWriter.startDate == nil, true)
        XCTAssertEqual(flipBookAssetWriter.endDate == nil, true)
        XCTAssertEqual(flipBookAssetWriter.gifImageScale, 0.5)
        XCTAssertEqual(flipBookAssetWriter.frames.isEmpty, true)
        XCTAssertEqual(flipBookAssetWriter.queue.label, "com.FlipBook.asset.writer.queue")
        XCTAssertEqual(flipBookAssetWriter.input == nil, true)
        XCTAssertEqual(flipBookAssetWriter.adapter == nil, true)
        XCTAssertEqual(flipBookAssetWriter.gifWriter != nil, true)
    }
    
    func testWriteToFrame() {
        let flipBookAssetWriter = FlipBookAssetWriter()
        let image: Image
        #if os(OSX)
        let view: View = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGray.cgColor
        guard let img = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image = img
        #else
        let view: View = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.backgroundColor = UIColor.systemGray
        guard let img = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image = img
        #endif
        flipBookAssetWriter.writeFrame(image)
        XCTAssertEqual(flipBookAssetWriter.frames.count, 1)
    }
    
    func testCreateAssetFromImages() {
        let flipBookAssetWriter = FlipBookAssetWriter()
        flipBookAssetWriter.size = CGSize(width: 100.0, height: 100.0)
        
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

        // Test video
        var prog: CGFloat = 0.0
        var assetURL: URL? = nil
        let expectation = self.expectation(description: "createAsset")
        
        flipBookAssetWriter.createAsset(from: [image, image1, image2], progress: { (p) in
            prog = p
        }, completion: { result in
            switch result {
                
            case .success(let asset):
                switch asset {
                case .video(let url):
                    assetURL = url
                    expectation.fulfill()
                case .livePhoto, .gif:
                    XCTFail("Wrong asset type")
                }
            case .failure(let error):
                XCTFail(error.localizedDescription)
            }
        })
        
        waitForExpectations(timeout: 30) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        XCTAssertEqual(prog != 0.0, true)
        XCTAssertEqual(assetURL != nil, true)
        
        // Test GIF
        var prog1: CGFloat = 0.0
        var assetURLGIF: URL? = nil
        let expectationGIF = self.expectation(description: "createAssetGif")
        
        flipBookAssetWriter.createAsset(from: [image, image1, image2], assetType: .gif, progress: { (p) in
            prog1 = p
        }, completion: { result in
            switch result {
                
            case .success(let asset):
                switch asset {
                case .gif(let url):
                    assetURLGIF = url
                    expectationGIF.fulfill()
                case .livePhoto, .video:
                    XCTFail("Wrong asset type")
                }
            case .failure(let error):
                XCTFail(error.localizedDescription)
            }
        })
        
        waitForExpectations(timeout: 30) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        XCTAssertEqual(prog1 != 0.0, true)
        XCTAssertEqual(assetURLGIF != nil, true)
        
        // Test Live Photo
        var prog2: CGFloat = 0.0
        var livePhoto: PHLivePhoto? = nil
        let expectationLivePhoto = self.expectation(description: "createAssetLivePhoto")
        
        flipBookAssetWriter.createAsset(from: [image, image1, image2], assetType: .livePhoto(nil), progress: { (p) in
            prog2 = p
        }, completion: { result in
            switch result {
                
            case .success(let asset):
                switch asset {
                case let .livePhoto(lp, _):
                    livePhoto = lp
                    expectationLivePhoto.fulfill()
                case .gif, .video:
                    XCTFail("Wrong asset type")
                }
            case .failure(let error):
                XCTFail(error.localizedDescription)
            }
        })
        
        waitForExpectations(timeout: 30) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        XCTAssertEqual(prog2 != 0.0, true)
        XCTAssertEqual(livePhoto != nil, true)
    }
    
    func testMakeFileOutputURL() {
        let flipBookAssetWriter = FlipBookAssetWriter()
        let urlString = flipBookAssetWriter.makeFileOutputURL()?.absoluteString
        XCTAssertEqual(urlString?.contains("FlipBook.mov"), true)
        XCTAssertEqual(urlString?.contains("Caches"), true)
        
        let urlString1 = flipBookAssetWriter.makeFileOutputURL(fileName: "myGreat.gif")?.absoluteString
        XCTAssertEqual(urlString1?.contains("myGreat.gif"), true)
        XCTAssertEqual(urlString1?.contains("Caches"), true)
    }
    
    func testMakeWriter() {
        let flipBookAssetWriter = FlipBookAssetWriter()
        flipBookAssetWriter.size = CGSize(width: 100.0, height: 100.0)
        do {
            let writer = try flipBookAssetWriter.makeWriter()
            XCTAssertEqual(flipBookAssetWriter.input != nil, true)
            XCTAssertEqual(flipBookAssetWriter.adapter != nil, true)
            XCTAssertEqual(writer.inputs.contains(flipBookAssetWriter.input!), true)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testMakeFrameRate() {
        let flipBookAssetWriter = FlipBookAssetWriter()
        flipBookAssetWriter.frames = Array(repeating: nil, count: 180)
        flipBookAssetWriter.startDate = Date(timeIntervalSinceNow: -3)
        flipBookAssetWriter.endDate = Date()
        
        let frameRate = flipBookAssetWriter.makeFrameRate()
        XCTAssertEqual(frameRate, 60)
        
        let flipBookAssetWriter1 = FlipBookAssetWriter()
        flipBookAssetWriter1.frames = Array(repeating: nil, count: 180)
        flipBookAssetWriter1.preferredFramesPerSecond = 20
        
        let frameRate1 = flipBookAssetWriter1.makeFrameRate()
        XCTAssertEqual(frameRate1, 20)
    }
    
    func testMakePixelBuffer() {
        let image: Image
        #if os(OSX)
        let view: View = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGray.cgColor
        guard let img = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image = img
        #else
        let view: View = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.backgroundColor = UIColor.systemGray
        guard let img = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image = img
        #endif
        
        let pixelBuffer = image.cgI?.makePixelBuffer()
        XCTAssertEqual(pixelBuffer != nil, true)
    }
    
    static var allTests = [
        ("testInit", testInit),
        ("testWriteToFrame", testWriteToFrame),
        ("testCreateAssetFromImages", testCreateAssetFromImages),
        ("testMakeFileOutputURL", testMakeFileOutputURL),
        ("testMakeWriter", testMakeWriter),
        ("testMakeFrameRate", testMakeFrameRate),
        ("testMakePixelBuffer", testMakePixelBuffer)
    ]
}
