import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(FlipBookUnitTests.allTests),
        testCase(FlipBookAssetWriterUnitTests.allTests),
        testCase(FlipBookGIFWriterUnitTests.allTests)
    ]
}
#endif
