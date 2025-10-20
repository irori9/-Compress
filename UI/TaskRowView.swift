import SwiftUI

struct TaskRowView: View {
    @ObservedObject var task: ArchiveTask
    var onCancel: (() -> Void)?

    private var progressText: String {
        String(format: "%.0f%%", task.progress * 100)
    }

    private var speedText: String {
        guard let bps = task.bytesPerSecond else { return "--" }
        if bps > 1_000_000 { return String(format: "%.1f MB/s", bps / 1_000_000) }
        if bps > 1_000 { return String(format: "%.1f KB/s", bps / 1_000) }
        return String(format: "%.0f B/s", bps)
    }

    private var etaText: String {
        guard let eta = task.estimatedRemainingTime else { return "--" }
        let seconds = Int(eta)
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.sourceURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(task.state.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: task.progress)
                .tint(.blue)

            HStack(spacing: 12) {
                Label(progressText, systemImage: "percent")
                Label(speedText, systemImage: "speedometer")
                Label(etaText, systemImage: "hourglass")
                Spacer()
                if task.canCancel {
                    Button(action: { onCancel?() }) {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

struct TaskRowView_Previews: PreviewProvider {
    static var previews: some View {
        let task = ArchiveTask(sourceURL: URL(fileURLWithPath: "/tmp/demo.zip"), destinationURL: URL(fileURLWithPath: "/tmp/out"))
        task.progress = 0.42
        task.bytesPerSecond = 1_234_567
        task.estimatedRemainingTime = 87
        return TaskRowView(task: task)
            .padding()
            .background(
                LinearGradient(colors: [.cyan.opacity(0.4), .blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
    }
}
