import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var selectedTab: AppTab = .library
    @State private var showingPicker = false
    @State private var pendingPickedURLs: [URL] = []
    @State private var pickerReturnedNoFiles = false

    var body: some View {
        ZStack {
            AuroraBackground()

            TabView(selection: $selectedTab) {
                LibraryHomeView(
                    onImport: { showingPicker = true },
                    onOpenSearch: { selectedTab = .search }
                )
                .tag(AppTab.library)

                SearchView()
                    .tag(AppTab.search)

                EffectsView()
                    .tag(AppTab.effects)

                SettingsView {
                    selectedTab = .effects
                }
                .tag(AppTab.settings)
            }
            .toolbar(.hidden, for: .tabBar)
            .tint(AppTheme.ice)

            if library.isImporting {
                ImportOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(20)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerDock(selectedTab: $selectedTab)
        }
        .alert(item: $library.importAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
        .sheet(
            isPresented: $showingPicker,
            onDismiss: processPendingPickedFiles
        ) {
            DocumentPicker(
                onPick: queuePickedFiles,
                onCancel: { showingPicker = false }
            )
            .ignoresSafeArea()
            .interactiveDismissDisabled()
        }
        .animation(.easeInOut(duration: 0.24), value: library.isImporting)
        .animation(.easeInOut(duration: 0.24), value: themeManager.mode)
    }

    private func queuePickedFiles(_ urls: [URL]) {
        pendingPickedURLs = urls
        pickerReturnedNoFiles = urls.isEmpty
        showingPicker = false

        if !urls.isEmpty {
            Task { @MainActor in
                processPendingPickedFiles()
            }
        }
    }

    private func processPendingPickedFiles() {
        if pickerReturnedNoFiles {
            pickerReturnedNoFiles = false
            pendingPickedURLs = []
            library.reportEmptySelection()
            return
        }

        guard !pendingPickedURLs.isEmpty else { return }
        let urls = pendingPickedURLs
        pendingPickedURLs = []

        Task { @MainActor in
            await library.importFiles(urls)
        }
    }
}

private struct ImportOverlay: View {
    @EnvironmentObject private var library: MusicLibrary

    var body: some View {
        ZStack {
            Color.black.opacity(0.36)
                .ignoresSafeArea()

            VStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(AppTheme.ice.opacity(0.16))
                        .frame(width: 54, height: 54)

                    ProgressView()
                        .tint(AppTheme.ice)
                        .scaleEffect(1.1)
                }

                Text("正在导入音乐")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                if let progress = library.importProgress {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.ice)
                        .frame(width: 190)

                    Text(progress.fileName)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: 220)

                    Text(progress.statusText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme.textTertiary)
                } else {
                    Text("正在准备文件")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Button {
                    library.cancelImport()
                } label: {
                    Text(library.isImportCancelling ? "正在取消…" : "取消导入")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(AppTheme.controlFill, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(AppTheme.hairline.opacity(0.6), lineWidth: 0.6)
                        }
                }
                .buttonStyle(.plain)
                .disabled(library.isImportCancelling)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 25)
            .glassPanel(cornerRadius: 28, tint: AppTheme.ice, strokeOpacity: 0.22)
        }
    }
}
