//
//  FlipBookLivePhotoWriterUnitTests.swift
//  
//
//  Created by Brad Gayman on 1/26/20.
//

import XCTest
import Photos
@testable import FlipBook
#if os(OSX)
import AppKit
#else
import UIKit
#endif

// MARK: - FlipBookLivePhotoWriterUnitTests -

final class FlipBookLivePhotoWriterUnitTests: XCTestCase {
    
    func testInit() {
        
        let flipBookLivePhotoWriter = FlipBookLivePhotoWriter()
        
        XCTAssertEqual(FlipBookLivePhotoWriter.queue.label, "com.FlipBook.live.photo.writer.queue")
        XCTAssertEqual(flipBookLivePhotoWriter.cacheDirectory != nil, true)
        XCTAssertEqual(flipBookLivePhotoWriter.audioReader == nil, true)
        XCTAssertEqual(flipBookLivePhotoWriter.videoReader == nil, true)
        XCTAssertEqual(flipBookLivePhotoWriter.assetWriter == nil, true)
    }
    
    func testMakeCacheDirectoryURL() {
        let flipBookLivePhotoWriter = FlipBookLivePhotoWriter()
        let url = flipBookLivePhotoWriter.makeCacheDirectoryURL()
        
        XCTAssertEqual(url != nil, true)
        XCTAssertEqual(url?.absoluteString.contains("Caches"), true)
        XCTAssertEqual(url?.absoluteString.contains("FlipBook-LivePhoto"), true)
        XCTAssertEqual(FileManager.default.fileExists(atPath: url?.path ?? ""), true)
    }
    
    func testClearCache() {
        let flipBookLivePhotoWriter = FlipBookLivePhotoWriter()
        let url = flipBookLivePhotoWriter.makeCacheDirectoryURL()
        XCTAssertEqual(FileManager.default.fileExists(atPath: url?.path ?? ""), true)
        flipBookLivePhotoWriter.clearCache()
        XCTAssertEqual(FileManager.default.fileExists(atPath: url?.path ?? ""), false)
    }
    
