import Foundation
import XCTest

@testable import FreeFlowCloud

final class CloudTranscriberTests: XCTestCase {
  func testMissingKeyFailsBeforeAudioReadOrTransport() async {
    let client = StubHTTPClient(
      outcome: .failure(.notConnectedToInternet)
    )
    do {
      _ = try await CloudTranscriber(client: client).transcribe(
        URL(fileURLWithPath: "/private/tmp/freeflow-intentionally-missing.wav"),
        apiKey: "  \n",
        service: .xAI
      )
      XCTFail("Expected a missing-key error")
    } catch {
      XCTAssertEqual(
        error as? CloudTranscriptionError,
        .missingAPIKey(provider: "xAI (Grok)")
      )
    }
    let callCount = await client.numberOfCalls()
    XCTAssertEqual(callCount, 0)
  }

  func testCredentialAccountsAreUniqueAndPreserveOpenAILegacyLocator() {
    XCTAssertEqual(CloudAPIProvider.openAI.keychainAccount, "openai-api-key")
    XCTAssertEqual(
      Set(CloudAPIProvider.allCases.map(\.keychainAccount)).count,
      CloudAPIProvider.allCases.count
    )
  }

  func testEveryServiceSelectsItsOwnCredentialProvider() {
    XCTAssertEqual(
      CloudTranscriptionService.openAI(model: "model").credentialProvider,
      .openAI
    )
    XCTAssertEqual(CloudTranscriptionService.xAI.credentialProvider, .xAI)
    XCTAssertEqual(
      CloudTranscriptionService.groq(model: "model").credentialProvider,
      .groq
    )
  }

