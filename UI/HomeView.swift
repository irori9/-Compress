import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var queue: TaskQueue
    @State private var showingPicker = false

    var body: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()

            VStack(spacing: 24) {
                header

                Button(action: { showingPicker = true }) {
                    Label(NSLocalizedString("import_archives", comment: ""), systemImage: "tray.and.arrow.down")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                }
                .keyboardShortcut("n", modifiers: [.command])
                .accessibilityLabel(Text(NSLocalizedString("import_archives", comment: "")))

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if queue.tasks.isEmpty {
                            emptyState
                        } else {
                            ForEach(queue.tasks) { task in
                                TaskRowView(task: task) {
                                    queue.cancel(taskID: task.id)
                                }
                                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, 48)
            .padding(.bottom, 24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        PasswordStore.shared.clearAll()
                    } label: {
                        Label(NSLocalizedString("clear_saved_passwords", comment: ""), systemImage: "key.fill")
                    }
                    .tint(.orange)
                    .accessibilityLabel(Text(NSLocalizedString("clear_saved_passwords", comment: "")))
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            DocumentPickerView { urls in
                for url in urls {
                    _ = queue.addTask(from: url)
                }
                showingPicker = false
            }
        }
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.cyan.opacity(0.6), Color.blue.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 40)

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 280, height: 280)
                .offset(x: -120, y: -180)
                .blur(radius: 8)

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 220, height: 220)
                .offset(x: 140, y: 160)
                .blur(radius: 8)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("app_title", comment: ""))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(NSLocalizedString("subtitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("no_tasks", comment: ""))
                .font(.headline)
            Text(NSLocalizedString("tap_import_to_start", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
        )
        .padding(.top, 40)
    }
}

#Preview {
    HomeView().environmentObject(TaskQueue())
}
