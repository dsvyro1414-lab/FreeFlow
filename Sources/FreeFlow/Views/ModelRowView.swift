import SwiftUI

struct ModelRowView: View {
  let title: String
  let subtitle: String
  let status: ModelStatus
  let isAvailable: Bool
  let download: () -> Void
  let remove: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .fontWeight(.medium)
        Text(isAvailable ? subtitle : "Unavailable on this Mac")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      statusControl
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var statusControl: some View {
    switch status {
    case .notDownloaded:
      Button("Download", action: download)
        .disabled(!isAvailable)
    case .downloading(let progress):
      ProgressView(value: progress)
        .frame(width: 84)
    case .ready:
      HStack(spacing: 8) {
        Label("Ready", systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.green)
        Button("Remove", action: remove)
      }
    case .failed:
      Button("Retry", action: download)
        .disabled(!isAvailable)
    }
  }
}
