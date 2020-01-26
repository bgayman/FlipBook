import XCTest
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
        
        flipBook.startRecording(view, progress: { _ in }, completion: { _ in })
        
        flipBook.stop()
        
        #if os(OSX)
        XCTAssertEqual(flipBook.source?.isCancelled, true)
        #else
        XCTAssertEqual(flipBook.displayLink == nil, true)
        #endif
        
        XCTAssertEqual(flipBook.writer.endDate != nil, true)
    }

    static var allTests = [
        ("testInit", testInit),
        ("testStart", testStart),
        ("testStop", testStop)
    ]
}
