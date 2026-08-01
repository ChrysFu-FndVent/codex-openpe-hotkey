import CodexOpenPEHotkeyCore
import Foundation

final class OpenPEClient {
    private let configuration: RuntimeConfiguration

    init(configuration: RuntimeConfiguration) {
        self.configuration = configuration
    }

    func enhance(
        prompt: String,
        bearerToken: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) throws -> URLSessionDataTask {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.httpBody = try JSONEncoder().encode(EnhancementRequest(prompt: prompt))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(OpenPEClientError.invalidResponse))
                return
            }
            guard let data else {
                completion(.failure(OpenPEClientError.emptyResponse(statusCode: http.statusCode)))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let errorResponse = try? JSONDecoder().decode(EnhancementErrorResponse.self, from: data)
                completion(.failure(OpenPEClientError.httpError(
                    statusCode: http.statusCode,
                    requestID: errorResponse?.requestID
                )))
                return
            }

            do {
                let response = try JSONDecoder().decode(EnhancementResponse.self, from: data)
                let enhanced = response.enhancedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !enhanced.isEmpty else {
                    completion(.failure(OpenPEClientError.emptyEnhancedPrompt))
                    return
                }
                completion(.success(enhanced))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }
}

enum OpenPEClientError: LocalizedError {
    case invalidResponse
    case emptyResponse(statusCode: Int)
    case httpError(statusCode: Int, requestID: String?)
    case emptyEnhancedPrompt

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenPE server returned an invalid response"
        case .emptyResponse(let statusCode):
            return "OpenPE server returned an empty response (HTTP \(statusCode))"
        case .httpError(let statusCode, let requestID):
            if let requestID, !requestID.isEmpty {
                return "OpenPE server returned HTTP \(statusCode), request_id=\(requestID)"
            }
            return "OpenPE server returned HTTP \(statusCode)"
        case .emptyEnhancedPrompt:
            return "OpenPE server returned an empty enhanced prompt"
        }
    }
}
