import FreeFlowCloud
import SwiftUI

struct CloudCredentialEditor: View {
  private enum Feedback {
    case success(String)
    case failure(String)

    var message: String {
      switch self {
      case .success(let message), .failure(let message): message
      }
    }

    var color: Color {
      switch self {
      case .success: .secondary
      case .failure: .red
      }
    }
  }

  let provider: CloudAPIProvider
  let isConfigured: Bool
  let save: (String) throws -> Void
  let delete: () throws -> Void

  @State private var apiKey = ""
  @State private var feedback: Feedback?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("\(provider.title) API key")
        Spacer()
        if isConfigured {
          Label("Saved", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.green)
        }
      }

      SecureField(
        "\(provider.title) API key",
        text: Binding(
          get: { apiKey },
          set: { value in
            apiKey = value
            feedback = nil
          }
        )
      )
      .labelsHidden()
      .textFieldStyle(.roundedBorder)
      .frame(maxWidth: .infinity)

      HStack {
        Button("Save Key") {
          do {
            try save(apiKey)
            apiKey = ""
            feedback = .success("Saved securely in Keychain.")
          } catch {
            feedback = .failure(error.localizedDescription)
          }
        }
        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Save \(provider.title) API key")

        if isConfigured {
          Button("Delete Key", role: .destructive) {
            do {
              try delete()
              apiKey = ""
              feedback = .success("Key deleted.")
            } catch {
              feedback = .failure(error.localizedDescription)
            }
          }
          .accessibilityLabel("Delete \(provider.title) API key")
        }
      }

      if let feedback {
        Text(feedback.message)
          .font(.caption)
          .foregroundStyle(feedback.color)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}
