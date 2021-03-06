//
//  RequestTests.swift
//
//  Created by Steve Madsen on 5/8/20.
//  Copyright © 2021 Light Year Software, LLC.
//

import XCTest
import Nimble
@testable import Request

class RequestTests: XCTestCase {
    let session = TestSession()
    private var request = TestRequest()

    override func setUpWithError() throws {
        try super.setUpWithError()
        RequestTaskManager.shared.session = session
    }

    func testSuccess() {
        session.allow(.get("https://api/test"), return: 200, body: "1")
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
        session.allow(.get("https://api/test"), return: 500, body: "1")
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

    func testCustomErrorHandler() {
        session.allow(.get("https://api/test"), return: 500, body: "{}")
        let expectation = XCTestExpectation(description: "GET /test")
        let publisher = CustomErrorRequest().start()
            .sink(receiveCompletion: { result in
                switch result {
                case .finished: fail("should not succeed")
                case .failure(let error as NSError):
                    expect(error.domain) == "TestDomain"
                    expect(error.code) == 500
                    expect(error.userInfo["body"] as? Data) == "{}".data(using: .utf8)
                    expectation.fulfill()
                }
            }, receiveValue: { _ in
                fail("should not receive a value")
            })
        expect(publisher).toNot(beNil())
        wait(for: [expectation], timeout: 1)
    }

    func testInvalidResponseType() {
        session.allow(.get("https://api/test"), return: 200, headers: ["Content-Type": "text/html"], body: "a")
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

    func testEmptyResponse() {
        session.allow(.get("https://api/test"), return: 204, headers: ["Content-Length": "0"], body: "")
        let expectation = XCTestExpectation(description: "GET /test")
        let publisher = EmptyResponseRequest().start()
            .sink(receiveCompletion: { result in
                switch result {
                case .finished: expectation.fulfill()
                case .failure:  fail("should not fail")
                }
            }, receiveValue: {
                expect($0) == 1
            })
        expect(publisher).toNot(beNil())
        wait(for: [expectation], timeout: 1)
    }

    func testParsingFailure() {
        session.allow(.get("https://api/test"), return: 200, body: "a")
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
        session.allow(.get("https://api/test"), return: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: nil))
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
        session.allow(.get("https://api/test"), return: NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted, userInfo: nil))
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

private class EmptyResponseRequest: Request {
    let baseURL = URL(string: "https://api")!
    let path = "/test"

    func parseResponse(context: Void?, data: Data) throws -> Int {
        1
    }
}

private class CustomErrorRequest: Request {
    let baseURL = URL(string: "https://api")!
    let path = "/test"

    func parseResponse(context: Void?, data: Data) throws {
    }

    func parseError(status: Int, data: Data?) -> Error {
        NSError(domain: "TestDomain", code: status, userInfo: ["body": data!])
    }
}
