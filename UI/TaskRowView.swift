import SwiftUI

struct TaskRowView: View {
    @EnvironmentObject private var queue: TaskQueue
    @ObservedObject var task: ArchiveTask
    var onCancel: (() -> Void)?

    @State private var showingPasswordSheet = false
    @State private var passwordInput: String = ""

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
                    Button(action: { onCancel?(); ExtractionExecutor.shared.cancel(task: task); queue.cancel(taskID: task.id) }) {
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
        .onAppear {
            if task.state == .pending {
                ExtractionExecutor.shared.ensureStarted(queue: queue, task: task)
            }
        }
        .onChange(of: task.state) { _, newState in
            if newState == .failed, let msg = task.errorMessage, msg.contains("密码") {
                showingPasswordSheet = true
            }
        }
        .sheet(isPresented: $showingPasswordSheet) {
            VStack(spacing: 16) {
                Text("需要密码")
                    .font(.headline)
                SecureField("输入密码", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("取消") {
                        showingPasswordSheet = false
                    }
                    Spacer()
                    Button("重试") {
                        showingPasswordSheet = false
                        ExtractionExecutor.shared.retry(queue: queue, task: task, password: passwordInput)
                    }
                    .disabled(passwordInput.isEmpty)
                }
            }
            .padding()
            .presentationDetents([.height(180)])
        }
    }
}

struct TaskRowView_Previews: PreviewProvider {
    static var previews: some View {
        let task = ArchiveTask(sourceURL: URL(fileURLWithPath: "/tmp/demo.zip"), destinationURL: URL(fileURLWithPath: "/tmp/out"))
        task.progress = 0.42
        task.bytesPerSecond = 1_234_567
        task.estimatedRemainingTime = 87
        return TaskRowView(task: task)
            .environmentObject(TaskQueue())
            .padding()
            .background(
                LinearGradient(colors: [.cyan.opacity(0.4), .blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
    }
}
