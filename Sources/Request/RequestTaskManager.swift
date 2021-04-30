//
//  RequestTaskManager.swift
//
//  Created by Steve Madsen on 5/10/20.
//  Copyright © 2021 Light Year Software, LLC.
//

import Foundation

open class RequestTaskManager: NSObject, URLSessionDelegate, URLSessionDataDelegate {
    public static var shared = RequestTaskManager()

    public var session: RequestSession!
    private var activeRequests = [URLSessionTask: ProgressiveResponse]()

    override private init() {
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    func track(task: URLSessionDataTask, request: ProgressiveResponse) {
        activeRequests[task] = request
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard var request = activeRequests[dataTask] else {
            assertionFailure("Callback for untracked task")
            return
        }

        request.taskDidReceive(response: response)
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard var request = activeRequests[dataTask] else {
            assertionFailure("Callback for untracked task")
            return
        }

        request.taskDidReceive(data: data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let request = activeRequests[task] else {
            assertionFailure("Callback for untracked task")
            return
        }

        if let error = error {
            request.taskDidFail(error: error)
        } else {
            request.taskDidComplete()
        }

        activeRequests[task] = nil
    }
}
