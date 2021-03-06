//
//  Request.swift
//
//  Created by Steve Madsen on 5/8/20.
//  Copyright © 2021 Light Year Software, LLC.
//

import Foundation
import Combine

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
}

public enum RequestError: Error {
    case nonHTTPResponse
    case serverFailure(Int)
    case wrongContentType
    case parseError
}

public extension Error {
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

public protocol Request {
    associatedtype ContextType
    associatedtype ModelType

    var method: HTTPMethod { get }
    var baseURL: URL { get }
    var url: URL { get }
    var path: String { get }
    var queryItems: [URLQueryItem] { get }
    var contentType: String { get }
    var headers: [String: String] { get }
    var body: Data? { get }
    var bodyStream: (stream: InputStream, size: Int)? { get }
    var expectedResponseType: String? { get }
    var successStatusCodes: Set<Int> { get }

    var decoder: JSONDecoder { get }
    var encoder: JSONEncoder { get }

    func parseResponse(context: ContextType?, data: Data) throws -> ModelType
    func parseError(status: Int, data: Data?) -> Error
    func logDebug(_ message: String)
    func logError(_ message: String, data: [String: Any])
}

public protocol RequestSession {
    func dataTask(with request: URLRequest) -> URLSessionDataTask
    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask
}

extension URLSession: RequestSession {}

public extension Request {
    var method: HTTPMethod { .get }
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
        urlComponents.path = path

        if !queryItems.isEmpty {
            var querySafe = CharacterSet.urlQueryAllowed
            querySafe.remove("+")
            urlComponents.percentEncodedQuery = queryItems.map {
                "\($0.name.addingPercentEncoding(withAllowedCharacters: querySafe)!)=\($0.value?.addingPercentEncoding(withAllowedCharacters: querySafe) ?? "")"
            }.joined(separator: "&")
        }

        return urlComponents.url(relativeTo: baseURL)!
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
            .flatMap { parse(response: $0.response, context: context, data: $0.data) }
            .eraseToAnyPublisher()
    }

    private func buildRequest() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        logDebug("⤴️ \(request.httpMethod?.uppercased() ?? "") \(request.url?.absoluteString ?? "?")")
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
            logDebug("⤵️ \(request.httpMethod?.uppercased() ?? "") \(request.url?.absoluteString ?? "?") [\(result.response.statusCode) | \(bytes) bytes in \(String(format: "%.3fs", elapsed))]")
        } else {
            logDebug("❌ \(request.httpMethod?.uppercased() ?? "") \(request.url?.absoluteString ?? "?") [\(result.response.statusCode) | \(bytes) bytes in \(String(format: "%.3fs", elapsed))]")
            logError("\(Self.self) \(result.response.statusCode)",
                     data: ["url": request.url?.absoluteString ?? "?",
                            "requestBody": String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "<not UTF-8>",
                            "response": String(data: result.data ?? Data(), encoding: .utf8) ?? "<not UTF-8>"
                     ])
        }
    }

    private func logFailure(request: URLRequest, completion: Subscribers.Completion<Error>) {
        guard case let .failure(error) = completion else { return }
        logDebug("❌ \(request.httpMethod?.uppercased() ?? "") \(request.url?.absoluteString ?? "?") \(error)")
        if !error.transientNetworkError {
            logError("\(Self.self) network error", data: ["error": "\(error)", "url": request.url?.absoluteString ?? "?"])
        }
    }

    private func validateStatus(result: (response: HTTPURLResponse, data: Data?)) throws -> (response: HTTPURLResponse, data: Data?) {
        if !successStatusCodes.contains(result.response.statusCode) {
            throw parseError(status: result.response.statusCode, data: result.data)
        }
        return result
    }

    func parseError(status: Int, data: Data?) -> Error {
        RequestError.serverFailure(status)
    }

    private func validateContentType(result: (response: HTTPURLResponse, data: Data?)) throws -> (response: HTTPURLResponse, data: Data?) {
        guard result.data?.isEmpty == false else { return result }
        guard let expectedType = self.expectedResponseType else { return result }
        guard let responseType = result.response.value(forHTTPHeaderField: "Content-Type"),
              responseType == expectedType || responseType.hasPrefix("\(expectedType); charset")
        else { throw RequestError.wrongContentType }
        return result
    }

    private func parse(response: HTTPURLResponse, context: ContextType?, data: Data?) -> AnyPublisher<ModelType, Error> {
        Future<ModelType, Error> { promise in
            let contentLength = response.value(forHTTPHeaderField: "Content-Length")
            do {
                if let data = data {
                    promise(.success(try parseResponse(context: context, data: data)))
                } else if contentLength == "0" {
                    promise(.success(try parseResponse(context: context, data: Data())))
                } else {
                    promise(.failure(RequestError.parseError))
                }
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    func logDebug(_ message: String) {
        print(message)
    }

    func logError(_ message: String, data: [String: Any]) {
        print("\(message) \(data)")
    }
}

public extension Request where ContextType: Scheduler {
    func start(context: ContextType) -> AnyPublisher<ModelType, Error> {
        start(on: context, context: context)
    }
}

public extension Request {
    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
#if DEBUG
        encoder.outputFormatting = .prettyPrinted
#endif
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    func encode<T: Encodable>(_ object: T) throws -> Data {
        let data = try encoder.encode(object)

        if let string = String(data: data, encoding: .utf8) {
            logDebug(string)
        }

        return data
    }
}

private let iso8601WithMilliseconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

public extension Request {
    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom {
            let container = try $0.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601WithMilliseconds.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "“\(string)” does not appear to be a valid ISO8601 date")
        }
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    func decode<T: Decodable>(_ jsonType: T.Type, from data: Data) throws -> T {
#if DEBUG
        if let string = String(data: data, encoding: .utf8) {
            logDebug(string)
        }
#endif

        return try decoder.decode(T.self, from: data)
    }
}
