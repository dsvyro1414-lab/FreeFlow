import Foundation

public enum CloudTranscriptionService: Equatable, Sendable {
  case openAI(model: String)
  case xAI
  case groq(model: String)

  public var credentialProvider: CloudAPIProvider {
    switch self {
    case .openAI: .openAI
    case .xAI: .xAI
    case .groq: .groq
    }
  }

  var providerName: String {
    credentialProvider.title
  }

  var endpoint: URL {
    switch self {
    case .openAI:
      URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    case .xAI:
      URL(string: "https://api.x.ai/v1/stt")!
    case .groq:
      URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    }
  }

  var multipartFields: [(name: String, value: String)] {
    switch self {
    case .openAI(let model), .groq(let model):
      [
        ("model", model),
        ("language", "en"),
      ]
    case .xAI:
      [
        ("format", "true"),
        ("language", "en"),
        // Preserve fillers at the provider boundary so the app-level toggle
        // remains the single source of truth for transcript cleanup.
        ("filler_words", "true"),
      ]
    }
  }
}

public enum CloudTranscriptionError: LocalizedError, Equatable, Sendable {
  case missingAPIKey(provider: String)
  case invalidResponse(provider: String)
  case requestFailed(provider: String, message: String)

  public var errorDescription: String? {
    switch self {
    case .missingAPIKey(let provider):
      "Add your \(provider) API key in Settings."
    case .invalidResponse(let provider):
      "\(provider) returned an invalid transcription response."
    case .requestFailed(let provider, let message):
      "\(provider) transcription failed: \(message)"
    }
  }
}

protocol CloudHTTPClient: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

private struct URLSessionCloudHTTPClient: CloudHTTPClient {
  let session: URLSession

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await session.data(for: request)
  }
}

public actor CloudTranscriber {
  private let client: any CloudHTTPClient

  public init(session: URLSession = .shared) {
    client = URLSessionCloudHTTPClient(session: session)
  }

  init(client: any CloudHTTPClient) {
    self.client = client
  }

  public func transcribe(
    _ audioURL: URL,
    apiKey: String,
    service: CloudTranscriptionService
  ) async throws -> String {
    try Task.checkCancellation()
    let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
      throw CloudTranscriptionError.missingAPIKey(provider: service.providerName)
    }

    let request = try CloudTranscriptionRequestBuilder.makeRequest(
      audioURL: audioURL,
      apiKey: apiKey,
      service: service
    )

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await client.data(for: request)
      try Task.checkCancellation()
    } catch {
      if Task.isCancelled { throw CancellationError() }
      throw CloudTranscriptionError.requestFailed(
        provider: service.providerName,
        message: error.localizedDescription
      )
    }

    guard let http = response as? HTTPURLResponse else {
      throw CloudTranscriptionError.invalidResponse(provider: service.providerName)
    }
    guard 200..<300 ~= http.statusCode else {
      let message =
        CloudTranscriptionResponseDecoder.providerErrorMessage(
          from: data,
          apiKey: apiKey
        ) ?? "HTTP \(http.statusCode)"
      throw CloudTranscriptionError.requestFailed(
        provider: service.providerName,
        message: message
      )
    }

    guard let text = CloudTranscriptionResponseDecoder.transcript(from: data) else {
      throw CloudTranscriptionError.invalidResponse(provider: service.providerName)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum CloudTranscriptionRequestBuilder {
  static func makeRequest(
    audioURL: URL,
    apiKey: String,
    service: CloudTranscriptionService,
    boundary: String = "FreeFlow-\(UUID().uuidString)"
  ) throws -> URLRequest {
    var request = URLRequest(url: service.endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type"
    )
    request.httpBody = try multipartBody(
      audioURL: audioURL,
      fields: service.multipartFields,
      boundary: boundary
    )
    return request
  }

  private static func multipartBody(
    audioURL: URL,
    fields: [(name: String, value: String)],
    boundary: String
  ) throws -> Data {
    var body = Data()
    for field in fields {
      body.appendUTF8("--\(boundary)\r\n")
      body.appendUTF8("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
      body.appendUTF8("\(field.value)\r\n")
    }

    // xAI requires the file to be the final multipart field. Keeping this
    // ordering for every provider also preserves the existing OpenAI request.
    body.appendUTF8("--\(boundary)\r\n")
    body.appendUTF8(
      "Content-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\n"
    )
    body.appendUTF8("Content-Type: audio/wav\r\n\r\n")
    body.append(try Data(contentsOf: audioURL))
    body.appendUTF8("\r\n--\(boundary)--\r\n")
    return body
  }
}

enum CloudTranscriptionResponseDecoder {
  private struct Transcript: Decodable {
    let text: String
  }

  static func transcript(from data: Data) -> String? {
    try? JSONDecoder().decode(Transcript.self, from: data).text
  }

  static func providerErrorMessage(from data: Data, apiKey: String) -> String? {
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else { return nil }

    let message: String?
    if let error = dictionary["error"] as? [String: Any] {
      message = error["message"] as? String
    } else if let error = dictionary["error"] as? String {
      message = error
    } else {
      message =
        dictionary["message"] as? String
        ?? dictionary["detail"] as? String
        ?? dictionary["err_msg"] as? String
    }

    guard let message else { return nil }
    let singleLine =
      message
      .components(separatedBy: .newlines)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !singleLine.isEmpty else { return nil }
    let redacted = singleLine.replacingOccurrences(of: apiKey, with: "[redacted]")
    return String(redacted.prefix(240))
  }
}

extension Data {
  fileprivate mutating func appendUTF8(_ string: String) {
    append(Data(string.utf8))
  }
}
