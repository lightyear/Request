//
//  RequestTests.swift
//
//  Created by Steve Madsen on 5/8/20.
//  Copyright © 2021 Light Year Software, LLC.
//

import XCTest
import Nimble
@testable import Request

private class TestRequest: Request {
    let baseURL = URL(string: "https://api")!
    let path = "/test"

    var errors = [String]()

    func parseResponse(context: Void?, data: Data) throws -> Int {
        if let string = String(data: data, encoding: .utf8), let value = Int(string) {
            return value
        } else {
            throw RequestError.parseError
        }
    }

    func logError(_ message: String, data: [String: Any]) {
        errors.append(message)
    }
}

class RequestTests: XCTestCase {
    let session = TestSession()
    private var request = TestRequest()

    override func setUpWithError() throws {
        try super.setUpWithError()
        RequestTaskManager.shared.session = session
    }

    func testSuccess() {
        session.allow(.get, "https://api/test", return: 200, body: "1")
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

    func testServerFailure() {
        session.allow(.get, "https://api/test", return: 500, body: "1")
        let expectation = XCTestExpectation(description: "GET /test")
        let publisher = request.start()
            .sink(receiveCompletion: { result in
                switch result {
                case .finished: fail("should not succeed")
                case .failure(RequestError.serverFailure(let status)):
                    expect(status) == 500
                    expectation.fulfill()
                case .failure: fail("failed with the wrong error type")
                }
            }, receiveValue: { _ in
                fail("should not receive a value")
            })
        expect(publisher).toNot(beNil())
        wait(for: [expectation], timeout: 1)
    }

    func testInvalidResponseType() {
        session.allow(.get, "https://api/test", return: 200, headers: ["Content-Type": "text/html"], body: "a")
        let expectation = XCTestExpectation(description: "GET /test")
        let publisher = request.start()
            .sink(receiveCompletion: { result in
                switch result {
                case .finished: fail("should not succeed")
                case .failure(RequestError.wrongContentType):
                    expectation.fulfill()
                case .failure: fail("failed with the wrong error type")
                }
            }, receiveValue: { _ in
                fail("should not receive a value")
            })
        expect(publisher).toNot(beNil())
        wait(for: [expectation], timeout: 1)
    }

    func testParsingFailure() {
        session.allow(.get, "https://api/test", return: 200, body: "a")
        let expectation = XCTestExpectation(description: "GET /test")
        let publisher = request.start()
            .sink(receiveCompletion: { result in
                switch result {
                case .finished: fail("should not succeed")
                case .failure(RequestError.parseError):
                    expectation.fulfill()
                case .failure: fail("failed with the wrong error type")
                }
            }, receiveValue: { _ in
                fail("should not receive a value")
            })
        expect(publisher).toNot(beNil())
        wait(for: [expectation], timeout: 1)
    }

    func testNetworkFailure() {
        session.allow(.get, "https://api/test", return: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: nil))
        let expectation = XCTestExpectation(description: "GET /test")
        let publisher = request.start()
            .sink(receiveCompletion: { result in
                switch result {
                case .finished: fail("should not succeed")
                case .failure(let error as NSError):
                    expect(error.domain) == NSURLErrorDomain
                    expect(error.code) == NSURLErrorCannotFindHost
                    expectation.fulfill()
                }
            }, receiveValue: { _ in
                fail("should not receive a value")
            })
        expect(publisher).toNot(beNil())
        wait(for: [expectation], timeout: 1)
    }

    func testNonTransientNetworkFailureIsLogged() {
        session.allow(.get, "https://api/test", return: NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted, userInfo: nil))
        let expectation = XCTestExpectation(description: "GET /test")
        let publisher = request.start()
            .sink(receiveCompletion: { result in
                switch result {
                case .finished: fail("should not succeed")
                case .failure(_):
                    expect(self.request.errors).toNot(beEmpty())
                    expectation.fulfill()
                }
            }, receiveValue: { _ in
                fail("should not receive a value")
            })
        expect(publisher).toNot(beNil())
        wait(for: [expectation], timeout: 1)
    }
}
