//
//  Request.swift
//
//  Created by Steve Madsen on 5/8/20.
//  Copyright © 2021 Light Year Software, LLC.
//

import Foundation
import Combine

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
}

enum RequestError: Error {
    case nonHTTPResponse
    case serverFailure(Int)
    case wrongContentType
    case parseError
}

extension Error {
    var transientNetworkError: Bool {
        let error = self as NSError
        guard error.domain == NSURLErrorDomain else { return false }
        switch error.code {
        case NSURLErrorCancelled,
             NSURLErrorTimedOut,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorUserCancelledAuthentication,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive,
             NSURLErrorDataNotAllowed:
            return true

        default:
            return false
        }
    }
}

var RequestBaseURL: URL?
var RequestLogError: ((String, _: [String: Any]?) -> Void)?

protocol Request {
    associatedtype ContextType
    associatedtype ModelType

    var method: HTTPMethod { get }
    var url: URL { get }
    var scheme: String { get }
    var host: String { get }
    var path: String { get }
    var queryItems: [URLQueryItem] { get }
    var contentType: String { get }
    var headers: [String: String] { get }
    var body: Data? { get }
    var bodyStream: (stream: InputStream, size: Int)? { get }
    var expectedResponseType: String? { get }
    var successStatusCodes: Set<Int> { get }

    func parseResponse(context: ContextType?, data: Data) throws -> ModelType
}

protocol RequestSession {
    func dataTask(with request: URLRequest) -> URLSessionDataTask
    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask
}

extension URLSession: RequestSession {}

extension Request {
    var method: HTTPMethod { .get }
    var scheme: String { "https" }
    var queryItems: [URLQueryItem] { [] }
    var contentType: String { "application/json" }
    var body: Data? { nil }
    var bodyStream: (stream: InputStream, size: Int)? { nil }
    var expectedResponseType: String? { "application/json" }
    var successStatusCodes: Set<Int> {
        Set(200..<300)
    }

    var url: URL {
        var urlComponents = URLComponents()
        urlComponents.scheme = scheme
        urlComponents.host = host
        urlComponents.path = path
        urlComponents.queryItems = queryItems.isEmpty ? nil : queryItems
        return urlComponents.url!
    }

    var headers: [String: String] { ["Accept": "application/json"] }

    func start() -> AnyPublisher<ModelType, Error> {
        start(on: RunLoop.current, context: nil)
    }

    func start(context: ContextType) -> AnyPublisher<ModelType, Error> {
        start(on: RunLoop.current, context: context)
    }

    func start<S: Scheduler>(on scheduler: S, context: ContextType?) -> AnyPublisher<ModelType, Error> {
        let startedAt = Date()
        let request = buildRequest()
        return startTask(request: request)
            .handleEvents(receiveOutput: { logResponse(startedAt: startedAt, request: request, result: $0) },
                          receiveCompletion: { logFailure(request: request, completion: $0) })
            .tryMap { try validateStatus(result: $0) }
            .tryMap { try validateContentType(result: $0) }
            .receive(on: scheduler)
            .flatMap { parse(context: context, data: $0.data) }
            .eraseToAnyPublisher()
    }

    private func buildRequest() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        print("⤴️ \(request.httpMethod?.uppercased() ?? "") \(request.url?.absoluteString ?? "?")")
        if let body = body {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        } else if let body = bodyStream {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.setValue("\(body.size)", forHTTPHeaderField: "Content-Length")
            request.httpBodyStream = body.stream
        }
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    private func startTask(request: URLRequest) -> AnyPublisher<(response: HTTPURLResponse, data: Data?), Error> {
        guard ProcessInfo.processInfo.environment["SIMULATE_NO_NETWORK"] == nil else {
            return Fail<(response: HTTPURLResponse, data: Data?), Error>(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)).eraseToAnyPublisher()
        }

