//
//  TestSessionTests.swift
//  
//
//  Created by Steve Madsen on 5/14/21.
//

import XCTest
import Nimble
@testable import Request

class TestSessionTests: XCTestCase {
    func testRequestMatchesMethodAndURL() {
        let request = TestSession.Request.get("http://example.test/")
        var urlRequest = URLRequest(url: URL(string: "http://example.test/")!)
        expect(request.matches(urlRequest)) == true

        urlRequest.httpMethod = "get"
        expect(request.matches(urlRequest)) == true

        urlRequest.httpMethod = "POST"
        expect(request.matches(urlRequest)) == false
        expect(TestSession.Request.post("http://example.test/").matches(urlRequest)) == true

        urlRequest.httpMethod = "PUT"
        expect(TestSession.Request.put("http://example.test/").matches(urlRequest)) == true

        urlRequest.httpMethod = "DELETE"
        expect(TestSession.Request.delete("http://example.test/").matches(urlRequest)) == true
    }

    func testRequestMatchesRequiredHeaders() {
        let headers = ["foo": "bar"]
        var urlRequest = URLRequest(url: URL(string: "http://example.test/")!)
        expect(TestSession.Request.get("http://example.test/", headers: headers).matches(urlRequest)) == false

        urlRequest.httpMethod = "POST"
        expect(TestSession.Request.post("http://example.test/", headers: headers).matches(urlRequest)) == false

        urlRequest.httpMethod = "PUT"
        expect(TestSession.Request.put("http://example.test/", headers: headers).matches(urlRequest)) == false

        urlRequest.httpMethod = "DELETE"
        expect(TestSession.Request.delete("http://example.test/", headers: headers).matches(urlRequest)) == false

        urlRequest.httpMethod = "GET"
        urlRequest.addValue("bar", forHTTPHeaderField: "foo")
        expect(TestSession.Request.get("http://example.test/", headers: headers).matches(urlRequest)) == true

        urlRequest.httpMethod = "POST"
        expect(TestSession.Request.post("http://example.test/", headers: headers).matches(urlRequest)) == true

        urlRequest.httpMethod = "PUT"
        expect(TestSession.Request.put("http://example.test/", headers: headers).matches(urlRequest)) == true

        urlRequest.httpMethod = "DELETE"
        expect(TestSession.Request.delete("http://example.test/", headers: headers).matches(urlRequest)) == true
    }
}
