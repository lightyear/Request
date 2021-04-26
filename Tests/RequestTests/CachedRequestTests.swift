//
//  CachedRequestTests.swift
//
//  Created by Steve Madsen on 1/17/21.
//  Copyright © 2021 Light Year Software, LLC.
//

import XCTest
import Nimble
@testable import Request

private enum CacheError: Error {
    case shouldNotParse
}

private struct TestRequest: CachedRequest {
    typealias ModelType = Int
    typealias ContextType = Void

    let method = HTTPMethod.get
    let host = "api"
    let path = "/test"

    func cachedResponse(context: Void?) -> Int? {
        1
    }

    func parseResponse(context: Void?, data: Data) throws -> Int {
        throw CacheError.shouldNotParse
    }
}

class CachedRequestTests: XCTestCase {
    let session = TestSession()
    private var request = TestRequest()

    override func setUpWithError() throws {
        try super.setUpWithError()
        RequestTaskManager.shared.session = session
    }

    func testReturnsCachedResponse() {
        let expectation = XCTestExpectation(description: "GET /test")
        let publisher = request.start()
            .sink(receiveCompletion: { result in
                switch result {
                case .finished:           expectation.fulfill()
                case .failure(let error): fail("\(error)")
                }
            }, receiveValue: {
                expect($0) == 1
            })
        expect(publisher).toNot(beNil())
        wait(for: [expectation], timeout: 1)
    }
}
