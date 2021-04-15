//
//  RequestTaskManager.swift
//
//  Created by Steve Madsen on 5/10/20.
//  Copyright © 2021 Light Year Software, LLC.
//

import Foundation

class RequestTaskManager: NSObject, URLSessionDelegate, URLSessionDataDelegate {
    static var shared = RequestTaskManager()

    var session: RequestSession!
    private var activeRequests = [URLSessionTask: ProgressiveResponse]()

    override private init() {
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    func track(task: URLSessionDataTask, request: ProgressiveResponse) {
        activeRequests[task] = request
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard var request = activeRequests[dataTask] else {
            RequestLogError?("Callback for untracked task", ["url": "\(dataTask.originalRequest?.url?.absoluteString ?? "nil")"])
            return
        }

        request.taskDidReceive(response: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard var request = activeRequests[dataTask] else {
            RequestLogError?("Callback for untracked task", ["url": "\(dataTask.originalRequest?.url?.absoluteString ?? "nil")"])
            return
        }

        request.taskDidReceive(data: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let request = activeRequests[task] else {
            RequestLogError?("Callback for untracked task", ["url": "\(task.originalRequest?.url?.absoluteString ?? "nil")"])
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
