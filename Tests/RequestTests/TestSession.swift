//
//  TestSession.swift
//
//  Created by Steve Madsen on 5/8/20.
//  Copyright © 2021 Light Year Software, LLC.
//

import Foundation
@testable import Request

class TestSession: RequestSession {
    struct Request: Hashable {
        let method: HTTPMethod
        let url: String
    }

    enum Response {
        case http(status: Int, headers: [String: String], body: Data)
        case networkError(Error)

        init(status: Int, headers: [String: String] = [:], body: String) {
            self = .http(status: status, headers: headers, body: body.data(using: .utf8)!)
        }
    }

    enum SessionError: Error {
        case notAllowed(String)
    }

    private var stubRequests = [Request: Response]()

    func reset() {
        stubRequests = [:]
    }

    func allow(_ method: HTTPMethod, _ url: String, return status: Int, headers: [String: String] = ["Content-Type": "application/json"], body: String = "") {
        stubRequests[Request(method: method, url: url)] = Response(status: status, headers: headers, body: body)
    }

    func allow(_ method: HTTPMethod, _ url: String, return error: Error) {
        stubRequests[Request(method: method, url: url)] = .networkError(error)
    }

    func dataTask(with request: URLRequest) -> URLSessionDataTask {
        fatalError("not implemented")
    }

    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        let req = Request(method: HTTPMethod(rawValue: request.httpMethod!)!, url: request.url!.absoluteString)
        if case .http(let status, let headers, let body) = stubRequests[req] {
            let httpResponse = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "1.1", headerFields: headers.merging(["Content-Length": "\(body.count)"]) { _, other in other })
            return TestDataTask { completionHandler(body, httpResponse, nil) }
        } else if case .networkError(let error) = stubRequests[req] {
            return TestDataTask { completionHandler(nil, nil, error) }
        } else {
            return TestDataTask { completionHandler(nil, nil, SessionError.notAllowed("\(req.method) \(req.url) is not allowed here")) }
        }
    }
}

class TestDataTask: URLSessionDataTask {
    let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    override func resume() {
        completion()
    }
}
