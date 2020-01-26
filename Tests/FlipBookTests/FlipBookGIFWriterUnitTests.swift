//
//  FlipBookGIFWriterUnitTests.swift
//  
//
//  Created by Brad Gayman on 1/26/20.
//

import XCTest
@testable import FlipBook
#if os(OSX)
import AppKit
#else
import UIKit
#endif

final class FlipBookGIFWriterUnitTests: XCTestCase {
    
    func testInit() {
        let gifWriter = FlipBookGIFWriter(fileOutputURL: FlipBookAssetWriter().makeFileOutputURL(fileName: "output.gif"))
        
        XCTAssertEqual(FlipBookGIFWriter.queue.label, "com.FlipBook.gif.writer.queue")
        XCTAssertEqual(gifWriter?.fileOutputURL.absoluteString.contains("Caches"), true)
        XCTAssertEqual(gifWriter?.fileOutputURL.absoluteString.contains("output.gif"), true)
    }
    
    func testImageResize() {
        let image: Image
        let scale: CGFloat
        #if os(OSX)
        let view: View = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGray.cgColor
        scale = view.scale
        guard let img = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image = img
        #else
        let view: View = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.backgroundColor = UIColor.systemGray
        scale = view.scale
        guard let img = view.fb_makeViewSnapshot() else {
            XCTFail("Could not make image")
            return
        }
        image = img
        #endif
        let cgImage = image.cgI
        
        XCTAssertEqual(cgImage != nil, true)
        XCTAssertEqual(cgImage?.width, 100 * Int(scale))
        XCTAssertEqual(cgImage?.height, 100 * Int(scale))
        
        let resizedCGImage = cgImage?.resize(with: 0.5)
        
        XCTAssertEqual(resizedCGImage != nil, true)
        XCTAssertEqual(resizedCGImage?.width, 100 * Int(scale) / 2)
        XCTAssertEqual(resizedCGImage?.height, 100 * Int(scale) / 2)
    }
    
    func testMakeGIF() {
        // Make Images
        let image: Image
        let image1: Image
        let image2: Image
        let scale: CGFloat
        #if os(OSX)
        let view: View = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 100.0, height: 100.0)))
        view.wantsLayer = true
        scale = view.scale
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
        scale = view.scale
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
        
        var prog: CGFloat = 0.0
        var assetURL: URL? = nil
        let expectation = self.expectation(description: "createAsset")
        
        let gifWriter = FlipBookGIFWriter(fileOutputURL: FlipBookAssetWriter().makeFileOutputURL(fileName: "output.gif"))
        gifWriter?.makeGIF([image, image1, image2], delay: 0.02, loop: 0, sizeRatio: 0.5, progress: { p in
            prog = p
        }, completion: { result in
            switch result {
            case .success(let url):
                assetURL = url
                expectation.fulfill()
            case .failure(let error):
                XCTFail(error.localizedDescription)
            }
        })
        
        waitForExpectations(timeout: 30) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        
        XCTAssertEqual(assetURL != nil, true)
        XCTAssertEqual(prog != 0.0, true)
        do {
            let gifData = try Data(contentsOf: assetURL!)
            guard let source =  CGImageSourceCreateWithData(gifData as CFData, nil) else {
                XCTFail("Could not make source")
                return
            }
            XCTAssertEqual(CGImageSourceGetCount(source), 3)
            if let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                XCTAssertEqual(image.width, 100 * Int(scale) / 2)
                XCTAssertEqual(image.height, 100 * Int(scale) / 2)
            } else {
                XCTFail("No first image")
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
        
    }
    
    static var allTests = [
        ("testInit", testInit),
        ("testImageResize", testImageResize)
    ]
}
