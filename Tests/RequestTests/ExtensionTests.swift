//
//  ExtensionTests.swift
//
//  Created by Steve Madsen on 5/6/21.
//  Copyright © 2021 Light Year Software, LLC.
//  

import XCTest
import Nimble
import Request

private struct TestRequest: Request {
    let baseURL: URL
    let path: String
    let queryItems: [URLQueryItem]

    init(baseURL: URL, path: String, queryItems: [URLQueryItem] = []) {
        self.baseURL = baseURL
        self.path = path
        self.queryItems = queryItems
    }

    func parseResponse(context: Void?, data: Data) throws {
    }
}

private protocol ServiceRequest: Request {}

private extension ServiceRequest {
    var baseURL: URL { URL(string: "https://my.service/")! }
}

private struct TestServiceRequest: ServiceRequest {
    let path = "endpoint"

    func parseResponse(context: Void?, data: Data) throws {
    }
}

class ExtensionTests: XCTestCase {
    func testURL() {
        var request = TestRequest(baseURL: URL(string: "https://example.test")!, path: "foo/bar")
        expect(request.url.absoluteString) == "https://example.test/foo/bar"

        request = TestRequest(baseURL: URL(string: "https://example.test/foo")!, path: "/bar")
        expect(request.url.absoluteString) == "https://example.test/bar"

        request = TestRequest(baseURL: URL(string: "https://example.test")!, path: "foo", queryItems: [URLQueryItem(name: "q", value: "value")])
        expect(request.url.absoluteString) == "https://example.test/foo?q=value"
    }

    func testDerivedProtocol() {
        expect(TestServiceRequest().url.absoluteString) == "https://my.service/endpoint"
    }
}
