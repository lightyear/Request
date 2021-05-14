//
//  TestSession.swift
//
//  Created by Steve Madsen on 5/8/20.
//  Copyright © 2021 Light Year Software, LLC.
//

import Foundation

open class TestSession: RequestSession {
    public enum Request {
        case get(String, headers: [String: String] = [:])
        case post(String, body: Data = Data(), headers: [String: String] = [:])
        case put(String, body: Data = Data(), headers: [String: String] = [:])
        case delete(String, headers: [String: String] = [:])

        func matches(_ urlRequest: URLRequest) -> Bool {
            switch self {
            case .get(let url, let headers):
                return urlRequest.httpMethod?.uppercased() == "GET"
                    && urlRequest.url?.absoluteString == url
                    && headers.allSatisfy { urlRequest.allHTTPHeaderFields?[$0.key] == $0.value }
            case .post(let url, _, let headers):
                return urlRequest.httpMethod?.uppercased() == "POST"
                    && urlRequest.url?.absoluteString == url
                    && headers.allSatisfy { urlRequest.allHTTPHeaderFields?[$0.key] == $0.value }
            case .put(let url, _, let headers):
                return urlRequest.httpMethod?.uppercased() == "PUT"
                    && urlRequest.url?.absoluteString == url
                    && headers.allSatisfy { urlRequest.allHTTPHeaderFields?[$0.key] == $0.value }
            case .delete(let url, let headers):
                return urlRequest.httpMethod?.uppercased() == "DELETE"
                    && urlRequest.url?.absoluteString == url
                    && headers.allSatisfy { urlRequest.allHTTPHeaderFields?[$0.key] == $0.value }
            }
        }
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

    private var stubRequests = [(request: Request, response: Response)]()

    public init() {
    }

    public func reset() {
        stubRequests = []
    }

    public func allow(_ request: Request, return status: Int, headers: [String: String] = ["Content-Type": "application/json"], body: String = "") {
        stubRequests.append((request, Response(status: status, headers: headers, body: body)))
    }

    public func allow(_ request: Request, return error: Error) {
        stubRequests.append((request, .networkError(error)))
    }

    public func dataTask(with request: URLRequest) -> URLSessionDataTask {
        fatalError("not implemented")
    }

    public func dataTask(with urlRequest: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        guard let stub = stubRequests.first(where: { $0.request.matches(urlRequest) })
        else {
            return TestDataTask { completionHandler(nil, nil, SessionError.notAllowed("\(urlRequest.httpMethod ?? "unknown-method") \(urlRequest.url?.absoluteString ?? "unknown-url") is not allowed here")) }
        }

        switch stub.response {
        case .http(let status, let headers, let body):
            let httpResponse = HTTPURLResponse(url: urlRequest.url!, statusCode: status, httpVersion: "1.1", headerFields: headers.merging(["Content-Length": "\(body.count)"]) { _, other in other })
            return TestDataTask { completionHandler(body, httpResponse, nil) }
        case .networkError(let error):
            return TestDataTask { completionHandler(nil, nil, error) }
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
