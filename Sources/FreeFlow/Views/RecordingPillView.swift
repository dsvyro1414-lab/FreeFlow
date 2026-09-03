import SwiftUI

struct RecordingPillView: View {
  @ObservedObject var model: PillPresentationModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let waveformShape: [CGFloat] = [
    0.28, 0.48, 0.72, 0.92, 0.58, 1, 0.64, 0.88, 0.68, 0.44, 0.26,
  ]

  private var width: CGFloat {
    switch model.phase {
    case .recording: 98
    case .downloading: 116
    case .processing: 52
    case .success: 70
    case .failure: 64
    case .hidden: 38
    }
  }

  var body: some View {
    phaseContent
      .padding(.horizontal, 8)
      .frame(width: width, height: 28)
      .background(Color.black.opacity(0.96), in: Capsule())
      .overlay {
        Capsule()
          .strokeBorder(.white.opacity(0.22), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.24), radius: 6, y: 2)
      .animation(
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.84),
        value: width
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(model.label)
  }

  @ViewBuilder
  private var phaseContent: some View {
    switch model.phase {
    case .recording:
      HStack(spacing: 3) {
        ForEach(Self.waveformShape.indices, id: \.self) { index in
          Capsule()
            .fill(.white.opacity(0.96))
            .frame(
              width: 2.25,
              height: waveformHeight(at: index)
            )
        }
      }
      .animation(
        reduceMotion ? nil : .easeOut(duration: 0.07),
        value: model.audioLevel
      )
    case .downloading(let progress):
      HStack(spacing: 6) {
        ProgressView(value: progress)
          .progressViewStyle(.circular)
          .controlSize(.small)
          .tint(.white)
        Text(progress > 0 ? "Downloading \(Int(progress * 100))%" : "Downloading")
          .font(.system(size: 9, weight: .medium, design: .rounded))
          .lineLimit(1)
      }
      .foregroundStyle(.white)
    case .processing:
      ProgressView()
        .controlSize(.small)
        .tint(.white)
    case .success:
      statusLabel(systemImage: "checkmark", text: model.label, color: .white)
    case .failure:
      statusLabel(systemImage: "exclamationmark", text: model.label, color: .orange)
    case .hidden:
      EmptyView()
    }
  }

  private func waveformHeight(at index: Int) -> CGFloat {
    let level = reduceMotion ? 0 : CGFloat(min(max(model.audioLevel, 0), 1))
    let response = pow(level, 0.72)
    return 2.25 + response * (3 + Self.waveformShape[index] * 8)
  }

  private func statusLabel(systemImage: String, text: String, color: Color) -> some View {
    HStack(spacing: 5) {
      Image(systemName: systemImage)
        .font(.system(size: 9, weight: .bold))
      Text(text)
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .lineLimit(1)
    }
    .foregroundStyle(color)
  }
}
