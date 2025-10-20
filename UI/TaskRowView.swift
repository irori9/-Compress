import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TaskRowView: View {
    @EnvironmentObject private var queue: TaskQueue
    @ObservedObject var task: ArchiveTask
    var onCancel: (() -> Void)?

    @State private var showingPasswordSheet = false
    @State private var passwordInput: String = ""
    @State private var rememberPassword: Bool = false
    @State private var expanded: Bool = false
    @FocusState private var pwFocused: Bool

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
                Button(action: { withAnimation { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            ProgressView(value: task.progress)
                .tint(.blue)
                .animation(.easeInOut(duration: 0.2), value: task.progress)
                .accessibilityLabel(Text("Progress"))
                .accessibilityValue(Text(progressText))

            HStack(spacing: 12) {
                Label(progressText, systemImage: "percent")
                Label(speedText, systemImage: "speedometer")
                Label(etaText, systemImage: "hourglass")
                Spacer()
                if task.state == .running {
                    Button(action: { queue.pause(taskID: task.id) }) {
                        Label(NSLocalizedString("pause", comment: ""), systemImage: "pause.fill")
                    }
                    .buttonStyle(.borderless)
                } else if task.state == .paused || task.state == .failed || task.state == .pending {
                    Button(action: { queue.resume(taskID: task.id) }) {
                        Label(NSLocalizedString("resume", comment: ""), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderless)
                }
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

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(NSLocalizedString("priority", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { task.priority }, set: { queue.setPriority(taskID: task.id, priority: $0) })) {
                            Text(NSLocalizedString("high", comment: "")).tag(ArchiveTaskPriority.high)
                            Text(NSLocalizedString("normal", comment: "")).tag(ArchiveTaskPriority.normal)
                            Text(NSLocalizedString("low", comment: "")).tag(ArchiveTaskPriority.low)
                        }
                        .pickerStyle(.segmented)
                    }
                    if let current = task.currentFileName {
                        Text("当前文件: \(current)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let total = task.totalItems {
                        Text("条目数: \(total)").font(.caption).foregroundStyle(.secondary)
                    }
                    if !task.errorDetails.isEmpty {
                        Text("错误列表:").font(.caption).bold()
                        ForEach(task.errorDetails, id: \.self) { e in
                            Text(e).font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button(NSLocalizedString("retry", comment: "")) {
                                showingPasswordSheet = true
                            }
                            Button(NSLocalizedString("skip", comment: "")) {
                                // Mark as completed (skipped)
                                task.state = .completed
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
                .transition(.opacity)
            }
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
                queue.schedule()
            }
        }
        .onChange(of: task.state) { _, newState in
            if newState == .failed, let msg = task.errorMessage, msg.contains("密码") {
                showingPasswordSheet = true
                #if canImport(UIKit)
                let gen = UINotificationFeedbackGenerator(); gen.notificationOccurred(.error)
                #endif
            } else if newState == .completed {
                #if canImport(UIKit)
                let gen = UINotificationFeedbackGenerator(); gen.notificationOccurred(.success)
                #endif
            }
        }
        .sheet(isPresented: $showingPasswordSheet) {
            VStack(spacing: 16) {
                Text(NSLocalizedString("need_password", comment: ""))
                    .font(.headline)
                HStack(spacing: 8) {
                    SecureField(NSLocalizedString("enter_password", comment: ""), text: $passwordInput)
                        .textFieldStyle(.roundedBorder)
                        .focused($pwFocused)
                    #if canImport(UIKit)
                    if let clip = UIPasteboard.general.string, !clip.isEmpty {
                        Button(NSLocalizedString("paste_from_clipboard", comment: "")) {
                            passwordInput = clip
                        }
                        .buttonStyle(.bordered)
                    }
                    #endif
                }
                Toggle(NSLocalizedString("remember_password", comment: ""), isOn: $rememberPassword)
                if task.failedAttempts >= 3 {
                    Text(NSLocalizedString("failed_attempts_limit", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        showingPasswordSheet = false
                    }
                    Spacer()
                    Button(NSLocalizedString("retry", comment: "")) {
                        showingPasswordSheet = false
                        if rememberPassword { PasswordStore.shared.setPassword(passwordInput, for: .file(task.sourceURL)) }
                        ExtractionExecutor.shared.retry(queue: queue, task: task, password: passwordInput)
                    }
                    .disabled(passwordInput.isEmpty || task.failedAttempts >= 5)
                }
            }
            .padding()
            .onAppear { pwFocused = true }
            .presentationDetents([.height(220)])
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
