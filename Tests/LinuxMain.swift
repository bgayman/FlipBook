import XCTest

import FlipBookTests

var tests = [XCTestCaseEntry]()
tests += FlipBookUnitTests.allTests()
tests += FlipBookAssetWriterUnitTests.allTests()
tests += FlipBookGIFWriterUnitTests.allTests()
XCTMain(tests)
