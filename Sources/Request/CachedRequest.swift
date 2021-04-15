//
//  CachedRequest.swift
//
//  Created by Steve Madsen on 1/17/21.
//  Copyright © 2021 Light Year Software, LLC.
//

import Foundation
import Combine

protocol CachedRequest: Request {
    func cachedResponse(context: ContextType?) -> ModelType?
}

extension CachedRequest {
    func start() -> AnyPublisher<ModelType, Error> {
        if checkCache(), let cache = cachedResponse(context: nil) {
            return Just(cache).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        return start(on: RunLoop.current, context: nil)
    }

    func start(context: ContextType) -> AnyPublisher<ModelType, Error> {
        if checkCache(), let cache = cachedResponse(context: context) {
            return Just(cache).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        return start(on: RunLoop.current, context: context)
    }

    private func checkCache() -> Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment["IGNORE_REQUEST_CACHE"] == nil
#else
        return true
#endif
    }
}

extension CachedRequest where ContextType: Scheduler {
    func start(context: ContextType) -> AnyPublisher<ModelType, Error> {
        if checkCache(), let cache = cachedResponse(context: context) {
            return Just(cache).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        return start(on: context, context: context)
    }
}
