//
//  ProgressiveResponse.swift
//
//  Created by Steve Madsen on 5/10/20.
//  Copyright © 2021 Light Year Software, LLC.
//

import Foundation
import Combine

public protocol ProgressiveResponse {
    var response: URLResponse? { get set }
    var data: Data { get set }
    var progressPublisher: PassthroughSubject<(received: Int, total: Int64), Never> { get }
    var completion: ((Data?, URLResponse?, Error?) -> Void)? { get set }

    mutating func taskDidReceive(response: URLResponse)
    mutating func taskDidReceive(data: Data)
    func taskDidComplete()
    func taskDidFail(error: Error)
}

public extension ProgressiveResponse {
    mutating func taskDidReceive(response: URLResponse) {
        self.response = response
    }

    mutating func taskDidReceive(data: Data) {
        self.data.append(data)
        let total = (response as? HTTPURLResponse)?.expectedContentLength ?? 0
        progressPublisher.send((received: self.data.count, total: total))
    }

    func taskDidComplete() {
        progressPublisher.send(completion: .finished)
        completion!(data, response, nil)
    }

    func taskDidFail(error: Error) {
        progressPublisher.send(completion: .finished)
        completion!(nil, nil, error)
    }
}
