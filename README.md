# Request

Request is a simple Combine-based wrapper around `URLSession`.

* An endpoint is defined in its own `Request`-conforming type.
* These types define how to talk to that endpoint, falling back to sensible defaults.
* Each type declares the model type it returns and optionally a context type.
* A context can be provided when you start a request and it will be given back to parse the response.

## Installing

Add Request to your project using Swift Package Manager in Xcode or to your `dependencies` in `Package.swift`:

```
.package(url: "https://github.com/lightyear/Request", from: "0.1.0")
```

## Example

These examples use the models at [JSONPlaceholder](https://jsonplaceholder.typicode.com). For example, the `/users` endpoint returns data like this:

```
[
    {
        "id": 1,
        "name": "Leanne Graham",
        "username": "Bret",
        "email": "Sincere@april.biz",
        "address": {
            "street": "Kulas Light",
            "suite": "Apt. 556",
            "city": "Gwenborough",
            "zipcode": "92998-3874",
            "geo": {
                "lat": "-37.3159",
                "lng": "81.1496"
            }
        },
        "phone": "1-770-736-8031 x56442",
        "website": "hildegard.org",
        "company": {
            "name": "Romaguera-Crona",
            "catchPhrase": "Multi-layered client-server neural-net",
            "bs": "harness real-time e-markets"
        }
    },
    ...
]
```

This could be modeled in a `Codable` type:

```
struct User: Codable {
    var id: Int
    var name: String
    var username: String
    var email: String
    // etc...
}
```

Here is a `Request`-conforming type to fetch the list of users:

```
struct GetUsersRequest: Request {
    typealias ModelType = [User]
    typealias ContextType = Void

    let method = HTTPMethod.get
    let host = "jsonplaceholder.typicode.com"
    let path = "/users"

    func parseResponse(context: Void?, data: Data) throws -> [User] {
        try decode([User].self, from: data)
    }
}
```

To make the request and do something with the returned list of users:

```
GetUsersRequest().start()
    .catch {
        // handle errors
    }.sink {
        // $0 is an array of User instances
    }
```


## Customization

### Declaring a base URL

Your types don't have to be `struct`s. If you wished, you could have a base type that defined sensible defaults for a hierarchy of requests, such as a base URL:

```
class BaseAPI {
    let baseURL = URL(string: "https://jsonplaceholder.typicode.com/"
}

class GetUsersRequest: BaseAPI, Request {
    let path = "users"

    func parseResponse(context: Void?, data: Data) throws -> [User] {
        try decode([User].self, from: data)
    }
}
```

Or you could introduce your own small protocol to provide a default:

```
protocol JSONPlaceholderRequest: Request {}

extension JSONPlaceholderRequest {
    var baseURL = URL(string: "https://jsonplaceholder.typicode.com/" }
}

struct GetUsersRequest: JSONPlaceholderRequest {
    let path = "users"

    func parseResponse(context: Void?, data: Data) throws -> [User] {
        try decode([User].self, from: data)
    }
}
```

### Logging

The `Request` protocol declares two functions that are used for reporting some basic diagnostics: `logDebug()` and `logError()`. The former is used for request lifecycle events and the latter for non-transient network errors. Transient errors are ones that are expected to occur on real-world networks, like user cancellations, time outs, connection errors and network unavailability. These errors still fail the request, but the `logError()` function gives you a single place to log non-transient errors so you don't have to put those log statements everywhere in your app.

The protocol extension implements these functions by `print()`-ing them to the debug console, but you can override them to provide different behavior:

```
extension Request {
    func logDebug(_ message: String) {
    }
    
    func logError(_ message: String, data: [String: Any]) {
        // data includes additional details about the request that failed and
        // the error
    }
```

## Testing

The library includes a `TestSession` type that can be assigned to the shared `RequestTaskManager.shared.session` property. This provides a way to set up mocks and expectations on network requests without generating real network activity. An example is in [RequestTests.swift](Tests/RequestTests/RequestTests.swift).

## Contributing

This library is maintained by [@sjmadsen](https://github.com/sjmadsen). Bug reports, feature requests and PRs are appreciated!