  func testOpenAIRequestPreservesLegacyWireContract() throws {
    let audioURL = try makeAudioFile()
    let request = try CloudTranscriptionRequestBuilder.makeRequest(
      audioURL: audioURL,
      apiKey: "openai-test-key",
      service: .openAI(model: "gpt-4o-mini-transcribe"),
      boundary: "test-boundary"
    )

    XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-test-key")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Content-Type"),
      "multipart/form-data; boundary=test-boundary"
    )

    let body = try requestBody(request)
    XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-4o-mini-transcribe"))
    XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nen"))
    XCTAssertFalse(body.contains("name=\"format\""))
    XCTAssertFalse(body.contains("name=\"response_format\""))
    try assertFileIsFinalField(in: body)
  }

  func testXAIRequestPlacesRequiredOptionsBeforeFinalFile() throws {
    let audioURL = try makeAudioFile()
    let request = try CloudTranscriptionRequestBuilder.makeRequest(
      audioURL: audioURL,
      apiKey: "xai-test-key",
      service: .xAI,
      boundary: "test-boundary"
    )

    XCTAssertEqual(request.url?.absoluteString, "https://api.x.ai/v1/stt")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xai-test-key")

    let body = try requestBody(request)
    XCTAssertTrue(body.contains("name=\"format\"\r\n\r\ntrue"))
    XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nen"))
    XCTAssertTrue(body.contains("name=\"filler_words\"\r\n\r\ntrue"))
    XCTAssertFalse(body.contains("name=\"model\""))
    try assertFileIsFinalField(in: body)
  }

  func testGroqRequestUsesWhisperModelAndGroqEndpoint() throws {
    let audioURL = try makeAudioFile()
    let request = try CloudTranscriptionRequestBuilder.makeRequest(
      audioURL: audioURL,
      apiKey: "groq-test-key",
      service: .groq(model: "whisper-large-v3-turbo"),
      boundary: "test-boundary"
    )

    XCTAssertEqual(
      request.url?.absoluteString,
      "https://api.groq.com/openai/v1/audio/transcriptions"
    )
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer groq-test-key")

    let body = try requestBody(request)
    XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nwhisper-large-v3-turbo"))
    XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nen"))
    try assertFileIsFinalField(in: body)
  }

  func testSharedTranscriptDecoderAcceptsProviderSuccessShape() throws {
    let data = try XCTUnwrap(#"{"text":"  dictated text  "}"#.data(using: .utf8))
    XCTAssertEqual(CloudTranscriptionResponseDecoder.transcript(from: data), "  dictated text  ")
  }

  func testProviderErrorDecoderRedactsKeyAndFlattensNewlines() throws {
    let data = try XCTUnwrap(
      #"{"error":{"message":"Rejected test-secret\nTry again"}}"#.data(using: .utf8)
    )
    XCTAssertEqual(
      CloudTranscriptionResponseDecoder.providerErrorMessage(
        from: data,
        apiKey: "test-secret"
      ),
      "Rejected [redacted] Try again"
    )
  }

  func testProviderErrorDecoderAcceptsRootMessage() throws {
    let data = try XCTUnwrap(#"{"message":"Invalid credentials"}"#.data(using: .utf8))
    XCTAssertEqual(
      CloudTranscriptionResponseDecoder.providerErrorMessage(from: data, apiKey: "unused"),
      "Invalid credentials"
    )
  }

  func testInjectedTransportReturnsTrimmedTranscript() async throws {
    let audioURL = try makeAudioFile()
    let response = try httpResponse(statusCode: 200)
    let client = StubHTTPClient(
      outcome: .response(Data(#"{"text":"  dictated text  "}"#.utf8), response)
    )

    let transcript = try await CloudTranscriber(client: client).transcribe(
      audioURL,
      apiKey: "test-key",
      service: .groq(model: "whisper-large-v3-turbo")
    )

    XCTAssertEqual(transcript, "dictated text")
    let callCount = await client.numberOfCalls()
    XCTAssertEqual(callCount, 1)
  }

  func testNonSuccessResponseUsesRedactedProviderError() async throws {
    let audioURL = try makeAudioFile()
    let response = try httpResponse(statusCode: 401)
    let client = StubHTTPClient(
      outcome: .response(
        Data(#"{"error":{"message":"Rejected test-key"}}"#.utf8),
        response
      )
    )

    do {
      _ = try await CloudTranscriber(client: client).transcribe(
        audioURL,
        apiKey: "test-key",
        service: .xAI
      )
      XCTFail("Expected a request failure")
    } catch {
      XCTAssertEqual(
        error as? CloudTranscriptionError,
        .requestFailed(provider: "xAI (Grok)", message: "Rejected [redacted]")
      )
    }
  }

  func testTransportErrorIsProviderScoped() async throws {
    let audioURL = try makeAudioFile()
    let client = StubHTTPClient(
      outcome: .failure(.notConnectedToInternet)
    )

    do {
      _ = try await CloudTranscriber(client: client).transcribe(
        audioURL,
        apiKey: "test-key",
        service: .openAI(model: "gpt-4o-mini-transcribe")
      )
      XCTFail("Expected a transport failure")
    } catch let error as CloudTranscriptionError {
      guard case .requestFailed(let provider, let message) = error else {
        return XCTFail("Expected a provider-scoped request failure")
      }
      XCTAssertEqual(provider, "OpenAI")
      XCTAssertFalse(message.isEmpty)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testCancellationAfterTransportDoesNotReturnTranscript() async throws {
    let audioURL = try makeAudioFile()
    let response = try httpResponse(statusCode: 200)
    let client = CancellingHTTPClient(
      data: Data(#"{"text":"must not escape"}"#.utf8),
      response: response
    )

    do {
      _ = try await CloudTranscriber(client: client).transcribe(
        audioURL,
        apiKey: "test-key",
        service: .openAI(model: "gpt-4o-mini-transcribe")
      )
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func makeAudioFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("FreeFlowCloudTests-\(UUID().uuidString).wav")
    try Data("test-audio".utf8).write(to: url, options: .atomic)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func requestBody(_ request: URLRequest) throws -> String {
    let data = try XCTUnwrap(request.httpBody)
    return try XCTUnwrap(String(data: data, encoding: .utf8))
  }

  private func httpResponse(statusCode: Int) throws -> HTTPURLResponse {
    try XCTUnwrap(
      HTTPURLResponse(
        url: URL(string: "https://provider.example/v1/stt")!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      )
    )
  }

  private func assertFileIsFinalField(in body: String) throws {
    let file = try XCTUnwrap(body.range(of: "name=\"file\""))
    let earlierFields = body[..<file.lowerBound]
    let laterFields = body[file.upperBound...]
    XCTAssertTrue(earlierFields.contains("name="))
    XCTAssertFalse(laterFields.contains("Content-Disposition: form-data; name="))
    XCTAssertTrue(body.hasSuffix("\r\n--test-boundary--\r\n"))
  }
}

private actor StubHTTPClient: CloudHTTPClient {
  enum Outcome: @unchecked Sendable {
    case response(Data, URLResponse)
    case failure(URLError.Code)
  }

  private let outcome: Outcome
  private var calls = 0

  init(outcome: Outcome) {
    self.outcome = outcome
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    calls += 1
    switch outcome {
    case .response(let data, let response):
      return (data, response)
    case .failure(let code):
      throw URLError(code)
    }
  }

  func numberOfCalls() -> Int {
    calls
  }
}

private struct CancellingHTTPClient: CloudHTTPClient {
  let data: Data
  let response: URLResponse

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    withUnsafeCurrentTask { task in
      task?.cancel()
    }
    return (data, response)
  }
}