    func testMakeKeyPhoto() {
        let flipBookLivePhotoWriter = FlipBookLivePhotoWriter()
        var assetURL: URL?
        let expectation = self.expectation(description: "createAsset")
        
        makeVideo { (url) in
            guard let url = url else {
                XCTFail("Could not make movie")
                return
            }
            assetURL = url
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        
        guard let url = assetURL else {
            XCTFail("Could not make movie")
            return
        }
        do {
            guard let imageURL = try flipBookLivePhotoWriter.makeKeyPhoto(from: url) else {
                XCTFail("Could not make url")
                return
            }
            let imageData = try Data(contentsOf: imageURL)
            guard let source =  CGImageSourceCreateWithData(imageData as CFData, nil) else {
                XCTFail("Could not make source")
                return
            }
            XCTAssertEqual(CGImageSourceGetCount(source), 1)
            XCTAssertEqual(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil, true)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testMakeMetadataItemForStillImageTime() {
        let flipBookLivePhotoWriter = FlipBookLivePhotoWriter()
        let item = flipBookLivePhotoWriter.makeMetadataItemForStillImageTime()
        XCTAssertEqual(item.key != nil, true)
        XCTAssertEqual(item.key as? NSString, "com.apple.quicktime.still-image-time" as NSString)
        XCTAssertEqual(item.keySpace, AVMetadataKeySpace("mdta"))
        XCTAssertEqual(item.value as? NSNumber, 0 as NSNumber)
        XCTAssertEqual(item.dataType, "com.apple.metadata.datatype.int8")
    }
    
    func testMakeMetadataAdaptorForStillImageTime() {
        let flipBookLivePhotoWriter = FlipBookLivePhotoWriter()
        let adaptor = flipBookLivePhotoWriter.makeMetadataAdaptorForStillImageTime()
        let input = adaptor.assetWriterInput
        
        XCTAssertEqual(input.mediaType, .metadata)
        XCTAssertEqual(input.sourceFormatHint != nil, true)
    }
    
    func testMakeMetadataForAssetID() {
        let flipBookLivePhotoWriter = FlipBookLivePhotoWriter()
        let idString = UUID().uuidString
        let item = flipBookLivePhotoWriter.makeMetadata(for: idString)
        
        XCTAssertEqual(item.key as? NSString, "com.apple.quicktime.content.identifier" as NSString)
        XCTAssertEqual(item.keySpace, AVMetadataKeySpace("mdta"))
        XCTAssertEqual(item.value as? NSString, idString as NSString)
        XCTAssertEqual(item.dataType, "com.apple.metadata.datatype.UTF-8")
    }
    
    func testAddAssetIDToImage() {
        let flipBookLivePhotoWriter = FlipBookLivePhotoWriter()
        let flipBookAssetWriter = FlipBookAssetWriter()
        let idString = UUID().uuidString
        
        guard let startURL = flipBookAssetWriter.makeFileOutputURL(fileName: "startURL.jpg"),
              let destURL = flipBookAssetWriter.makeFileOutputURL(fileName: "destURL.jpg") else {
            XCTFail("Could not create URLs")
            return
        }
        
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
        guard let data = image.jpegRep else {
            XCTFail("Could not make Image data")
            return
        }
        do {
            try data.write(to: startURL)
        } catch {
            XCTFail(error.localizedDescription)
        }
        
        _ = flipBookLivePhotoWriter.add(idString, toImage: startURL, saveTo: destURL)
        guard let imageSource = CGImageSourceCreateWithURL(destURL as CFURL, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [AnyHashable: Any] else {
                XCTFail("Could not get properties")
                return
        }
        let assetProps = imageProperties[kCGImagePropertyMakerAppleDictionary] as? [AnyHashable: Any]
        XCTAssertEqual(assetProps?["17"] != nil, true)
        XCTAssertEqual(assetProps?["17"] as? String, idString)
    }
    
    func testExtractResources() {
        let flipBookLivePhotoWriter = FlipBookLivePhotoWriter()
        var livePhotoResources: LivePhotoResources?
        let expectation = self.expectation(description: "createAsset")
        
        // Make video
        makeVideo { (url) in
            guard let url = url else {
                XCTFail("Could not make movie")
                return
            }
            flipBookLivePhotoWriter.makeLivePhoto(from: nil, videoURL: url, progress: { _ in }) { (result) in
                switch result {
                case .success(let lp, _):
                    flipBookLivePhotoWriter.extractResources(from: lp) { (result) in
                        switch result {
                        case .success(let resources):
                            livePhotoResources = resources
                            XCTAssertEqual(Thread.isMainThread, true)
                            expectation.fulfill()
                        case .failure(let error):
                            XCTFail(error.localizedDescription)
                        }
                    }
                case .failure(let error):
                    XCTFail(error.localizedDescription)
                }
            }
        }
        
        waitForExpectations(timeout: 30) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }

        guard let resources = livePhotoResources else {
            XCTFail("livePhotoResources should not be nil")
            return
        }
        XCTAssertEqual(resources.videoURL.absoluteString.contains("Caches"), true)
        XCTAssertEqual(resources.imageURL.absoluteString.contains("Caches"), true)
        
        let asset = AVURLAsset(url: resources.videoURL)
        XCTAssertEqual(asset.tracks(withMediaType: .video).first != nil, true)
        do {
            let data = try Data(contentsOf: resources.imageURL)
            let image = Image(data: data)
            XCTAssertEqual(image != nil, true)
        } catch {
            XCTFail("Could not get data")
        }
    }
    
    func testMakeLivePhoto() {
        let flipBookLivePhotoWriter = FlipBookLivePhotoWriter()
        var livePhotoResources: LivePhotoResources?
        var livePhoto: PHLivePhoto?
        var prog: CGFloat = 0.0
        let expectation = self.expectation(description: "makeLivePhoto")
        makeVideo { (url) in
            guard let url = url else {
                XCTFail("Could not make movie")
                return
            }
            flipBookLivePhotoWriter.makeLivePhoto(from: nil, videoURL: url, progress: { p in
                prog = p
                XCTAssertEqual(Thread.isMainThread, true)
            }) { (result) in
                XCTAssertEqual(Thread.isMainThread, true)
                switch result {
                case let .success(lp, resources):
                    livePhoto = lp
                    livePhotoResources = resources
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail(error.localizedDescription)
                }
            }
        }
        
        waitForExpectations(timeout: 30) { (error) in
            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }
        
        XCTAssertEqual(prog != 0.0, true)
        guard let liveP = livePhoto, let resources = livePhotoResources else {
            XCTFail("values nil")
            return
        }
        XCTAssertEqual(liveP.size.width, 100 * View().scale)
        XCTAssertEqual(liveP.size.height, 100 * View().scale)
        XCTAssertEqual(resources.videoURL.absoluteString.contains("Caches"), true)
        XCTAssertEqual(resources.imageURL.absoluteString.contains("Caches"), true)
        let asset = AVURLAsset(url: resources.videoURL)
        XCTAssertEqual(asset.tracks(withMediaType: .video).first != nil, true)
        do {
            let data = try Data(contentsOf: resources.imageURL)
            let image = Image(data: data)
            XCTAssertEqual(image != nil, true)
        } catch {
            XCTFail("Could not get data")
        }
    }
    
    static var allTests = [
        ("testInit", testInit),
        ("testMakeCacheDirectoryURL", testMakeCacheDirectoryURL),
        ("testClearCache", testClearCache),
        ("testMakeKeyPhoto", testMakeKeyPhoto),
        ("testMakeMetadataItemForStillImageTime", testMakeMetadataItemForStillImageTime),
        ("testMakeMetadataAdaptorForStillImageTime", testMakeMetadataAdaptorForStillImageTime),
        ("testMakeMetadataForAssetID", testMakeMetadataForAssetID),
        ("testExtractResources", testExtractResources),
        ("testMakeLivePhoto", testMakeLivePhoto)
    ]
}

// MARK: - FlipBookLivePhotoWriterUnitTests + MakeVideo -

extension FlipBookLivePhotoWriterUnitTests {
    
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

        flipBookAssetWriter.createAsset(from: [image, image1, image2], progress: { (_) in }, completion: { result in
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