        return Future<(response: HTTPURLResponse, data: Data?), Error> { promise in
            let task: URLSessionDataTask
            let completion: (Data?, URLResponse?, Error?) -> Void = { data, response, error in
                if let error = error {
                    promise(.failure(error))
                } else if let httpResponse = response as? HTTPURLResponse {
                    promise(.success((httpResponse, data)))
                } else {
                    promise(.failure(RequestError.nonHTTPResponse))
                }
            }
            if var self = self as? ProgressiveResponse {
                self.completion = completion
                task = RequestTaskManager.shared.session.dataTask(with: request)
                RequestTaskManager.shared.track(task: task, request: self)
            } else {
                task = RequestTaskManager.shared.session.dataTask(with: request, completionHandler: completion)
            }
            task.resume()
        }.eraseToAnyPublisher()
    }

    private func logResponse(startedAt: Date, request: URLRequest, result: (response: HTTPURLResponse, data: Data?)) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let bytes = result.data?.count ?? 0
        if successStatusCodes.contains(result.response.statusCode) {
            print("⤵️ \(request.httpMethod?.uppercased() ?? "") \(request.url?.absoluteString ?? "?") [\(result.response.statusCode) | \(bytes) bytes in \(String(format: "%.3fs", elapsed))]")
        } else {
            print("❌ \(request.httpMethod?.uppercased() ?? "") \(request.url?.absoluteString ?? "?") [\(result.response.statusCode) | \(bytes) bytes in \(String(format: "%.3fs", elapsed))]")
            RequestLogError?("\(Self.self) \(result.response.statusCode)", ["url": request.url?.absoluteString ?? "?", "requestBody": String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "<not UTF-8>", "response": String(data: result.data ?? Data(), encoding: .utf8) ?? "<not UTF-8>"])
        }
    }

    private func logFailure(request: URLRequest, completion: Subscribers.Completion<Error>) {
        guard case let .failure(error) = completion else { return }
        print("❌ \(request.httpMethod?.uppercased() ?? "") \(request.url?.absoluteString ?? "?") \(error)")
        if !error.transientNetworkError {
            RequestLogError?("\(Self.self) network error", ["error": "\(error)", "url": request.url?.absoluteString ?? "?"])
        }
    }

    private func validateStatus(result: (response: HTTPURLResponse, data: Data?)) throws -> (response: HTTPURLResponse, data: Data?) {
        if !successStatusCodes.contains(result.response.statusCode) {
            throw RequestError.serverFailure(result.response.statusCode)
        }
        return result
    }

    private func validateContentType(result: (response: HTTPURLResponse, data: Data?)) throws -> (response: HTTPURLResponse, data: Data?) {
        guard let expectedType = self.expectedResponseType else { return result }
        guard let responseType = result.response.value(forHTTPHeaderField: "Content-Type"),
              responseType == expectedType || responseType.hasPrefix("\(expectedType); charset")
        else { throw RequestError.wrongContentType }
        return result
    }

    private func parse(context: ContextType?, data: Data?) -> AnyPublisher<ModelType, Error> {
        Future<ModelType, Error> { promise in
            guard let data = data else {
                promise(.failure(RequestError.parseError))
                return
            }

            do {
                let model = try parseResponse(context: context, data: data)
                promise(.success(model))
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }
}

extension Request where ContextType: Scheduler {
    func start(context: ContextType) -> AnyPublisher<ModelType, Error> {
        start(on: context, context: context)
    }
}

extension Request {
    func encode<T: Encodable>(_ object: T) throws -> Data {
        let encoder = JSONEncoder()
#if DEBUG
        encoder.outputFormatting = .prettyPrinted
#endif
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(object)

        if let string = String(data: data, encoding: .utf8) {
            print(string)
        }

        return data
    }
}

fileprivate let iso8601WithMilliseconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

extension Request {
    func decode<T: Decodable>(_ jsonType: T.Type, from data: Data) throws -> T {
#if DEBUG
        if let string = String(data: data, encoding: .utf8) {
            print(string)
        }
#endif
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom({
            let container = try $0.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601WithMilliseconds.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "“\(string)” does not appear to be a valid ISO8601 date")
        })
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let object = try decoder.decode(T.self, from: data)

        return object
    }
}
