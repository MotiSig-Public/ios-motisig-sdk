import Foundation

final class HTTPClient {
    private let session: URLSession
    private let configuration: Configuration
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }()
    private let decoder = JSONDecoder()

    init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    // MARK: - Typed response, with body

    func request<Body: Encodable, T: Decodable>(
        _ endpoint: Endpoint,
        body: Body,
        responseType: T.Type
    ) async throws -> T {
        let data = try await perform(endpoint, body: body)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MotiSigError.decodingError(error)
        }
    }

    // MARK: - Void response, with body

    func request<Body: Encodable>(
        _ endpoint: Endpoint,
        body: Body
    ) async throws {
        _ = try await perform(endpoint, body: body)
    }

    // MARK: - Void response, no body

    func request(_ endpoint: Endpoint) async throws {
        _ = try await perform(endpoint)
    }

    // MARK: - Typed response, no body (e.g. GET)

    func request<T: Decodable>(
        _ endpoint: Endpoint,
        responseType: T.Type
    ) async throws -> T {
        let data = try await perform(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MotiSigError.decodingError(error)
        }
    }

    /// `GET /users/{id}` — returns `nil` when the server responds **404** (Expo `getUser` parity).
    func getUser(userId: String) async throws -> MotiSigUser? {
        let data = try await sendAllowing404(.getUser(userId: userId), body: nil)
        guard let data, !data.isEmpty else { return nil }
        do {
            let decoded = try decoder.decode(UserResponse.self, from: data)
            guard let user = decoded.user else { return nil }
            return MotiSigUser(jsonValue: user)
        } catch {
            throw MotiSigError.decodingError(error)
        }
    }

    /// `POST /users/{id}/ping` with one retry after **1.5s** on transport failure (Expo `ping` parity).
    func requestPingWithNetworkRetry(userId: String) async throws {
        do {
            try await request(.ping(userId: userId))
        } catch let err as MotiSigError {
            if case .networkError = err {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                try await request(.ping(userId: userId))
            } else {
                throw err
            }
        }
    }

    // MARK: - Private

    private func perform<Body: Encodable>(
        _ endpoint: Endpoint,
        body: Body
    ) async throws -> Data {
        let encodedBody: Data
        do {
            encodedBody = try encoder.encode(body)
        } catch {
            throw MotiSigError.encodingError(error)
        }

        return try await send(endpoint, body: encodedBody)
    }

    private func perform(_ endpoint: Endpoint) async throws -> Data {
        try await send(endpoint, body: nil)
    }

    private func send(_ endpoint: Endpoint, body: Data?) async throws -> Data {
        let urlRequest = endpoint.urlRequest(
            baseURL: configuration.baseURL,
            sdkKey: configuration.sdkKey,
            projectId: configuration.projectId,
            body: body
        )

        Logger.shared.debug("[\(endpoint.method.rawValue)] \(urlRequest.url?.absoluteString ?? "")")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw MotiSigError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MotiSigError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = (try? decoder.decode(ErrorResponseBody.self, from: data))?.error
            throw MotiSigError.apiError(
                statusCode: httpResponse.statusCode,
                message: errorMessage
            )
        }

        return data
    }

    private func sendAllowing404(_ endpoint: Endpoint, body: Data?) async throws -> Data? {
        let urlRequest = endpoint.urlRequest(
            baseURL: configuration.baseURL,
            sdkKey: configuration.sdkKey,
            projectId: configuration.projectId,
            body: body
        )

        Logger.shared.debug("[\(endpoint.method.rawValue)] \(urlRequest.url?.absoluteString ?? "")")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw MotiSigError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MotiSigError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = (try? decoder.decode(ErrorResponseBody.self, from: data))?.error
            throw MotiSigError.apiError(
                statusCode: httpResponse.statusCode,
                message: errorMessage
            )
        }

        return data
    }
}
