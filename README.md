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

Your types don't have to be `struct`s. If you wished, you could have a base type that defined sensible defaults for a hierarchy of requests, such as a request scheme and host:

```
class BaseAPI {
    let host = "jsonplaceholder.typicode.com"
}

class GetUsersRequest: BaseAPI, Request {
    typealias ModelType = [User]
    typealias ContextType = Void

    let method = HTTPMethod.get
    let path = "/users"

    func parseResponse(context: Void?, data: Data) throws -> [User] {
        try decode([User].self, from: data)
    }
}
```

Or you could override the protocol extension in the library to provide a default for any types that don't provide their own value for a property:

```
extension Request {
    var host: String { "jsonplaceholder.typicode.com" }
}
```

## Testing

The library includes a `TestSession` type that can be assigned to the shared `RequestTaskManager.shared.session` property. This provides a way to set up mocks and expectations on network requests without generating real network activity. An example is in [RequestTests.swift](Tests/RequestTests/RequestTests.swift).

## Contributing

This library is maintained by [@sjmadsen](https://github.com/sjmadsen). Bug reports, feature requests and PRs are appreciated!
