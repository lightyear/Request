import XCTest

import RequestTests

var tests = [XCTestCaseEntry]()
tests += RequestTests.allTests()
tests += CachedRequestTests.allTests()
XCTMain(tests)
